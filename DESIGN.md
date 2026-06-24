---
name: Core AI Lab
description: A precise native workbench for evidence-backed Core AI workflows.
colors:
  system-blue: "#007AFF"
  system-green: "#34C759"
  system-orange: "#FF9500"
  system-red: "#FF3B30"
  on-accent: "#FFFFFF"
typography:
  title:
    fontFamily: "SF Pro, -apple-system, BlinkMacSystemFont, sans-serif"
    fontSize: "1.25rem"
    fontWeight: 600
    lineHeight: 1.25
    letterSpacing: "normal"
  body:
    fontFamily: "SF Pro, -apple-system, BlinkMacSystemFont, sans-serif"
    fontSize: "1rem"
    fontWeight: 400
    lineHeight: 1.4
    letterSpacing: "normal"
  technical:
    fontFamily: "SF Mono, ui-monospace, SFMono-Regular, monospace"
    fontSize: "0.875rem"
    fontWeight: 400
    lineHeight: 1.4
    letterSpacing: "normal"
components:
  button-primary:
    backgroundColor: "{colors.system-blue}"
    textColor: "{colors.on-accent}"
    typography: "{typography.body}"
  status-success:
    textColor: "{colors.system-green}"
    typography: "{typography.body}"
  status-warning:
    textColor: "{colors.system-orange}"
    typography: "{typography.body}"
  status-error:
    textColor: "{colors.system-red}"
    typography: "{typography.body}"
---

# Design System: Core AI Lab

## Overview

**Creative North Star: “The Native Instrument”**

Core AI Lab should feel like an Apple developer instrument: calm at rest, exact when interrogated, and candid about what it knows. The interface uses standard SwiftUI navigation, forms, lists, tables, toolbars, and status views so platform behavior carries the visual language. Technical density is welcome when it improves comparison or preserves evidence; decoration is not a substitute for hierarchy.

Each workspace follows a legible sequence: orient, prepare, act, observe, verify. Common actions stay visible while prerequisites, provenance, raw identifiers, and limitations appear where they become relevant. Standard controls inherit the platform's current materials and Liquid Glass behavior automatically; the app does not add ornamental glass effects of its own.

The system explicitly rejects consumer chat-app framing, generic dashboard card grids, science-fiction control panels, and marketing-first presentation. It should remain recognizably native on iPhone, iPad, and Mac while preserving the rigor expected from a model inspection and validation tool.

**Key Characteristics:**

- Native and platform-adaptive
- Evidence-led rather than decorative
- Information-rich with progressive disclosure
- Clear about prerequisites, progress, cancellation, and failure
- Accessible by default, including keyboard and VoiceOver workflows

## Colors

Color is semantic and restrained. SwiftUI system backgrounds, labels, separators, fills, and materials are the source of truth for light mode, dark mode, Increase Contrast, and platform variation.

### Primary

- **System Blue:** The sole interactive accent for selection, links, focus, and the primary action in a workflow.

### Status

- **System Green:** Verified success or a completed, valid state. Pair it with a checkmark and text.
- **System Orange:** Caution, provisional evidence, or a condition that deserves review. Pair it with a warning symbol and explanation.
- **System Red:** Destructive actions and failures that need attention. Never use it as ambient decoration.

### Neutral

- Use semantic SwiftUI styles such as primary, secondary, tertiary, background, grouped background, separator, and material. Do not hardcode neutral colors that would break system appearance modes.

**The One Accent Rule.** A screen gets one prominent blue action. Secondary actions use standard bordered, plain, menu, or navigation treatments.

**The Redundancy Rule.** Status is always expressed with text and an icon or shape in addition to color.

## Typography

- **Display Font:** SF Pro through SwiftUI semantic title styles
- **Body Font:** SF Pro through SwiftUI semantic body, callout, subheadline, and footnote styles
- **Label/Mono Font:** SF Mono through monospaced variants of the nearest semantic style

**Character:** Familiar, highly legible, and quiet. Typography creates hierarchy without oversized display treatments or gratuitous weight changes.

### Hierarchy

