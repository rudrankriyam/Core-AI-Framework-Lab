import argparse
import asyncio
import gc
import math
import time
import wave
from dataclasses import dataclass
from pathlib import Path

import numpy as np
import torch
from coreai.runtime import (
    AIModel,
    ComputeUnitKind,
    NDArray,
    SpecializationOptions,
)
from transformers import (
    AutoTokenizer,
    LogitsProcessorList,
    RepetitionPenaltyLogitsProcessor,
    TemperatureLogitsWarper,
    TopKLogitsWarper,
    TopPLogitsWarper,
)

from s3gen import (
    S3GEN_GENERATED_TOKENS,
    S3GEN_TOTAL_MEL_FRAMES,
)
from t3 import (
    T3_HEAD_DIM,
    T3_MAX_CONTEXT_LENGTH,
    T3_MAX_TEXT_TOKENS,
    T3_NUM_HEADS,
    T3_NUM_LAYERS,
    T3_START_SPEECH_TOKEN,
    T3_STOP_SPEECH_TOKEN,
)
from vocoder import (
    SAMPLES_PER_MEL_FRAME,
    SOURCE_CHANNELS,
)

S3GEN_SILENCE_TOKEN = 4299
SAMPLE_RATE = 24_000
S3GEN_END_SILENCE_TOKENS = 3


@dataclass(frozen=True)
class AssetPaths:
    embeddings: Path
    transformer: Path
    s3gen: Path
    vocoder: Path
    tokenizer: Path
    max_context_length: int = T3_MAX_CONTEXT_LENGTH


@dataclass(frozen=True)
class SynthesisResult:
    waveform: np.ndarray
    speech_tokens: list[int]
    normalized_text: str
    elapsed_seconds: float


def normalize_text(text: str) -> str:
    if not text:
        return "You need to add some text for me to talk."
    if text[0].islower():
        text = text[0].upper() + text[1:]
    text = " ".join(text.split())
    for old, new in (
        ("…", ", "),
        (":", ","),
        ("—", "-"),
        ("–", "-"),
        (" ,", ","),
        ("“", '"'),
        ("”", '"'),
        ("‘", "'"),
        ("’", "'"),
    ):
        text = text.replace(old, new)
    text = text.rstrip(" ")
    if not text.endswith((".", "!", "?", "-", ",")):
        text += "."
    return text


def tokenize_text(tokenizer, text: str) -> list[int]:
    input_ids = tokenizer(
        text,
        return_tensors="np",
        truncation=True,
        max_length=T3_MAX_TEXT_TOKENS,
    ).input_ids[0]
    return input_ids[:T3_MAX_TEXT_TOKENS].astype(np.int32).tolist()


def gpu_options() -> SpecializationOptions:
    return SpecializationOptions.from_preferred_compute_unit_kind(
        ComputeUnitKind.gpu()
    )


def make_logits_processors(
    *,
    temperature: float,
    top_k: int,
    top_p: float,
    repetition_penalty: float,
) -> LogitsProcessorList:
    processors = LogitsProcessorList()
    if temperature > 0 and temperature != 1:
        processors.append(TemperatureLogitsWarper(temperature))
    if top_k > 0:
        processors.append(TopKLogitsWarper(top_k))
    if top_p < 1:
        processors.append(TopPLogitsWarper(top_p))
    if repetition_penalty != 1:
        processors.append(
            RepetitionPenaltyLogitsProcessor(repetition_penalty)
        )
    return processors


def sample_speech_token(
    logits_array: np.ndarray,
    input_ids: list[int],
    processors: LogitsProcessorList,
) -> int:
    logits = torch.from_numpy(
        logits_array[:, -1, :].astype(np.float32, copy=False)
    )
    processor_ids = torch.tensor([input_ids], dtype=torch.long)
    processed = processors(processor_ids, logits)
    probabilities = torch.softmax(processed, dim=-1)
    return int(torch.multinomial(probabilities, num_samples=1).item())


