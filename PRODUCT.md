# Product

## Register

product

## Users

Core AI Lab is for Apple-platform developers, ML engineers, researchers, and model-recipe authors who want to bring modern open models onto Apple silicon. They work on a Mac with Xcode, Python/PyTorch checkpoints, and one or more Apple devices nearby. Their job is to discover what Core AI can run, turn a source model into a trustworthy `.aimodel` pipeline, inspect and exercise it, compare deployment variants, and carry a proven integration into an app without reconstructing the workflow from terminal history.

## Product Purpose

Core AI Lab is the local workbench for the full Core AI deployment loop: discover, convert, inspect, run, validate, optimize, benchmark, and package. It combines the immediacy of a model playground with the guided rigor of a visual conversion tool, while remaining broad enough for language, vision, audio, diffusion, embedding, and multi-model pipelines.

Success means a developer can understand an unfamiliar Core AI asset in minutes, reproduce a known recipe without hidden setup, see exactly why a conversion or specialization failed, compare variants with defensible evidence, and export an integration whose model contracts, licenses, checksums, and performance claims are explicit.

## Brand Personality

Expert, curious, audacious. The product should feel like a serious native instrument that happens to make difficult model engineering inviting. Its voice is direct and technically honest, with moments of delight earned by real outputs rather than decoration.

## Anti-references

- Not a static WWDC example gallery or an ever-growing stack of settings forms.
- Not a generic chat application wearing a model picker.
- Not an LLM-only imitation of LM Studio; Core AI spans many model and pipeline types.
- Not a black-box “convert anything” button that hides unsupported operations, parity loss, or hardware fallbacks.
- Not a card-grid SaaS dashboard, a terminal-themed costume, or a visual graph full of ornamental nodes.
- Not a replacement for Apple’s Core AI Debugger, Instruments, or Xcode model viewer; it should connect those tools into a coherent workflow.

## Design Principles

1. **Evidence is the interface.** Show contracts, provenance, parity, timings, memory, and failure boundaries next to every claim.
2. **Progressive disclosure preserves momentum.** A first successful run should be simple; tensors, compression maps, custom kernels, and state layouts remain one deliberate step deeper.
3. **Pipelines are first-class.** Treat tokenizers, host transforms, model functions, state, randomness, and post-processing as one typed, inspectable system.
4. **Every experiment is reproducible.** Persist source revisions, environments, seeds, shapes, converter options, checksums, target hardware, and generated artifacts.
5. **Apple hardware is part of the model.** macOS, iOS, GPU, Neural Engine, specialization, memory pressure, and thermal behavior are deployment profiles, not late-stage toggles.

## Accessibility & Inclusion

Target Apple Human Interface Guidelines and WCAG 2.2 AA where applicable. Support full keyboard operation, VoiceOver, Dynamic Type, Reduce Motion, sufficient contrast, and status communication that never relies on color alone. Charts, waveforms, spectrograms, and pipeline diagrams require text summaries, labeled comparisons, and accessible data tables. Long-running conversion and specialization work must expose clear progress, cancellation, recovery, and plain-language errors.
