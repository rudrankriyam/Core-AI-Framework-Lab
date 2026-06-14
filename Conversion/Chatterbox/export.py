import argparse
import gc
import shutil
import tempfile
import time
from dataclasses import dataclass
from pathlib import Path

import torch
from coreai.runtime import AIModelAssetMetadata
from coreai_opt.base_model_compressor import ExportBackend
from coreai_opt.quantization import Quantizer, QuantizerConfig
from coreai_torch import TorchConverter, get_decomp_table

from coreai_state import register_cache_lowering
from encoders import (
    CoreAICompatibleVoiceEncoder,
    create_speaker_encoder,
    create_voice_encoder,
    speaker_encoder_reference_inputs,
    voice_encoder_reference_inputs,
)
from vocoder import (
    CoreAICompatibleVocoder,
    load_chatterbox_vocoder,
    reference_inputs,
)
from t3 import (
    T3_CONDITION_TOKEN_COUNT,
    T3_HIDDEN_SIZE,
    T3_MAX_CONTEXT_LENGTH,
    create_cache_tensors,
    load_t3_embedding_modules,
    load_t3_transformer,
)
from s3gen import (
    S3GEN_GENERATED_TOKENS,
    S3GEN_TOTAL_MEL_FRAMES,
    load_s3gen_model,
    reference_inputs as s3gen_reference_inputs,
)

DEFAULT_REPO_ID = "ResembleAI/chatterbox-turbo"
CONDITIONALS_CHECKPOINT = "conds.pt"
T3_CHECKPOINT = "t3_turbo_v1.safetensors"
VOICE_CHECKPOINT = "ve.safetensors"
VOCODER_CHECKPOINT = "s3gen_meanflow.safetensors"


@dataclass(frozen=True)
class Stage:
    entrypoint: str
    source_component: str
    purpose: str


STAGES = (
    Stage("voice_encoder", "model.ve", "Reference voice embedding for T3."),
    Stage("speech_tokenizer", "model.s3gen.tokenizer", "Reference audio to S3 tokens."),
    Stage("speaker_encoder", "model.s3gen.speaker_encoder", "Reference x-vector for S3Gen."),
    Stage("t3_prefill", "model.t3", "Text and conditioning prefill with explicit KV outputs."),
    Stage("t3_decode", "model.t3", "One autoregressive speech-token decode step."),
    Stage("s3gen", "model.s3gen.flow", "Speech tokens to mel with the two-step mean-flow decoder."),
    Stage("vocoder", "model.s3gen.mel2wav", "Mel frames to a 24 kHz waveform."),
)


class IdentityProbe(torch.nn.Module):
    def forward(self, value: torch.Tensor) -> torch.Tensor:
        return value


def build_metadata(description: str) -> AIModelAssetMetadata:
    metadata = AIModelAssetMetadata()
    metadata.author = "Resemble AI; Core AI conversion by Core AI Framework Lab"
    metadata.license = "MIT"
    metadata.model_description = description
    metadata.creation_date = int(time.time())
    return metadata


def save_program(program, output_path: Path, overwrite: bool, description: str) -> None:
    if output_path.exists():
        if not overwrite:
            raise FileExistsError(
                f"{output_path} already exists. Pass --overwrite to replace it."
            )
        if output_path.is_dir():
            shutil.rmtree(output_path)
        else:
            output_path.unlink()

    output_path.parent.mkdir(parents=True, exist_ok=True)
    program.save_asset(output_path, build_metadata(description))


def create_contract_probe(output_path: Path, overwrite: bool) -> None:
    """Create a tiny multi-function asset that validates the Swift app plumbing."""
    module = IdentityProbe().eval()
    sample = (torch.zeros((1, 1), dtype=torch.float16),)
    converter = TorchConverter()

    for stage in STAGES:
        exported = torch.export.export(module, args=sample)
        exported = exported.run_decompositions(get_decomp_table())
        converter.add_exported_program(
            exported_program=exported,
            input_names=["input"],
            output_names=["output"],
            entrypoint_name=stage.entrypoint,
        )

    program = converter.to_coreai()
    program.optimize()
    save_program(
        program,
        output_path,
        overwrite,
        "A tiny seven-entrypoint Core AI asset for testing the Chatterbox app "
        "contract. It does not synthesize speech.",
    )
    print(f"[OK] Wrote contract probe to {output_path}")