def cache_array(max_context_length: int) -> np.ndarray:
    return np.zeros(
        (
            T3_NUM_LAYERS,
            1,
            T3_NUM_HEADS,
            max_context_length,
            T3_HEAD_DIM,
        ),
        dtype=np.float16,
    )


async def generate_speech_tokens(
    assets: AssetPaths,
    text_tokens: list[int],
    *,
    max_generated_tokens: int,
    temperature: float,
    top_k: int,
    top_p: float,
    repetition_penalty: float,
) -> list[int]:
    load_started = time.perf_counter()
    embeddings_model, transformer_model = await asyncio.gather(
        AIModel.load(assets.embeddings, specialization_options=gpu_options()),
        AIModel.load(assets.transformer, specialization_options=gpu_options()),
    )
    print(
        "[INFO] Loaded T3 assets in "
        f"{time.perf_counter() - load_started:.3f} seconds"
    )
    prefill = embeddings_model.load_function("prefill")
    decode = embeddings_model.load_function("decode")
    prefill_transformer = transformer_model.load_function("prefill")
    decode_transformer = transformer_model.load_function("decode")

    embedding_outputs = await prefill(
        inputs={
            "textTokens": NDArray(
                np.asarray([text_tokens], dtype=np.int32)
            )
        }
    )
    input_embeddings = embedding_outputs["inputEmbeddings"]
    sequence_length = input_embeddings.shape[1]
    if sequence_length + max_generated_tokens >= assets.max_context_length:
        raise ValueError(
            "Text plus generated speech exceeds the T3 context length."
        )

    key_cache = cache_array(assets.max_context_length)
    value_cache = cache_array(assets.max_context_length)
    processors = make_logits_processors(
        temperature=temperature,
        top_k=top_k,
        top_p=top_p,
        repetition_penalty=repetition_penalty,
    )

    prefill_started = time.perf_counter()
    transformer_outputs = await prefill_transformer(
        inputs={
            "inputEmbeddings": input_embeddings,
            "positionIDs": NDArray(
                np.arange(sequence_length, dtype=np.int32).reshape(1, -1)
            ),
            "keyCache": NDArray(key_cache),
            "valueCache": NDArray(value_cache),
        }
    )
    print(
        "[INFO] T3 prefill completed in "
        f"{time.perf_counter() - prefill_started:.3f} seconds"
    )
    key_updates = transformer_outputs["keyUpdates"].numpy()
    value_updates = transformer_outputs["valueUpdates"].numpy()
    key_cache[..., :sequence_length, :] = key_updates
    value_cache[..., :sequence_length, :] = value_updates

    generated: list[int] = []
    token = sample_speech_token(
        transformer_outputs["logits"].numpy(),
        [T3_START_SPEECH_TOKEN],
        processors,
    )
    generated.append(token)

    decode_started = time.perf_counter()
    for index in range(1, max_generated_tokens):
        if token == T3_STOP_SPEECH_TOKEN:
            generated.pop()
            break

        embedding_outputs = await decode(
            inputs={
                "speechToken": NDArray(
                    np.asarray([[token]], dtype=np.int32)
                )
            }
        )
        sequence_length += 1
        transformer_outputs = await decode_transformer(
            inputs={
                "inputEmbeddings": embedding_outputs["inputEmbeddings"],
                "positionIDs": NDArray(
                    np.asarray(
                        [[sequence_length - 1]],
                        dtype=np.int32,
                    )
                ),
                "keyCache": NDArray(key_cache),
                "valueCache": NDArray(value_cache),
            }
        )
        offset = sequence_length - 1
        key_cache[..., offset : offset + 1, :] = (
            transformer_outputs["keyUpdates"].numpy()
        )
        value_cache[..., offset : offset + 1, :] = (
            transformer_outputs["valueUpdates"].numpy()
        )
        token = sample_speech_token(
            transformer_outputs["logits"].numpy(),
            generated,
            processors,
        )
        generated.append(token)

        if index == 1 or (index + 1) % 10 == 0:
            elapsed = time.perf_counter() - decode_started
            print(
                f"[INFO] T3 generated {index + 1} tokens "
                f"in {elapsed:.2f} seconds"
            )

    if generated and generated[-1] == T3_STOP_SPEECH_TOKEN:
        generated.pop()

    del (
        embeddings_model,
        transformer_model,
        prefill,
        decode,
        prefill_transformer,
        decode_transformer,
        embedding_outputs,
        transformer_outputs,
        key_cache,
        value_cache,
        key_updates,
        value_updates,
    )
    gc.collect()
    return generated


