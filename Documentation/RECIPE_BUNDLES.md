# Recipe bundles

Core AI Lab recipe bundles are reviewable directories whose root contains
`recipe-bundle.json`. Version 1 of that manifest is published as
[`recipe-bundle.schema.json`](recipe-bundle.schema.json) and represented in
Swift by the public `CoreAIRecipeBundleManifest` API.

The bundle manifest supplements the runtime recipe manifest. It records package
identity, family, immutable source revision, license, author, every payload's
byte count and SHA-256 digest, and every reference to Python, Swift, or custom
code. It does not grant permission to run that code.

## Minimum layout

```text
Example.recipebundle/
  recipe-bundle.json
  Recipe/recipe.json
  Validation/contracts.json
  Authoring/export.py
  README.md
```

Every regular file except `recipe-bundle.json` must appear exactly once in the
`files` array. The runtime manifest named by `recipeManifestPath` must use the
`recipeManifest` role. Paths are normalized relative paths: absolute paths,
empty components, `.` and `..`, backslashes, tildes, and symbolic links are
rejected. Undeclared files are also rejected, so executable content cannot hide
beside the reviewed inventory.

The JSON Schema rejects unknown fields and the Swift decoder applies the same
closed-field policy. Cross-field rules, Unicode NFC normalization, executable
content checks, and inventory uniqueness are semantic validation steps described
by the schema's `x-coreai-semanticValidation` annotation and enforced by the app.

Use these roles:

- `recipeManifest`, `validationFixture`, `documentation`, and `data` are data.
- `pythonSource`, `swiftSource`, and `customCode` are executable material. Each
  one must have an explicit `codeReferences` entry with a stable ID, language,
  and entry point.

## Authoring and deterministic export

1. Put all source files below one authoring root. Do not use links to files
   elsewhere.
2. Pin the upstream repository and source revision. Record the applicable
   license and author in `provenance`; branch names and floating package ranges
   are not revisions.
3. Construct `CoreAIRecipeBundleDraft` with the reviewed file roles and code
   references.
4. Call `CoreAIRecipeBundleExporter.export(_:to:)`. It streams payloads into a
   staging directory, hashes the copied bytes, sorts file and code inventories,
   writes canonical sorted-key JSON, verifies the staged bundle, and promotes
   it atomically.
5. Run schema, contract, fixture, and platform validation appropriate to the
   recipe. Trust and verification are separate: passing schema validation does
   not establish model quality, hardware placement, or parity.

The exporter deliberately has no timestamp field. Identical metadata and bytes
produce the same canonical manifest and bundle identity.

## Import and trust boundary

`CoreAIRecipeBundleImporter` validates schema version, expected family, paths,
file inventory, links, sizes, and hashes before copying only declared payloads
into managed storage. Imports always start with the `importedUntrusted` trust
state.

The importer never invokes `Process`, imports Python, loads a Swift package, or
resolves an executable reference for use. A `CoreAIRecipeBundleSession` returns
data payloads normally but rejects executable payload and code-reference URLs
with `codeExecutionNotApproved` until the caller explicitly invokes
`approveReferencedCodeExecution()`. Approval only unlocks the reference; it
does not execute anything. A future worker/helper boundary must still isolate
untrusted conversion work before a distributed build runs imported code.

## Curated index semantics

`CoreAILab/Resources/Recipes/curated-recipes.json` is a versioned catalog. Every
entry has independent trust and verification states plus plain-language notes.
Each entry binds its trust claim to the exact SHA-256 digest of a checked-in
recipe manifest. Every positive verification state also names and hashes its
evidence source, so edits invalidate the catalog assertion until it is reviewed
and refreshed. The catalog UI shows both full digests. Repository tests invoke
`validateReferencedDigests(at:)` against the checkout root, rehashing the exact
recipe and evidence references; those source paths are intentionally not assumed
to exist in every platform's installed app bundle.
`fixturesValidated` means local deterministic fixtures passed; it does not imply
physical-device, Neural Engine, performance, or external CI verification.
Hardware claims require a durable evidence reference. The draft hardware matrix
work remains separate from this schema and trust foundation.