def inspect_source_model() -> None:
    """Download Chatterbox Turbo and verify the modules expected by the plan."""
    from chatterbox.tts_turbo import ChatterboxTurboTTS

    print("[INFO] Loading ResembleAI/chatterbox-turbo on CPU...")
    model = ChatterboxTurboTTS.from_pretrained(device="cpu")
    components = {
        "voice_encoder": model.ve,
        "speech_tokenizer": model.s3gen.tokenizer,
        "speaker_encoder": model.s3gen.speaker_encoder,
        "t3": model.t3,
        "s3gen": model.s3gen.flow,
        "vocoder": model.s3gen.mel2wav,
    }

    for name, component in components.items():
        parameter_count = sum(parameter.numel() for parameter in component.parameters())
        print(f"{name:18} {type(component).__name__:32} {parameter_count:>12,} parameters")


def resolve_checkpoint(
    repo_id: str,
    filename: str,
    checkpoint_path: Path | None,
) -> Path:
    if checkpoint_path is not None:
        if not checkpoint_path.is_file():
            raise FileNotFoundError(checkpoint_path)
        return checkpoint_path

    from huggingface_hub import hf_hub_download

    print(f"[INFO] Downloading {repo_id}/{filename}...")
    return Path(hf_hub_download(repo_id, filename))


def load_compatible_vocoder(
    checkpoint_path: Path,
    *,
    dtype: torch.dtype = torch.float32,
) -> CoreAICompatibleVocoder:
    print(f"[INFO] Loading the 328 mel2wav tensors from {checkpoint_path}...")
    vocoder = load_chatterbox_vocoder(checkpoint_path, dtype=dtype)
    return CoreAICompatibleVocoder(vocoder).eval().to(dtype=dtype)


def export_program(
    model: torch.nn.Module,
    example_inputs: tuple[torch.Tensor, ...],
    dynamic_shapes=None,
) -> torch.export.ExportedProgram:
    exported = torch.export.export(
        model,
        args=example_inputs,
        dynamic_shapes=dynamic_shapes,
    )
    return exported.run_decompositions(get_decomp_table())


def quantize_t3_transformer(
    model: torch.nn.Module,
    example_inputs: tuple[torch.Tensor, ...],
    *,
    block_size: int,
    mmap_dir: Path,
) -> torch.nn.Module:
    """Apply Apple's macOS INT4 weight format while retaining sensitive layers."""
    config = QuantizerConfig.from_dict(
        {
            "quantization_config": {
                "execution_mode": "eager",
                "global_config": {
                    "op_state_spec": {
                        "weight": {
                            "dtype": "int4",
                            "qscheme": "symmetric_with_clipping",
                            "granularity": {
                                "type": "per_block",
                                "block_size": block_size,
                                "axis": 1,
                            },
                        }
                    },
                    "op_input_spec": None,
                    "op_output_spec": None,
                },
            }
        }
    )
    int8_config = QuantizerConfig.from_dict(
        {
            "quantization_config": {
                "execution_mode": "eager",
                "global_config": {
                    "op_state_spec": {
                        "weight": {
                            "dtype": "int8",
                            "qscheme": "symmetric_with_clipping",
                            "granularity": {
                                "type": "per_channel",
                                "axis": 1,
                            },
                        }
                    },
                    "op_input_spec": None,
                    "op_output_spec": None,
                },
            }
        }
    )

    # These weights are tiny relative to the backbone and disproportionately
    # affect speech-token ranking and error accumulation during autoregression.
    config.set_module_name("position_embedding", None)
    config.set_module_name("speech_head", int8_config.global_config)
    config.set_module_name("blocks.0", None)
    config.set_module_name("blocks.23", None)

    quantizer = Quantizer(model, config)
    prepared = quantizer.prepare(example_inputs=example_inputs)
    return quantizer.finalize(
        prepared,
        backend=ExportBackend.CoreAI,
        mmap_dir=mmap_dir,
    ).eval()


def add_voice_encoder(
    converter: TorchConverter,
    checkpoint_path: Path,
) -> None:
    print(f"[INFO] Loading voice encoder weights from {checkpoint_path}...")
    model = CoreAICompatibleVoiceEncoder(
        create_voice_encoder(checkpoint_path)
    ).eval()
    converter.add_exported_program(
        exported_program=export_program(model, voice_encoder_reference_inputs()),
        input_names=["mels"],
        output_names=["embedding"],
        entrypoint_name="voice_encoder",
    )


