# Speaker diarization testing plan

## Product claim under test

The final feature should answer “who spoke when” for imported and progressively
processed audio/video. Anonymous labels such as `Speaker 1` are diarization.
Mapping a label to a known person is a separate enrollment/identification claim
and requires an explicit reference recording.

No stage is promoted because conversion exits successfully. Promotion requires
contract, numeric, semantic, timing, memory, and device evidence.

## 1. Converter and model-contract gates

Run in every default Python test pass without network access:

- Static segment pooling matches CAM++'s upstream ceil-mode average pooling
  within `atol=1e-6`, `rtol=1e-5`.
- Explicit temporal-statistics pooling matches CAM++'s unbiased standard
  deviation within `atol=1e-6`, `rtol=1e-5`.
- Folding the final non-affine inference BatchNorm into the output Conv1d
  preserves the source output within `atol=1e-5`, `rtol=1e-5`.
- Source architecture parameter count is exactly 6,848,544; the folded graph
  adds exactly 192 bias values.
- Default input is `[1, 600, 80]`; output is `[1, 192]` and L2-normalized.
- A 6.015-second, 16 kHz PCM window produces exactly 600 Kaldi-compatible
  80-bin Povey-window log-Mel frames after cepstral mean normalization.
- The exporter pins the checkpoint revision, verifies its SHA-256 before
  recording Apache-2.0 metadata, and refuses to overwrite an existing asset
  without `--overwrite`.
- `coreai-build inspect --json` reports only the documented function contract
  and no mutable state.

## 2. PyTorch-to-Core-AI parity gates

Run after every converter, PyTorch, Core AI wheel, or Xcode seed change:

- Fixed random seeds covering silence-like, low-amplitude, nominal, and clipped
  feature ranges.
- FP32 reference first; FP16 candidate second.
- Cosine similarity for every embedding must be at least 0.999.
- FP16 maximum absolute error must remain below `2e-3`.
- Output norm must remain within `1e-3` of 1.0.
- NaN and infinity counts must be zero.
- Record source revision, wheel versions, Xcode build, asset checksum, input
  checksum, cold specialization, cold inference, and at least 20 warm runs.

## 3. Speaker-discrimination gates

The small, reproducible smoke fixture uses public AMI `ES2004a` audio:

- AMI is CC BY 4.0 evaluation data, retained locally and never redistributed
  with the app, converted asset, or repository.
- Four speakers, two non-overlapping 6.015-second regions per speaker.
- First region enrolls the anonymous speaker; second region is the query.
- Core AI must classify 4/4 queries by nearest cosine similarity.
- Minimum same-speaker similarity must exceed maximum different-speaker
  similarity by at least 0.10 in this fixed smoke fixture.
- Core AI and PyTorch must choose identical nearest speakers.

Expand the semantic suite before shipping identification:

- At least 20 speakers with multiple microphones and sessions.
- Balanced gender presentation where metadata allows it; include similar vocal
  ranges rather than relying on obviously different voices.
- Clean, reverberant, compressed, distant-mic, quiet, accented, and noisy clips.
- Durations of 1, 2, 3, 4, 6, and 10 seconds to establish the minimum safe
  enrollment and query duration. CAM++ achieved 2/4 at two seconds, 3/4 at
  four seconds, and 4/4 at six seconds on the current AMI smoke fixture. Early
  speaker identity is therefore provisional, not a supported accuracy claim.
- Report equal-error rate, false accept rate, false reject rate, ROC/AUC, and
  per-domain thresholds. Do not choose a production threshold from one meeting.

## 4. Full diarization quality gates

The current energy-segmentation fallback has a smaller functional smoke gate:

- Generate the public AMI `A → B → A → B` fixture with
  `make_ami_diarization_fixture.py`.
- The Swift engine must return exactly four ordered turns, exactly two anonymous
  speakers, and the permutation-stable pattern `1 → 2 → 1 → 2`.
- The pinned Swift Kaldi frontend must match all 48,000 Torchaudio fixture
  values with maximum absolute error below `1e-3` and mean error below `5e-5`.
- Silence-only input must produce no turns, and cancelled or replaced media must
  not publish stale results.

The June 22, 2026 run passed the labeled fixture with repeat-speaker cosines of
0.806 and 0.754. That justifies a Lab example, not production promotion. Before
promotion, evaluate with standard RTTM scoring and speaker-label permutation
matching:

- Diarization Error Rate (DER), split into missed speech, false alarm, and
  speaker confusion.
