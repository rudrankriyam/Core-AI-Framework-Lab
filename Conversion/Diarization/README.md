# CAM++ speaker embedding for Core AI

This recipe converts the public
[`funasr/campplus`](https://huggingface.co/funasr/campplus) checkpoint into a
Core AI `.aimodel` asset. Both the checkpoint and the matching
[`modelscope/3D-Speaker`](https://github.com/modelscope/3D-Speaker) source are
explicitly Apache-2.0.

The source model has 6,848,544 parameters and produces a 192-dimensional
speaker embedding. The converter folds a parameter-free inference BatchNorm
into a new 192-value bias, so the equivalent exported graph contains 6,848,736
stored parameters.

The model answers whether prepared speech regions sound like the same speaker.
It does **not** find speech boundaries or create a complete diarization timeline
by itself. See [MODEL_SELECTION.md](MODEL_SELECTION.md) for the license-first
stack decision and [TESTING_PLAN.md](TESTING_PLAN.md) for promotion gates.

## Verified conversion

Evidence recorded on June 22, 2026 with Xcode 27 beta `27A5194q`, PyTorch
2.9.1, and `coreai-torch` 0.4.0:

| Evidence | Result |
| --- | --- |
| Pinned checkpoint revision | `e4b6ede7ce16997aff4ae69fbca1f0175e2afede` |
| Checkpoint SHA-256 | `3388cf5fd3493c9ac9c69851d8e7a8badcfb4f3dc631020c4961371646d5ada8` |
| Source / weight license | Apache-2.0 / Apache-2.0 |
| Source parameters | 6,848,544 |
| FP16 asset size | 14.2 MB |
| Input | Float16 `[1, 600, 80]` log-Mel frames, about 6.0 seconds |
| Output | L2-normalized Float16 `[1, 192]` speaker embedding |
| Required graph rewrites | Static segment means, explicit unbiased variance, final BatchNorm fold |
| Random-input Core AI/PyTorch cosine | 0.999996 |
| Random-input maximum absolute error | 0.000519 |
| Real-audio minimum parity cosine | 0.999994 |
| AMI `ES2004a` identification | 4/4 held-out speaker clips matched their enrollment clips |
| Same-speaker cosine | minimum 0.7126, mean 0.7644 |
| Different-speaker cosine | maximum 0.5886, mean 0.4046 |
| Separation margin | 0.1240 |
| Cached warm Core AI inference | median 6.09-7.54 ms across two runs on the tested Mac |

The real-audio check used two non-overlapping 6.015-second regions for each of
the four labeled speakers in public AMI meeting `ES2004a`. No audio, checkpoint,
or generated model is stored in this repository.

Shorter context was materially worse on the same deterministic windows:

| Context | Correct queries | Separation margin |
| --- | ---: | ---: |
| 2.015 seconds / 200 frames | 2/4 | -0.2023 |
| 4.015 seconds / 400 frames | 3/4 | -0.0239 |
| 6.015 seconds / 600 frames | 4/4 | 0.1240 |

That is useful negative evidence: this checkpoint is not currently a credible
two-second speaker-identification model. A live UI can update frequently after
enough context exists, but it must label early results provisional.

As an independent full-pipeline reference, FluidAudio's Core ML
Pyannote/WeSpeaker/VBx implementation was run on the complete 1,049-second
`ES2004a` meeting. It found 4/4 speakers with 10.42% DER, 13.42% JER, and
197.83x real-time throughput after model preparation. This validates a pipeline
shape; it is not a quality claim for CAM++ or the still-unconverted Core AI
segmentation stage.

## Setup and export

```bash
cd Conversion/Diarization
uv sync
uv run pytest -q
uv run python export.py --dtype float16 --frames 600 --overwrite
```

The exporter downloads the pinned public checkpoint to the Hugging Face cache.
It verifies the checkpoint SHA-256 before attaching Apache-2.0 metadata and
does not add model weights to the repository. Pass `--checkpoint PATH` to use
an identical already staged checkpoint without network access; arbitrary
weights are rejected rather than mislabeled. Static frame counts must be
multiples of 200 so CAM++'s 100-frame post-TDNN segment pooling remains exact.

Inspect the generated contract:

```bash
xcrun coreai-build inspect \
  exports/CAMPPlus192_float16_600f.aimodel \
  --json
```

Run Core AI/PyTorch numeric parity without external audio:

```bash
uv run python validate.py \
  --asset exports/CAMPPlus192_float16_600f.aimodel
```

To reproduce the public AMI speaker-identification check, stage
`ES2004a.Mix-Headset.wav` from the
[`AMI Meeting Corpus`](https://groups.inf.ed.ac.uk/ami/corpus/) and the AMI
1.6.2 `segments/` annotations, then run:

```bash
uv run python validate.py \
  --asset exports/CAMPPlus192_float16_600f.aimodel \
  --ami-audio /path/to/ES2004a.Mix-Headset.wav \
  --ami-segments /path/to/ami_public_1.6.2/segments \
  --json-output /tmp/campplus-coreai-validation.json
```

The command fails unless all four query clips select the correct enrolled
speaker, Core AI/PyTorch cosine parity stays above 0.999, maximum random-input
absolute error stays below 0.002, and the deterministic separation margin is at
least 0.10. Those are conversion smoke gates, not production identity
thresholds.

## Full diarization path

The preferred license-first batch stack is MIT Pyannote segmentation 3.0,
Apache-2.0 CAM++, and repository-owned clustering/timeline code. The Pyannote
checkpoint is gated on Hugging Face; the current account has not accepted its
contact-sharing terms, so this repository does not download, mirror, or convert
it.

MIT LS-EEND is the preferred true-streaming research path. It offers fast turn
activity updates but requires a stateful six-cache Core AI contract, exact
frontend parity, final-tail flushing, and long-session drift tests before it can
replace deterministic stub turns in the app.