def add_speaker_encoder(
    converter: TorchConverter,
    checkpoint_path: Path,
) -> None:
    print(f"[INFO] Loading speaker encoder weights from {checkpoint_path}...")
    model = create_speaker_encoder(
        checkpoint_path,
        coreai_compatible=True,
    )
    converter.add_exported_program(
        exported_program=export_program(model, speaker_encoder_reference_inputs()),
        input_names=["fbank"],
        output_names=["embedding"],
        entrypoint_name="speaker_encoder",
    )


def add_vocoder(
    converter: TorchConverter,
    checkpoint_path: Path,
    mel_frames: int,
    *,
    dtype: torch.dtype = torch.float16,
) -> None:
    model = load_compatible_vocoder(checkpoint_path, dtype=dtype)
    example_inputs = reference_inputs(mel_frames, dtype=dtype)
    with torch.inference_mode():
        output_shapes = [tuple(value.shape) for value in model(*example_inputs)]
    print(f"[INFO] Vocoder output shapes: {output_shapes}")
    converter.add_exported_program(
        exported_program=export_program(model, example_inputs),
        input_names=["speech_feat", "phase", "noise"],
        output_names=["waveform", "source"],
        entrypoint_name="vocoder",
    )


def validate_vocoder(checkpoint_path: Path, mel_frames: int) -> None:
    torch.manual_seed(0)
    model = load_compatible_vocoder(checkpoint_path, dtype=torch.float32)
    speech_feat, phase, noise = reference_inputs(
        mel_frames,
        dtype=torch.float32,
    )
    speech_feat.normal_()
    noise.normal_()

    with torch.inference_mode():
        f0 = model.vocoder.f0_predictor(speech_feat)
        source = model.build_source(f0, phase, noise)
        expected = model.vocoder.decode(speech_feat, source)
        actual = model.decode(speech_feat, source)

    difference = (expected - actual).abs()
    max_error = difference.max().item()
    mean_error = difference.mean().item()
    if max_error > 2e-5 or mean_error > 5e-6:
        raise RuntimeError(
            "Weighted vocoder parity exceeded the expected error bound: "
            f"max={max_error:.9g}, mean={mean_error:.9g}"
        )

    print(f"[OK] Weighted vocoder max error:  {max_error:.9g}")
    print(f"[OK] Weighted vocoder mean error: {mean_error:.9g}")


def validate_encoders(
    voice_checkpoint_path: Path,
    s3gen_checkpoint_path: Path,
) -> None:
    torch.manual_seed(1)
    voice_encoder = create_voice_encoder(voice_checkpoint_path)
    voice_model = CoreAICompatibleVoiceEncoder(voice_encoder).eval()
    voice_inputs = (torch.rand_like(voice_encoder_reference_inputs()[0]),)
    with torch.inference_mode():
        voice_expected = voice_encoder(*voice_inputs)
        voice_actual = voice_model(*voice_inputs)
    voice_error = (voice_expected - voice_actual).abs().max().item()
    if voice_error != 0:
        raise RuntimeError(f"Voice encoder parity failed: max={voice_error:.9g}")
    print("[OK] Voice encoder max error: 0")

    speaker_encoder = create_speaker_encoder(
        s3gen_checkpoint_path,
        coreai_compatible=False,
    )
    speaker_model = create_speaker_encoder(
        s3gen_checkpoint_path,
        coreai_compatible=True,
    )
    speaker_inputs = (torch.randn_like(speaker_encoder_reference_inputs()[0]),)
    with torch.inference_mode():
        speaker_expected = speaker_encoder(*speaker_inputs)
        speaker_actual = speaker_model(*speaker_inputs)
    difference = (speaker_expected - speaker_actual).abs()
    max_error = difference.max().item()
    mean_error = difference.mean().item()
    if max_error > 1e-5 or mean_error > 3e-6:
        raise RuntimeError(
            "Speaker encoder parity exceeded the expected error bound: "
            f"max={max_error:.9g}, mean={mean_error:.9g}"
        )
    print(f"[OK] Speaker encoder max error:  {max_error:.9g}")
    print(f"[OK] Speaker encoder mean error: {mean_error:.9g}")


