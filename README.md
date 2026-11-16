# af-scorer source candidate

Ruby CLI for preparing blind AdventureFinder assessment requests and producing
PROPOSED assessments. This source distribution stops at private candidate review.
It establishes neither publication clearance, model qualification nor acceptance.
The CLI never makes a proposal canonical.

The runtime and retained-profile ownership policy is in
[docs/CODE_STATUS.md](docs/CODE_STATUS.md); output and request contracts are in
[docs/csv-contract.md](docs/csv-contract.md) and
[docs/inference_request_provenance.md](docs/inference_request_provenance.md).
These contracts remain authoritative for their respective surfaces.

## Distribution and prerequisites

This is an explicit regular-file source archive, with no Git history, private
catalogs/books, actual configurations, raw prompts/responses or run packages.
Only `Manifest.txt` members enter the archive. The private sidecar inventory
records every path, mode, size and SHA-256 plus the archive digest. Keep it outside
a future public import; David selects the exact import set and creates new history.
No predecessor ancestry or old qualification is transferred.

Tested runtime: Ruby 4.0.9, Bundler 4.0.17 on arm64 macOS. Ruby/Bundler, the exact
gems in `Gemfile.lock`, and system `zip`/`unzip` are separately acquired public
dependencies. Dependencies are not downloaded by package or smoke commands.
Other platforms are unqualified. See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

From a reviewed source candidate, with output paths outside it:

```sh
ruby script/source_package.rb build . /absolute/private/af-scorer.tar /absolute/private/inventory.json
ruby script/source_package.rb unpack /absolute/private/af-scorer.tar /absolute/private/inventory.json /absolute/fresh/af-scorer
cd /absolute/fresh/af-scorer
ruby --version
bundle --version
bundle check
```

If dependencies are absent, stop the offline checks and acquire the locked
dependencies separately using your normal trusted setup. No credentials, provider
service, Ollama process or model is needed for preparation/preflight.

## Exact public method dependency

Acquire `dtnorris/af-specification-md` revision
`394a44c2c2052ce2eeb6d28cd7647ad8a50acfcf` separately through a trusted source.
Do not follow main or substitute another version. The required files are:

| File | SHA-256 |
| --- | --- |
| documents.json | 5ebb0fffcafa165a71bd3afef70e483217074d788d02ff9241ab3cedfd6bf0e6 |
| AdventureFinder_Analysis_Ontology_AFAO_v1.6.1.md | dcfad224ab9517272504a508f935a804032d04a7c812ede10498921ce4585fa1 |
| AdventureFinder_Analysis_Data_Assessment_Specification_v0.1.md | bbd90a20daafb58c3daee3af758972f09f658b271086e95060ce01df44197ad0 |

The actual scorer verifies these complete bytes at startup and preparation,
including replay: nineteen dimensions, 85 primary anchors and ten assessment
sections plus common/outside-section rules remain bound. Missing, changed,
wrong-version or incomplete definitions refuse before provider construction.
AFAO 1.6.1 remains Candidate pending targeted GM Preparation Burden 4/5
revalidation; Editorial Rev 2.0 remains Draft. ABDS 1.4 governs new upstream
source preparation. The standalone historical Salvage Operation freeze supplies
no forward fallback and is not a runtime input.

## Offline first operation

Run from the independently unpacked directory, providing an existing exact public
specification root and an absent PRIVATE evidence directory:

```sh
bundle exec ruby script/offline_smoke.rb /absolute/public-specification /absolute/private/smoke
```

The smoke creates only numeric page mechanics, a generated XLSX catalog and a
v0.1 source registry. Fresh cleared-environment processes invoke the actual
`bin/af-score --prepare-source`, then `--preflight --prepared-source` and render
eight target prompts/schemas and provider request artifacts. It verifies
`afsu-prepared-source/v0.2`, source/content/policy bindings and pinned method
provenance. It removes the inventory, reruns the same entries expecting explicit
refusal, restores exact bytes and requires identical successful rendering.
Both entries must construct and execute zero providers.

Raw status/stdout/stderr, observed reads, loaded scorer paths/hashes and generated
requests stay in that PRIVATE directory, never in the release/import set.
Additional absolute forbidden roots may follow the two arguments. The Ruby File
observer rejects those reads and records loaded scorer identities. It is not a
kernel sandbox or a universal native-IO tracer; zip/unzip process boundaries are
audited separately. Run evidence should retain that observation limit.

