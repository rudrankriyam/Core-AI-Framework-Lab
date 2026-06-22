# Diarization model selection

## Decision

Use only MIT or Apache-2.0 model weights in the default product path. Prefer a
less accurate model with unambiguous commercial redistribution rights over a
stronger model with non-commercial, custom, unknown, or mixed terms.

The first converted stage is
[`funasr/campplus`](https://huggingface.co/funasr/campplus), pinned to revision
`e4b6ede7ce16997aff4ae69fbca1f0175e2afede`. Its checkpoint is explicitly
Apache-2.0, and the matching
[`modelscope/3D-Speaker`](https://github.com/modelscope/3D-Speaker)
implementation is Apache-2.0. This is the default speaker-embedding model even
though its observed AMI separation is weaker than WeSpeaker.

For complete diarization, the preferred batch stack is:

1. [`pyannote/segmentation-3.0`](https://huggingface.co/pyannote/segmentation-3.0)
   for overlap-aware turn segmentation (MIT).
2. CAM++ for speaker embeddings (Apache-2.0).
3. A repository-owned MIT clustering and timeline implementation with no PLDA
   weights.

The Pyannote files require the user to accept an upstream contact-sharing gate.
The license is permissive, but the Lab will not accept those terms or obtain the
checkpoint through a mirror on the user's behalf.

While that gate remains unresolved, the Lab runs a deliberately weaker fallback:
repository-owned energy segmentation plus CAM++ and deterministic cosine
clustering. It adds no model weights or license obligations. It also has no
overlap model, no neural speaker-change detector, and no production accuracy
claim; it exists so the permissive CAM++ stage can be exercised end to end.

For true low-latency streaming, LS-EEND is the preferred research branch. Its
official code and published Apple-model exports are MIT, and the architecture
is about 11.18 million parameters. It is a materially harder Core AI conversion
because every step carries six recurrent/cache tensors and requires exact 8 kHz
frontend and flush behavior.

## License and feasibility matrix

| Candidate | Role | Weight terms | Code terms | Decision |
| --- | --- | --- | --- | --- |
| CAM++ | Speaker embedding | Apache-2.0 | Apache-2.0 | Selected, converted, and bundled |
| Pyannote segmentation 3.0 | Overlap-aware segmentation | MIT, gated access | MIT | Selected next stage; access blocked |
| LS-EEND | End-to-end streaming diarization | MIT | MIT | Selected streaming research path |
| WeSpeaker ResNet34-LM | Speaker embedding | CC-BY-4.0 | Apache-2.0 | Comparator only; not the default |
| Pyannote Community-1 | Complete batch pipeline | CC-BY-4.0, gated access | Mixed pipeline | Benchmark reference only |
| NVIDIA Sortformer v1 | End-to-end diarization | CC-BY-NC-4.0 | Apache-2.0 NeMo | Rejected: non-commercial weights |
| NVIDIA Sortformer v2.1 | End-to-end diarization | NVIDIA Open Model License | Apache-2.0 NeMo | Rejected from the clean default path |

CC-BY-4.0 permits commercial use with attribution, but MIT and Apache-2.0 are
preferred here because they produce a simpler, code-and-weight-aligned
redistribution story. “Open model” branding is not treated as a license.

## Measured tradeoff

Both candidates below were converted to FP16 Core AI assets and tested with the
same two clean windows for each of four speakers in public AMI meeting
`ES2004a`:

| Evidence | CAM++ (selected) | WeSpeaker (comparator) |
| --- | ---: | ---: |
| Held-out nearest-enrollment matches | 4/4 | 4/4 |
| Minimum same-speaker cosine | 0.7126 | 0.6540 |
| Maximum different-speaker cosine | 0.5886 | 0.1459 |
| Separation margin | 0.1240 | 0.5081 |
| Minimum Core AI/PyTorch parity | 0.999994 | 0.999999 |
| Warm median inference | 6.09-7.54 ms | 4.78 ms |
| Weight license on official model card | Apache-2.0 | CC-BY-4.0 |

CAM++ is therefore not presented as the quality winner. It is the license-first
choice, and its production threshold must be established on a much larger
multi-session corpus.

Context length matters substantially for the selected checkpoint. On the same
AMI smoke fixture, 2.015 seconds matched 2/4 queries, 4.015 seconds matched 3/4,
and 6.015 seconds matched 4/4. The live product must not imply reliable speaker
identity after only two seconds.

## Release gate

Every downloadable or bundled model must have a manifest containing the exact
source repository, immutable revision, file checksum, code license, weight
license, required attribution, and access terms. A model is blocked when any
field is unknown. Generated Core AI metadata must carry the weight license, and
distributed source adaptations must retain their upstream notices and license
copy. The current exporter enforces the pinned CAM++ checkpoint SHA-256 before
it writes Apache-2.0 metadata. The bundled asset also carries
`CoreAILab/Resources/Diarization/MODEL_PROVENANCE.json`, which pins the source,
conversion environment, and converted-file checksums.
