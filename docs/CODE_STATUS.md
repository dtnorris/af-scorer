# Code status and load-path policy

AdventureFinder preserves historical scorer work without presenting it as
current production architecture. Code is classified using three statuses:

- **current** — needed by a presently supported runtime;
- **historical-reproducibility** — retained to reproduce or inspect a completed
  experiment, but not part of normal operation;
- **dormant/uncertain** — apparently inactive, but not sufficiently proven
  obsolete to demote yet.

Classification follows current runtime reachability and support status, not a
file's age, name, or experimental origin. Operational clarifications that began
as experiments remain current when the supported scorer now depends on them.

## Current

`bin/af-score` and `require "af_scoring"` define the supported production path.
The canonical root continues to load catalog/source resolution, AFAO and
assessment specifications, current prompt construction (including qualified
production prompt profiles), schemas, providers, normalization, validation,
review rules, regression comparison, persistence, runner, and CLI code.

In particular, `PromptBuilder` is current. Do not demote a prompt clarification
merely because its lineage includes calibration or qualification work.
The Tactical Complexity morphology-equivalence guardrail v0.4 is likewise
current: it is unconditionally prepended to `PromptBuilder` and therefore
contributes to the ordinary production `challenge_character` prompt.

## Historical reproducibility

The following completed experiment implementations live under
`lib/af_scoring/experiments/` and are loaded only through
`require "af_scoring/experiments"`:

- the NoS two-stage experiment and runner/factory;
- standalone Phase-6 guardrail modules and runner metadata;

Their constants and behavior are retained; only their physical location and
load-path status change.

## Dormant / uncertain

The `gpt_oss_qualification` provider remains in the primary provider tree. The
current `Runner#build_provider` still recognizes that configured provider, so
this pass deliberately does not infer that it is obsolete. A later support
decision can demote or remove it with separate evidence.