def prepare_s3gen_tokens(generated: list[int]) -> np.ndarray:
    valid = [token for token in generated if token < T3_START_SPEECH_TOKEN]
    room_for_speech = S3GEN_GENERATED_TOKENS - 3
    valid = valid[:room_for_speech]
    tokens = valid + [S3GEN_SILENCE_TOKEN] * (
        S3GEN_GENERATED_TOKENS - len(valid)
    )
    return np.asarray([tokens], dtype=np.int32)


async def generate_mel(
    asset_path: Path,
    speech_tokens: np.ndarray,
) -> np.ndarray:
    load_started = time.perf_counter()
    model = await AIModel.load(
        asset_path,
        specialization_options=gpu_options(),
    )
    function = model.load_function("main")
    print(
        "[INFO] Loaded S3Gen in "
        f"{time.perf_counter() - load_started:.3f} seconds"
    )

    noise = torch.randn(
        (1, 80, S3GEN_TOTAL_MEL_FRAMES),
        dtype=torch.float16,
    )
    run_started = time.perf_counter()
    outputs = await function(
        inputs={
            "speechTokens": NDArray(speech_tokens),
            "noise": NDArray(noise),
        }
    )
    mel = outputs["mel"].numpy().astype(np.float16, copy=False)
    print(
        "[INFO] S3Gen completed in "
        f"{time.perf_counter() - run_started:.3f} seconds"
    )
    del model, function, outputs
    gc.collect()
    return mel


async def generate_waveform(
    asset_path: Path,
    mel: np.ndarray,
) -> np.ndarray:
    load_started = time.perf_counter()
    model = await AIModel.load(
        asset_path,
        specialization_options=gpu_options(),
    )
    function = model.load_function("vocoder")
    print(
        "[INFO] Loaded vocoder in "
        f"{time.perf_counter() - load_started:.3f} seconds"
    )

    phase = torch.empty(
        (1, SOURCE_CHANNELS, 1),
        dtype=torch.float16,
    ).uniform_(-math.pi, math.pi)
    phase[:, 0, :] = 0
    noise = torch.randn(
        (
            1,
            SOURCE_CHANNELS,
            mel.shape[-1] * SAMPLES_PER_MEL_FRAME,
        ),
        dtype=torch.float16,
    )
    run_started = time.perf_counter()
    outputs = await function(
        inputs={
            "speech_feat": NDArray(mel),
            "phase": NDArray(phase),
            "noise": NDArray(noise),
        }
    )
    waveform = outputs["waveform"].numpy()[0].astype(np.float32)
    print(
        "[INFO] Vocoder completed in "
        f"{time.perf_counter() - run_started:.3f} seconds"
    )
    del model, function, outputs
    gc.collect()
    return waveform