- Jaccard Error Rate (JER).
- Correct speaker count, fragmentation, speaker switches per minute, and
  overlap recall.
- Report both a 0.25-second collar/ignored-overlap score and a strict no-collar,
  overlap-included score. Never compare numbers with different scoring rules.

Promotion fixtures:

1. AMI `ES2004a`: correct speaker count, with the complete DER/JER component
   report retained as a smoke result rather than an absolute quality target.
2. Full 16-meeting AMI SDM evaluation split: Core AI average DER may regress no
   more than 0.5 percentage points from the same PyTorch graph and host
   pipeline.
3. VoxConverse: evaluate all 232 files and report mean/median DER and JER.
4. Targeted fixtures: silence, music-only, single speaker, rapid turn-taking,
   interruptions, simultaneous speakers, background conversation, and clips
   shorter than the model window.

The segmentation, embedding, clustering, and timeline stages must each report
their own duration and error boundary. A correct speaker count does not excuse
bad turn boundaries, and a low aggregate DER does not excuse unstable IDs in a
live UI. A weak but correctly measured permissive model may remain a Lab
example; it cannot silently graduate into a production-quality claim.

## 5. Progressive and streaming behavior

The current engine is batch-only. It uses three-second timeline slices with up
to 6.015 seconds of context inside each energy speech region, but publishes only
after the complete file finishes. For a future progressive engine:

- Use a 6-second CAM++ context window with a separately measured hop interval;
  the two- and four-second contracts failed the current identity smoke gate.
- Mark recent results provisional until enough right context is available.
- Measure first-result latency, update latency, revision depth, and how often a
  finalized speaker label changes.
- Require processing faster than real time (`RTFx > 1`) on every supported
  device. The product target should be comfortably higher, but the release gate
  is tied to named hardware rather than a universal desktop number.
- Cancelled/replaced media must not publish stale turns.
- Long files must stream from disk and keep memory bounded; test 10 minutes,
  1 hour, and the product's intended 10-hour lab session.

The current decoder retains all 16 kHz Float32 samples, so it explicitly fails
the bounded-memory/10-hour promotion gate even though the 27.06-second AMI smoke
fixture processed faster than real time.

For the preferred MIT stateful streaming candidate, LS-EEND, add state-reset,
checkpoint/resume, frontend parity, all six cache-tensor contracts,
frame-by-frame parity, final-tail flushing, and one-hour drift tests before it
can replace the rolling-window engine.

## 6. Performance and device matrix

Record separately:

- download and checksum verification;
- asset validation;
- specialization/cache miss and cache hit;
- model load;
- audio decode/resample/filterbank;
- segmentation/VAD;
- embedding inference;
- clustering and timeline reconstruction;
- UI publication.

Run on the oldest supported iPhone, a current iPhone, and at least one Apple
silicon Mac. Capture median and p95 latency, peak resident memory, allocated
model memory, thermal state, energy impact, and cache size. Preferred compute
unit is recorded as a request, not proof of actual hardware placement.

Physical-device Core AI integration tests remain opt-in through `COREAI_*`
paths and the existing device harness. Simulators are not accepted as evidence
for Core AI placement or performance.

## 7. Licensing and artifact safety

- The default stack accepts only MIT or Apache-2.0 code and model weights.
  CC-BY-4.0 candidates may remain documented comparators, but non-commercial,
  custom, unknown, or mixed terms fail the default release gate.
- Store source repository, immutable revision, checkpoint checksum, model card,
  code license, weight license, access terms, and attribution beside every
  generated manifest. Code and weights are audited separately.
- Preserve the Apache-2.0 3D-Speaker notice in adapted CAM++ source and include
  an Apache-2.0 license copy with any distributed source or converted asset.
- Never commit downloaded checkpoints, AMI audio, generated `.aimodel` assets,
  compiled assets, result bundles, or credentials.
- MIT Pyannote segmentation 3.0 remains blocked until its Hugging Face
  contact-sharing terms are explicitly accepted. Do not use an unofficial
  mirror to bypass the gate. Community-1's CC-BY-4.0 pipeline is a benchmark,
  not the selected default stack.
- Dataset access and redistribution terms are tracked independently from model
  terms; a permissive checkpoint does not relicense AMI, CALLHOME, or DIHARD.
- Any model or dataset change invalidates semantic thresholds until the relevant
  quality suite is rerun.

See [MODEL_SELECTION.md](MODEL_SELECTION.md) for the candidate matrix and the
measured quality-versus-license decision.