def export_vocoder(
    checkpoint_path: Path,
    output_path: Path,
    mel_frames: int,
    overwrite: bool,
) -> None:
    if mel_frames < 1:
        raise ValueError("--mel-frames must be positive")

    print("[INFO] Exporting the weighted Chatterbox HiFT graph...")
    converter = TorchConverter()
    add_vocoder(
        converter,
        checkpoint_path,
        mel_frames,
        dtype=torch.float16,
    )
    print("[INFO] Converting with Apple's coreai-torch TorchConverter...")
    program = converter.to_coreai()

    print("[INFO] Optimizing the Core AI program...")
    program.optimize()
    save_program(
        program,
        output_path,
        overwrite,
        "The weighted Chatterbox Turbo HiFT vocoder converted from PyTorch in "
        "float16 with Apple coreai-torch. The vocoder accepts 80-bin mel frames "
        "plus explicit phase and noise tensors and emits 24 kHz waveform samples.",
    )
    print(f"[OK] Wrote weighted Chatterbox vocoder to {output_path}")


def export_voice_encoder(
    checkpoint_path: Path,
    output_path: Path,
    overwrite: bool,
) -> None:
    converter = TorchConverter()
    add_voice_encoder(converter, checkpoint_path)
    print("[INFO] Converting the voice encoder with Apple coreai-torch...")
    program = converter.to_coreai()
    program.optimize()
    save_program(
        program,
        output_path,
        overwrite,
        "The weighted Chatterbox Turbo reference voice encoder converted from "
        "PyTorch with Apple coreai-torch.",
    )
    print(f"[OK] Wrote Chatterbox voice encoder to {output_path}")


def export_speaker_encoder(
    checkpoint_path: Path,
    output_path: Path,
    overwrite: bool,
) -> None:
    converter = TorchConverter()
    add_speaker_encoder(converter, checkpoint_path)
    print("[INFO] Converting the speaker encoder with Apple coreai-torch...")
    program = converter.to_coreai()
    program.optimize()
    save_program(
        program,
        output_path,
        overwrite,
        "The weighted Chatterbox Turbo S3Gen speaker encoder converted from "
        "PyTorch with Apple coreai-torch.",
    )
    print(f"[OK] Wrote Chatterbox speaker encoder to {output_path}")


def export_t3_embeddings(
    checkpoint_path: Path,
    conditionals_path: Path,
    output_path: Path,
    overwrite: bool,
) -> None:
    print("[INFO] Loading the weighted T3 embedding tables in float16...")
    prefill, decode = load_t3_embedding_modules(
        checkpoint_path,
        conditionals_path,
        dtype=torch.float16,
    )

    text_length = torch.export.Dim(
        "text_length",
        min=1,
        max=256,
    )
    prefill_inputs = (
        torch.zeros((1, 16), dtype=torch.int32),
    )
    decode_inputs = (
        torch.zeros((1, 1), dtype=torch.int32),
    )

    converter = TorchConverter()
    converter.add_exported_program(
        exported_program=export_program(
            prefill,
            prefill_inputs,
            dynamic_shapes=({1: text_length},),
        ),
        input_names=["textTokens"],
        output_names=["inputEmbeddings"],
        entrypoint_name="prefill",
    )
    converter.add_exported_program(
        exported_program=export_program(decode, decode_inputs),
        input_names=["speechToken"],
        output_names=["inputEmbeddings"],
        entrypoint_name="decode",
    )

    del prefill, decode
    gc.collect()

    print("[INFO] Converting the T3 embedding entrypoints...")
    program = converter.to_coreai()
    program.optimize()
    save_program(
        program,
        output_path,
        overwrite,
        "Chatterbox Turbo T3 text and speech embedding entrypoints. The "
        f"prefill function prepends {T3_CONDITION_TOKEN_COUNT} built-in voice "
        "conditioning vectors, and decode embeds one generated speech token.",
    )
    print(f"[OK] Wrote T3 embeddings to {output_path}")


