# Diarization fixtures

`CAMPPlusKaldiFeatures.float32` contains 600 × 80 little-endian Float32 values
from the pinned `torchaudio.compliance.kaldi.fbank` frontend. The waveform is a
deterministic integer saw pattern, so this fixture contains no third-party audio.

Regenerate it from `Conversion/Diarization` with:

```bash
uv run python generate_swift_feature_fixture.py
```