async def synthesize(
    assets: AssetPaths,
    text: str,
    *,
    seed: int,
    max_generated_tokens: int,
) -> SynthesisResult:
    started = time.perf_counter()
    torch.manual_seed(seed)
    np.random.seed(seed)
    normalized_text = normalize_text(text)
    tokenizer = AutoTokenizer.from_pretrained(
        assets.tokenizer,
        local_files_only=True,
    )
    text_tokens = tokenize_text(tokenizer, normalized_text)
    print(f"[INFO] Normalized text: {normalized_text}")
    print(f"[INFO] Text token count: {len(text_tokens)}")

    generated = await generate_speech_tokens(
        assets,
        text_tokens,
        max_generated_tokens=max_generated_tokens,
        temperature=0.8,
        top_k=1000,
        top_p=0.95,
        repetition_penalty=1.2,
    )
    if len(generated) >= max_generated_tokens:
        raise RuntimeError(
            "T3 reached the generation limit without emitting its stop token."
        )
    print(f"[INFO] Raw generated speech tokens: {len(generated)}")
    s3gen_tokens = prepare_s3gen_tokens(generated)
    print(
        "[INFO] Valid speech tokens before silence padding: "
        f"{np.count_nonzero(s3gen_tokens != S3GEN_SILENCE_TOKEN)}"
    )

    mel = await generate_mel(assets.s3gen, s3gen_tokens)
    waveform = await generate_waveform(assets.vocoder, mel)
    output_samples = (
        len(generated) + S3GEN_END_SILENCE_TOKENS
    ) * 2 * SAMPLES_PER_MEL_FRAME
    waveform = waveform[:output_samples]
    return SynthesisResult(
        waveform=waveform,
        speech_tokens=generated,
        normalized_text=normalized_text,
        elapsed_seconds=time.perf_counter() - started,
    )


def write_wave_file(path: Path, waveform: np.ndarray) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    pcm = np.clip(waveform, -1, 1)
    pcm = np.round(pcm * np.iinfo(np.int16).max).astype("<i2")
    with wave.open(str(path), "wb") as output:
        output.setnchannels(1)
        output.setsampwidth(2)
        output.setframerate(SAMPLE_RATE)
        output.writeframes(pcm.tobytes())


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Synthesize Chatterbox Turbo audio entirely with Core AI."
    )
    exports = Path(__file__).parent / "exports"
    parser.add_argument(
        "--embeddings",
        type=Path,
        default=exports / "ChatterboxTurboT3Embeddings.aimodel",
    )
    parser.add_argument(
        "--transformer",
        type=Path,
        default=exports / "ChatterboxTurboT3Transformer.aimodel",
    )
    parser.add_argument(
        "--s3gen",
        type=Path,
        default=exports / "ChatterboxTurboS3Gen.aimodel",
    )
    parser.add_argument(
        "--vocoder",
        type=Path,
        default=exports / "ChatterboxTurboVocoder.aimodel",
    )
    parser.add_argument("--tokenizer", type=Path, required=True)
    parser.add_argument(
        "--max-context-length",
        type=int,
        default=T3_MAX_CONTEXT_LENGTH,
    )
    parser.add_argument(
        "--text",
        default=(
            "This voice is running entirely on my Mac with Core AI. "
            "[chuckle] No cloud, no MLX, just Chatterbox."
        ),
    )
    parser.add_argument("--seed", type=int, default=67)
    parser.add_argument(
        "--max-generated-tokens",
        type=int,
        default=S3GEN_GENERATED_TOKENS - S3GEN_END_SILENCE_TOKENS,
    )
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()

    result = asyncio.run(
        synthesize(
            AssetPaths(
                embeddings=args.embeddings,
                transformer=args.transformer,
                s3gen=args.s3gen,
                vocoder=args.vocoder,
                tokenizer=args.tokenizer,
                max_context_length=args.max_context_length,
            ),
            args.text,
            seed=args.seed,
            max_generated_tokens=args.max_generated_tokens,
        )
    )
    write_wave_file(args.output, result.waveform)
    print(f"[OK] Wrote {args.output}")
    print(
        f"[OK] Audio duration: {result.waveform.size / SAMPLE_RATE:.3f} seconds"
    )
    print(f"[OK] End-to-end time: {result.elapsed_seconds:.3f} seconds")


if __name__ == "__main__":
    main()