def export_t3_transformer(
    checkpoint_path: Path,
    output_path: Path,
    overwrite: bool,
    max_context_length: int,
    compression: str,
    quantization_block_size: int,
) -> None:
    print("[INFO] Loading the 309M-parameter T3 transformer in float16...")
    prefill_transformer = load_t3_transformer(
        checkpoint_path,
        max_context_length=max_context_length,
        dtype=torch.float16,
        delta_cache=True,
    )
    decode_transformer = load_t3_transformer(
        checkpoint_path,
        max_context_length=max_context_length,
        dtype=torch.float16,
        static_decode_cache=True,
    )

    query_length = torch.export.Dim(
        "query_length",
        min=1,
        max=min(640, max_context_length - 1),
    )
    sequence_length = torch.export.Dim(
        "sequence_length",
        min=1,
        max=max_context_length - 1,
    )
    k_cache, v_cache = create_cache_tensors(
        max_context_length=max_context_length,
        dtype=torch.float16,
    )
    prefill_inputs = {
        "input_embeddings": torch.zeros(
            (1, 4, T3_HIDDEN_SIZE),
            dtype=torch.float16,
        ),
        "position_ids": torch.arange(
            8,
            dtype=torch.int32,
        ).unsqueeze(0),
        "k_cache": k_cache,
        "v_cache": v_cache,
    }
    prefill_dynamic_shapes = {
        "input_embeddings": {1: query_length},
        "position_ids": {1: sequence_length},
        "k_cache": {},
        "v_cache": {},
    }

    decode_inputs = {
        "input_embeddings": torch.zeros(
            (1, 1, T3_HIDDEN_SIZE),
            dtype=torch.float16,
        ),
        "position_ids": torch.tensor([[400]], dtype=torch.int32),
        "k_cache": k_cache,
        "v_cache": v_cache,
    }
    if compression == "int4":
        if quantization_block_size not in (16, 32, 64, 128):
            raise ValueError(
                "--quantization-block-size must be one of 16, 32, 64, or 128"
            )
        print(
            "[INFO] Compressing T3 with INT4 symmetric per-block weights "
            f"(block size {quantization_block_size})..."
        )
        temporary_directory = tempfile.TemporaryDirectory(
            prefix="chatterbox-t3-quantized-"
        )
        temporary_root = Path(temporary_directory.name)
        prefill_transformer = quantize_t3_transformer(
            prefill_transformer,
            (
                prefill_inputs["input_embeddings"],
                prefill_inputs["position_ids"],
                prefill_inputs["k_cache"],
                prefill_inputs["v_cache"],
            ),
            block_size=quantization_block_size,
            mmap_dir=temporary_root / "prefill",
        )
        decode_transformer = quantize_t3_transformer(
            decode_transformer,
            (
                decode_inputs["input_embeddings"],
                decode_inputs["position_ids"],
                decode_inputs["k_cache"],
                decode_inputs["v_cache"],
            ),
            block_size=quantization_block_size,
            mmap_dir=temporary_root / "decode",
        )
    else:
        temporary_directory = None

    print("[INFO] Exporting T3 prefill with delta key/value cache outputs...")
    with torch.no_grad():
        prefill_exported = torch.export.export(
            prefill_transformer,
            args=(),
            kwargs=prefill_inputs,
            dynamic_shapes=prefill_dynamic_shapes,
        )
    prefill_exported = prefill_exported.run_decompositions(
        get_decomp_table()
    )

    print("[INFO] Exporting T3 fixed-shape decode...")
    with torch.no_grad():
        decode_exported = torch.export.export(
            decode_transformer,
            args=(),
            kwargs=decode_inputs,
        )
    decode_exported = decode_exported.run_decompositions(
        get_decomp_table()
    )

    converter = TorchConverter()
    converter.add_exported_program(
        exported_program=prefill_exported,
        input_names=[
            "inputEmbeddings",
            "positionIDs",
            "keyCache",
            "valueCache",
        ],
        output_names=[
            "logits",
            "keyUpdates",
            "valueUpdates",
        ],
        entrypoint_name="prefill",
    )
    converter.add_exported_program(
        exported_program=decode_exported,
        input_names=[
            "inputEmbeddings",
            "positionIDs",
            "keyCache",
            "valueCache",
        ],
        output_names=[
            "logits",
            "keyUpdates",
            "valueUpdates",
        ],
        entrypoint_name="decode",
    )
    register_cache_lowering(converter)

    print("[INFO] Converting and optimizing the cached T3 transformer...")
    program = converter.to_coreai()
    program.optimize()
    del (
        prefill_transformer,
        decode_transformer,
        prefill_inputs,
        decode_inputs,
        k_cache,
        v_cache,
        converter,
        prefill_exported,
        decode_exported,
    )
    gc.collect()
    if temporary_directory is not None:
        temporary_directory.cleanup()

    precision_description = (
        "Core AI INT4 symmetric per-block weights with sensitive embeddings, "
        "boundary blocks, and the speech head retained at higher precision"
        if compression == "int4"
        else "float16"
    )
    save_program(
        program,
        output_path,
        overwrite,
        "The Chatterbox Turbo GPT-2-medium T3 backbone and speech-token head "
        f"converted to {precision_description}. Dynamic prefill and fixed-shape "
        "decode return only newly computed key/value cache slices.",
    )
    print(f"[OK] Wrote T3 transformer to {output_path}")