- **Title:** Navigation titles and the occasional workspace identity. Prefer the system navigation title before adding an in-content title.
- **Headline:** Section-leading labels and a small number of meaningful summaries.
- **Body:** Primary instructions, results, and user-authored content. Allow Dynamic Type to determine the runtime size.
- **Subheadline / Footnote:** Evidence boundaries, provenance, prerequisites, and supporting detail.
- **Technical:** Commands, hashes, paths, identifiers, tensor shapes, and numeric evidence. Keep them selectable and truncate long identifiers in the middle when horizontal space is limited.

**The Semantic Type Rule.** Use SwiftUI semantic styles rather than fixed point sizes. Bold is reserved for hierarchy, not routine emphasis.

## Elevation

The system is flat by default. Depth comes from platform navigation, grouped form backgrounds, sheets, popovers, menus, and system materials rather than custom shadows. Liquid Glass belongs to the navigation and control layer supplied by SwiftUI; content and evidence surfaces remain solid and readable. A material may back a temporary progress overlay, but it must not become a decorative card treatment.

**The Platform Depth Rule.** If SwiftUI already communicates the layer, do not add another shadow, blur, stroke, or floating container.

## Components

### Navigation

- Use `NavigationSplitView` for the app shell and group destinations as Library, Build, Run, and Validate.
- Preserve the selected destination, supply a symbol and concise accessibility hint, and let the system manage sidebar selection and toolbar overflow.
- Use a nested sidebar only when a tool has a genuine second-level information architecture, such as Recipe Studio.

### Grouped Workspaces

- Use grouped `Form` sections for ordered technical workflows. Every meaningful section has a concise noun label and, where useful, a familiar SF Symbol.
- Lead with current state and prerequisites, then inputs, the primary action, results, and evidence.
- Prefer full-width readable content over grids of small cards.

### Buttons

- Use an active verb and a familiar symbol. One action per workflow may use `borderedProminent`; supporting actions remain standard.
- Keep destructive actions in menus, confirmation dialogs, or explicit destructive roles unless immediate visibility is essential.
- While an action runs, show a labeled `ProgressView` that names the current work. Do not leave an active button looking tappable.
- Maintain a minimum 44 by 44 point interactive target on touch platforms and preserve standard keyboard shortcuts on Mac.

### Inputs and Search

- Use native fields, pickers, steppers, sliders, file importers, and search. Labels describe the value, while footers explain constraints or consequences.
- Disable an input only when editing it would be invalid during the current state; never use disabled styling as a substitute for an explanation.

### Empty, Loading, and Failure States

- Use `ContentUnavailableView` for first-run guidance, empty results, unsupported capabilities, and missing content.
- Loading states name the operation and show progress. Failure titles state what could not be completed; the message gives the exact error or a useful recovery action.
- Treat user-canceled pickers as cancellation, not failure.

### Evidence and Results

- Use `LabeledContent`, disclosure groups, lists, and tables for comparable facts. Keep raw commands, hashes, paths, and identifiers monospaced and selectable.
- Distinguish preferences, plans, cache states, and measured evidence in both layout and copy.
- Collapse explanatory detail when the primary task would otherwise be buried, but never hide caveats required to interpret a result honestly.

## Do's and Don'ts

### Do:

- **Do** start every workspace with purpose, current state, and the next meaningful action.
- **Do** rely on standard SwiftUI controls so appearance, Liquid Glass, keyboard behavior, and accessibility adapt with the platform.
- **Do** use one prominent primary action and let toolbars contain only high-value, contextual commands.
- **Do** use Dynamic Type, semantic colors, text-plus-symbol status, and 44-point touch targets.
- **Do** write concise sentence-case labels and task-specific failures such as “Couldn't Import the Recipe Bundle.”
- **Do** keep technical evidence precise, selectable, and visually quieter than the user's current task.

### Don't:

- **Don't** imitate consumer AI chat apps that reduce every workflow to a prompt box.
- **Don't** build generic SaaS dashboards from interchangeable card grids and decorative metrics.
- **Don't** use sci-fi control panels with neon gradients, ornamental glass, or unexplained status lights.
- **Don't** create marketing surfaces that hide provenance, prerequisites, or limitations behind optimistic copy.
- **Don't** introduce bespoke controls that replace familiar Apple platform behavior without improving the task.
- **Don't** use color alone, static hourglass symbols, vague “Operation Failed” alerts, or user-visible raw enum values.
- **Don't** claim hardware placement, performance, cache benefit, or model availability without corresponding evidence.
