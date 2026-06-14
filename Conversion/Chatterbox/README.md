# Chatterbox Turbo to Core AI

This directory converts Resemble AI's PyTorch Chatterbox Turbo pipeline into
native Core AI `.aimodel` assets. It uses Apple's `coreai-torch` converter, not
MLX or Core ML Tools.

## Current Status

- The complete fixed-voice inference path converts and runs through Core AI:
  T3 embeddings, T3 transformer, S3Gen mean flow, and the HiFT vocoder.
- T3 uses fixed persistent KV caches, dynamic prefill, one-token decode, and a
  quality-checked INT4 block-16 transformer export.
- S3Gen accepts 256 speech tokens and returns 512 generated mel frames after
  its 500-frame built-in voice prompt.
- The vocoder accepts 512 mel frames and emits 245,760 samples at 24 kHz.
- All 328 `mel2wav.*` tensors come from the official Chatterbox Turbo
  checkpoint.
- Both expanded S3Gen and vocoder graphs pass Core AI runtime parity against
  their PyTorch implementations.
- The four production assets plus tokenizer occupy about 600 MiB.

## Environment

Apple publishes `coreai-core` wheels for Python 3.11 and 3.12. Chatterbox pins
Torch 2.6, while `coreai-torch` requires Torch 2.8 or newer. This project uses
the tested overlap: Python 3.12, Torch 2.9.1, and Chatterbox 0.1.7.

```bash
cd Conversion/Chatterbox
uv sync
```

## Export The Production Assets

The first run downloads the official checkpoints from
`ResembleAI/chatterbox-turbo`. `S3GEN_GENERATED_TOKENS` in `s3gen.py` defines
the static S3Gen capacity; production uses 256.

```bash
uv run python export.py --mode export-t3-embeddings --overwrite

uv run python export.py \
  --mode export-t3-transformer \
  --t3-compression int4 \
  --quantization-block-size 16 \
  --overwrite

uv run python export.py --mode export-s3gen --overwrite

uv run python export.py \
  --mode export-vocoder \
  --mel-frames 512 \
  --overwrite
```

The generated assets are:

```text
exports/ChatterboxTurboT3Embeddings.aimodel
exports/ChatterboxTurboT3TransformerInt4.aimodel
exports/ChatterboxTurboS3Gen.aimodel
exports/ChatterboxTurboVocoder.aimodel
```

Validate the expanded audio graphs through Apple's runtime:

```bash
uv run python runtime_validate.py \
  --s3gen exports/ChatterboxTurboS3Gen.aimodel \
  --vocoder exports/ChatterboxTurboVocoder.aimodel \
  --mel-frames 512
```

Run the complete converted pipeline:

```bash
uv run python synthesize_coreai.py \
  --tokenizer /path/to/tokenizer \
  --output /tmp/chatterbox.wav
```

| Asset/entrypoint | Input | Output |
| --- | --- | --- |
| T3 embeddings `prefill` | text tokens | input embeddings |
| T3 embeddings `decode` | one speech token | input embedding |
| T3 transformer `prefill` | embeddings, positions, KV caches | logits, KV updates |
| T3 transformer `decode` | one embedding, position, KV caches | logits, KV updates |
| S3Gen `main` | `speechTokens [1, 256]`, `noise [1, 80, 1012]` | `mel [1, 80, 512]` |
| Vocoder `vocoder` | mel, phase, noise | `waveform [1, 245760]` |

The caller should set the first harmonic in `phase` to zero, sample the other
phase values uniformly from `[-pi, pi]`, and provide standard-normal `noise`.

## Why The Adapter Exists

The upstream graph uses seven operations not currently accepted by the Core AI
Torch converter: FFT, ELU, internal random generation, scalar remainder,
nearest-neighbor upsampling, tensor unfolding, and reflection padding.

`vocoder.py` preserves the learned network while replacing those operations
with supported equivalents:

- Fixed Hann-window DFT filters use convolution and transposed convolution.
- Conv1d layers use an equivalent trailing-axis Conv2d layout that avoids an
  Xcode 27 beta MPS specialization failure.
- Phase and noise become explicit inputs.
- ELU, modulo, upsampling, and reflection padding use primitive tensor ops.
- Weight-normalization parametrizations are folded into their learned weights.

## Runtime Measurements

Measured on an M5 Mac with Core AI device architecture `h17g`:

- S3Gen specialization/load: 4.302 seconds on a cold validation run
- S3Gen inference: 0.291 seconds
- vocoder specialization/load: 0.260 seconds
- vocoder inference: 0.372 seconds
- native Release app: 139 tokens, 5.68 seconds of audio, 4.85 seconds warm
  (RTF 0.85)

The no-cut regression sentence is:

```text
Oh, that's hilarious! [chuckle] This voice is running entirely on your Mac with Core AI.
```

The old 128-token graph stopped at exactly 5.12 seconds. The production
256-token graph reaches the T3 stop token, trims to 5.68 seconds for the tested
seed, and Whisper transcribes the complete final `Core AI.`

The contract probe still exists for testing model import and specialization:

```bash
uv run python export.py --mode probe --overwrite
```

Run the converter tests with:

```bash
uv run pytest -q
```

Compile a standalone model for the current macOS 27 machine:

```bash
export DEVELOPER_DIR=/path/to/Xcode-beta.app/Contents/Developer
ARCH=$(xcrun swift -e 'import CoreAI; print(AIModel.deviceArchitectureName)')

  xcrun coreai-build compile \
  exports/ChatterboxTurboVocoder.aimodel \
  --output "exports/ChatterboxTurboVocoder-${ARCH}.aimodelc" \
  --platform macOS \
  --min-deployment-version 27.0 \
  --architecture "$ARCH"
```