def export_s3gen(
    checkpoint_path: Path,
    conditionals_path: Path,
    output_path: Path,
    overwrite: bool,
) -> None:
    print("[INFO] Loading the weighted S3Gen mean-flow model in float16...")
    model = load_s3gen_model(
        checkpoint_path,
        conditionals_path,
        dtype=torch.float16,
        coreai_compatible=True,
    )
    inputs = s3gen_reference_inputs(dtype=torch.float16)
    with torch.inference_mode():
        output_shape = tuple(model(*inputs).shape)
    print(f"[INFO] S3Gen output shape: {output_shape}")

    converter = TorchConverter()
    converter.add_exported_program(
        exported_program=export_program(model, inputs),
        input_names=["speechTokens", "noise"],
        output_names=["mel"],
        entrypoint_name="main",
    )

    del model, inputs
    gc.collect()

    print("[INFO] Converting and optimizing the S3Gen flow graph...")
    program = converter.to_coreai()
    program.optimize()
    save_program(
        program,
        output_path,
        overwrite,
        "Chatterbox Turbo S3Gen converted to Core AI in float16. It accepts "
        f"{S3GEN_GENERATED_TOKENS} speech tokens and explicit mean-flow noise "
        f"covering {S3GEN_TOTAL_MEL_FRAMES} prompt-plus-output mel frames.",
    )
    print(f"[OK] Wrote S3Gen to {output_path}")


def export_available_components(
    voice_checkpoint_path: Path,
    s3gen_checkpoint_path: Path,
    output_path: Path,
    mel_frames: int,
    overwrite: bool,
) -> None:
    print("[INFO] Exporting three weighted Chatterbox components...")
    converter = TorchConverter()
    add_voice_encoder(converter, voice_checkpoint_path)
    add_speaker_encoder(converter, s3gen_checkpoint_path)
    add_vocoder(converter, s3gen_checkpoint_path, mel_frames)

    print("[INFO] Converting the three-function program with Apple coreai-torch...")
    program = converter.to_coreai()
    print("[INFO] Optimizing the Core AI program...")
    program.optimize()
    save_program(
        program,
        output_path,
        overwrite,
        "Three weighted Chatterbox Turbo components converted from PyTorch with "
        "Apple coreai-torch: the reference voice encoder, S3Gen speaker encoder, "
        "and 24 kHz HiFT vocoder.",
    )
    print(f"[OK] Wrote three-function Chatterbox asset to {output_path}")


def print_plan() -> None:
    print("Chatterbox Turbo Core AI function contract:\n")
    for index, stage in enumerate(STAGES, start=1):
        print(f"{index}. {stage.entrypoint}")
        print(f"   source:  {stage.source_component}")
        print(f"   purpose: {stage.purpose}")

    print(
        "\nThe production default-voice path is implemented as standalone T3 "
        "embeddings, T3 transformer, S3Gen, and vocoder assets. The reference "
        "voice encoder, speech tokenizer, and speaker encoder remain available "
        "for future voice-cloning work."
    )