## Explicit user inputs and configuration

Source registry resolution and raw page slicing now delegate to the standalone
`af-source-md` API `af-source-md/v0.1`, requiring Ruby 3.2+. Select the exact
reviewed owner tree with absolute `AF_SOURCE_MD_ROOT`, or supply `af_source_md`
on Ruby's load path when the variable is absent. Explicit missing, blank,
invalid or unsupported selection refuses without an ambient/historical fallback;
keep selection fixed for the process. The scorer adapter preserves its public
Resolution/Extraction types and error classes, lazy mapping checks, warnings,
source policy, Levels-context heuristics and complete prepared-source v0.2
replay. MD owns marker inventory and byte reads; scorer retains permission for
clamp/full-source scope and context selection. Selecting this candidate does not
requalify a frozen method or rewrite historical v0.1 artifacts.

`config/default.yml` is a template: its three input roots are deliberately unset.
Select all roots explicitly; there is no private sibling default. For example,
with your own catalog, source registry and content, and the exact method above:

```sh
export AF_XLSX_ROOT=/absolute/owned/catalog
export AF_SOURCE_ROOT=/absolute/owned/source
export AF_SPEC_ROOT=/absolute/public-specification
export AF_OUTPUT_DIR=/absolute/private/proposals
bin/af-score --prepare-source /absolute/private/prepared.json ADV-0001
bin/af-score --preflight --prepared-source /absolute/private/prepared.json --render-preflight /absolute/private/preflight.json ADV-0001
```

These paths are examples requiring explicit user choices. The catalog defaults
to `catalog.xlsx`; override `AF_CATALOG_WORKBOOK` if needed. The catalog requires
Adventure ID, Adventure Title, Page Count, Source Book, Book Publisher, Start Page
and End Page fields. The source registry is `source_registry.yml` under the
selected source root, using `adventurefinder-source-registry/v0.1`; registry
entries map Source Book to an owned Markdown file or explicit page segments.
Source files carry numeric `<!-- PAGE: 1 -->` or `<!-- PDF Page 1 -->` markers.
No actual catalog, workbook, source text or registry is distributed.
A private YAML overlay supplied with `--config` may select these paths instead.
The source owner retains responsibility for identity, content rights and boundaries.

Ordinary preparation, preflight and scoring ignore incidental absent, missing or
malformed regression workbooks. Explicit regression requires its selected valid
workbook and contextual eligibility before provider construction. Workbooks
enumerate cases; expected values remain AFAO-owned and are read after blind scoring.

Historical comparisons/source exceptions require explicit trusted
`afsu-target-eligibility/v0.1` selections with exact resolved catalog, registry,
source path/hash, adventure metadata, page offset, policy and AFAO digest.
An ADV label or observed digest alone establishes no historical membership.
Keep original frozen scorer, method, config and source bindings for replay.
New v0.2 payloads re-resolve live owner inputs; v0.1 payloads refuse here and
must use their original scorer. Historical `method.identity: configured` remains
explicitly selectable using retained exact definitions, without a public-identity claim.

All profile implementations remain included. Canonical loading ignores retained
profile environment variables; historical experiments require explicit
`require "af_scoring/experiments"` and their original selection. Retained NoS
supports Stage-1 preflight only, has no prepared-source replay, and refuses regression.
Never relabel old profiles/results or carry qualifications across new bindings.

Live scoring requires separately authorized provider/runtime setup. This package
proof performs no live scoring or qualification. Output stays PROPOSED with human
review; see the included review rules and CSV contract.

## Offline suite and integration boundary

With the exact public method available:

```sh
AF_TEST_SPEC_ROOT=/absolute/public-specification bundle exec rake test
```

The complete `test/**/*_test.rb` discovery remains intact. Tests generate local
mechanical inputs and fake only declared external provider/client boundaries.
The four benchmark-ID text fixtures are test support, not scoring inputs.

AFW's WL-04 owner must reconcile the actual scorer identity, prepared-source v0.2,
target selections, method/profile/request/schema hashes, ScorerAdapter HEAD and
closed-environment checks, and QualificationAttempt.freeze_contract (historical
v0.1 hashes its regression workbook unconditionally). No workload pin, frozen
result, model qualification or consumer acceptance changes with this archive.
David owns checkpoint record/verify, full-suite gates, integration, exact-set
rights review, target setup/naming, publication and final acceptance.
