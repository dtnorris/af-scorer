# Phase-6 Remediation Scorer Execution Contract

## Purpose

Phase-6 scorer guardrails are narrow, versioned prompt interventions used by external
local-model remediation experiments. They do not own experiment pass/fail policy or
score-triggered batch termination.

This contract keeps scorer behavior outcome-neutral so the evaluation repository can
complete diagnostic case sets even after strict remediation success becomes impossible.

## Scorer responsibilities

For every requested Phase-6 case, the scorer should:

1. resolve the requested canonical Adventure ID and source boundary normally;
2. preserve blind target scrubbing;
3. apply only the explicitly selected Phase-6 guardrail profile;
4. invoke the configured model;
5. validate and normalize the returned assessment using the ordinary schema;
6. persist the raw response and normalized result under the ordinary run contract; and
7. persist experimental provenance, including the active prompt profile and guardrail hash
   where the existing runner metadata module supplies them.

The current Phase-6 modules cover Social Interaction, Investigation Emphasis,
Lethality / Failure Severity, Puzzle / Problem-Solving Emphasis, and Seriousness.
Their anchor-preservation and anti-overcorrection language remains unchanged.

## Outcome neutrality

The scorer must not branch experiment execution based on comparison with an accepted
target. In particular, it must not stop or suppress later requested cases because:

- the score is adjacent rather than exact;
- the score is a hard miss;
- a known Phase-5 miss repeats;
- a protected control regresses;
- an external remediation criterion has failed; or
- an external qualification criterion can no longer be met.

Those facts are evaluator-side evidence, not scorer configuration.

## Integrity failures

The scorer should continue to fail clearly on ordinary integrity/configuration errors,
including unsupported guardrail profile names, inability to inject the intended focused
task guardrail, invalid source resolution, or structured-output validation failures under
the existing runner contract.

Whether a case-specific failure should pause a larger experiment is an evaluator/harness
decision. The scorer should report and persist enough evidence for that decision rather
than converting score quality into control flow.

## Relationship to Phase-6 runner metadata

Each active Phase-6 runner-metadata module marks the run experimental and records the
specific profile and guardrail SHA. That provenance is the mechanism by which downstream
evaluation can distinguish scorer configurations without encoding accepted target values
into scorer input.

No additional score-aware stopping logic belongs in these modules.

## Non-goals

This contract does not:

- relax any AFAO anchor;
- change any Phase-6 guardrail text;
- change remediation or qualification thresholds;
- authorize favorable reruns;
- authorize additional inference calls; or
- move oracle/accepted target values into scorer-visible context.