def default_output(mode: str) -> Path:
    exports = Path(__file__).parent / "exports"
    if mode == "probe":
        return exports / "ChatterboxContractProbe.aimodel"
    if mode == "export-voice-encoder":
        return exports / "ChatterboxTurboVoiceEncoder.aimodel"
    if mode == "export-speaker-encoder":
        return exports / "ChatterboxTurboSpeakerEncoder.aimodel"
    if mode == "export-t3-embeddings":
        return exports / "ChatterboxTurboT3Embeddings.aimodel"
    if mode == "export-t3-transformer":
        return exports / "ChatterboxTurboT3Transformer.aimodel"
    if mode == "export-s3gen":
        return exports / "ChatterboxTurboS3Gen.aimodel"
    if mode == "export-available":
        return exports / "ChatterboxTurboAvailable.aimodel"
    return exports / "ChatterboxTurboVocoder.aimodel"


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Convert Chatterbox Turbo components to native Core AI assets."
    )
    parser.add_argument(
        "--mode",
        choices=[
            "plan",
            "probe",
            "inspect-source",
            "validate-encoders",
            "validate-vocoder",
            "export-available",
            "export-speaker-encoder",
            "export-s3gen",
            "export-t3-embeddings",
            "export-t3-transformer",
            "export-voice-encoder",
            "export-vocoder",
        ],
        default="plan",
    )
    parser.add_argument("--repo-id", default=DEFAULT_REPO_ID)
    parser.add_argument("--checkpoint", type=Path)
    parser.add_argument("--conditionals", type=Path)
    parser.add_argument("--voice-checkpoint", type=Path)
    parser.add_argument("--output", type=Path)
    parser.add_argument(
        "--mel-frames",
        type=int,
        default=100,
        help="Static vocoder input length. 100 frames emits 2 seconds at 24 kHz.",
    )
    parser.add_argument("--overwrite", action="store_true")
    parser.add_argument(
        "--max-context-length",
        type=int,
        default=T3_MAX_CONTEXT_LENGTH,
    )
    parser.add_argument(
        "--t3-compression",
        choices=["none", "int4"],
        default="none",
        help="Optional weight compression for the T3 transformer export.",
    )
    parser.add_argument(
        "--quantization-block-size",
        type=int,
        default=16,
        help="Weights per INT4 quantization block.",
    )
    args = parser.parse_args()

    output_path = args.output or default_output(args.mode)
    if args.mode == "plan":
        print_plan()
    elif args.mode == "probe":
        create_contract_probe(output_path, args.overwrite)
    elif args.mode == "inspect-source":
        inspect_source_model()
    elif args.mode == "export-voice-encoder":
        voice_checkpoint_path = resolve_checkpoint(
            args.repo_id,
            VOICE_CHECKPOINT,
            args.voice_checkpoint,
        )
        export_voice_encoder(
            voice_checkpoint_path,
            output_path,
            args.overwrite,
        )
    elif args.mode in (
        "export-s3gen",
        "export-t3-embeddings",
        "export-t3-transformer",
    ):
        if args.mode == "export-s3gen":
            checkpoint_path = resolve_checkpoint(
                args.repo_id,
                VOCODER_CHECKPOINT,
                args.checkpoint,
            )
            conditionals_path = resolve_checkpoint(
                args.repo_id,
                CONDITIONALS_CHECKPOINT,
                args.conditionals,
            )
            export_s3gen(
                checkpoint_path,
                conditionals_path,
                output_path,
                args.overwrite,
            )
            return

        checkpoint_path = resolve_checkpoint(
            args.repo_id,
            T3_CHECKPOINT,
            args.checkpoint,
        )
        if args.mode == "export-t3-embeddings":
            conditionals_path = resolve_checkpoint(
                args.repo_id,
                CONDITIONALS_CHECKPOINT,
                args.conditionals,
            )
            export_t3_embeddings(
                checkpoint_path,
                conditionals_path,
                output_path,
                args.overwrite,
            )
        else:
            export_t3_transformer(
                checkpoint_path,
                output_path,
                args.overwrite,
                args.max_context_length,
                args.t3_compression,
                args.quantization_block_size,
            )
    else:
        checkpoint_path = resolve_checkpoint(
            args.repo_id,
            VOCODER_CHECKPOINT,
            args.checkpoint,
        )
        if args.mode == "validate-vocoder":
            validate_vocoder(checkpoint_path, args.mel_frames)
        elif args.mode == "export-speaker-encoder":
            export_speaker_encoder(
                checkpoint_path,
                output_path,
                args.overwrite,
            )
        elif args.mode in ("validate-encoders", "export-available"):
            voice_checkpoint_path = resolve_checkpoint(
                args.repo_id,
                VOICE_CHECKPOINT,
                args.voice_checkpoint,
            )
            if args.mode == "validate-encoders":
                validate_encoders(voice_checkpoint_path, checkpoint_path)
            else:
                export_available_components(
                    voice_checkpoint_path,
                    checkpoint_path,
                    output_path,
                    args.mel_frames,
                    args.overwrite,
                )
        else:
            export_vocoder(
                checkpoint_path,
                output_path,
                args.mel_frames,
                args.overwrite,
            )


if __name__ == "__main__":
    main()
