# AdventureFinder Automated Assessment Review Rules

## Version 0.1-draft

**Status:** Draft  
**Purpose:** Initial deterministic validation and review-routing rules for LLM-produced AdventureFinder assessment proposals.

## 1. Scope

These rules govern only the automated review layer of `af-cli-scoring-utility`.
They do not alter AFAO 1.0 scoring semantics, the AdventureFinder Analysis Data /
Assessment Specification 0.1, or the authority required to make an assessment canonical.

Every LLM-produced package remains **PROPOSED** regardless of whether automatic review
triggers fire.

## 2. Rule Classes

The utility distinguishes three classes of automated findings.

### 2.1 Hard Validation Failure

A hard validation failure means the generated package cannot be represented as a valid
AdventureFinder assessment proposal under the governing specifications. The CLI exits
non-zero for that Adventure ID and does not emit a successfully completed assessment CSV.
Raw provider output MAY still be retained for debugging.

### 2.2 Review Required

A review-required finding means the package is structurally valid enough to inspect, but
one or more conditions warrant explicit editorial attention. The package remains
`PROPOSED` and receives review disposition `REVIEW_REQUIRED`.

### 2.3 Informational Warning

An informational warning records a condition useful to a reviewer but does not by itself
require review. The package remains `PROPOSED`. If no review-required condition exists,
its review disposition is `NO_AUTOMATIC_REVIEW_TRIGGER`.

`NO_AUTOMATIC_REVIEW_TRIGGER` does **not** mean Accepted or canonical.

## 3. Hard Validation Failures

The following are hard failures in v0.1:

- configured AMC, AFAO, Assessment Specification, or regression-index workbook is missing;
- requested Adventure ID is absent from AMC 2.1;
- required adventure Markdown source cannot be resolved;
- canonical page boundaries cannot be extracted when full-source fallback is disabled;
- a focused scoring call returns malformed or non-schema-conforming data that cannot be normalized;
- a required scoring group or required dimension is missing or duplicated;
- an interpretive score is outside AFAO's permitted state/value combinations;
- a scored interpretive value is not an integer from 1 through 5;
- a scored confidence value is outside 0 through 100;
- a scored Level Start or Level End is not an integer from 1 through 20;
- Level Start exceeds Level End when both are scored;
- a scored # of Sessions value or Practical Range violates AFAO session semantics;
- a scored # of Sessions best estimate falls outside its Practical Range;
- a required rationale is blank;
- required evidence is absent or contains blank locator/note fields;
- required adjacent-anchor falsification is missing for an interpretive score where an adjacent anchor exists.

The utility MUST NOT silently repair a malformed value into a plausible value.

## 4. Review-Required Rules

### R-001 — Insufficient Evidence

Trigger when # of Sessions or an interpretive dimension is assessed as
`Insufficient Evidence`.

Code: `REVIEW:INSUFFICIENT_EVIDENCE`

### R-002 — Uncertain Level Endpoint

Trigger when Level Start or Level End is `Uncertain / Requires Source Verification`.

Code: `REVIEW:LEVEL_UNCERTAIN`

### R-003 — Low Confidence

Until production calibration establishes a permanent operational threshold, confidence
below **60%** triggers review.

Code: `REVIEW:LOW_CONFIDENCE`

This threshold is provisional and implements, rather than replaces, Assessment
Specification 0.1 guidance.

### R-004 — Rubric Ambiguity

Trigger when the scorer explicitly identifies ambiguity in the governing rubric rather
than ordinary application uncertainty.

Code: `REVIEW:RUBRIC_AMBIGUITY`

### R-005 — Evidence Insufficient

Trigger when the scorer states that the supplied source evidence is insufficient to
support its proposed value even if the returned assessment state is otherwise scored.

Code: `REVIEW:EVIDENCE_INSUFFICIENT`

### R-006 — Source Boundary Uncertainty

Trigger when exact canonical source extraction could not be established and an explicit
fallback mode was used, or when a focused scorer reports canonical-boundary uncertainty.

Codes:

- `REVIEW:SOURCE_BOUNDARY_UNVERIFIED`
- `REVIEW:SOURCE_BOUNDARY_UNCERTAINTY`

### R-007 — Path Variation Pressures an Anchor

Path sensitivity alone does not trigger review. Trigger only when substantially supported
published paths materially pressure or cross an adjacent score boundary such that the
canonical value is difficult to stabilize.

Code: `REVIEW:PATH_VARIATION_PRESSURES_ANCHOR`

### R-008 — Possible Specification Contradiction

Trigger when a scorer identifies a possible conflict between governing AFAO or production
assessment rules.

Code: `REVIEW:POSSIBLE_SPEC_CONTRADICTION`

### R-009 — Regression Disagreement

In regression mode only, trigger when at least one proposed value disagrees with an
explicit AFAO calibration expectation derived after the blind proposal is complete.

Code: `REVIEW:REGRESSION_DISAGREEMENT`

### R-010 — No Regression Expectation

In regression mode only, trigger when the requested Adventure ID is in the regression
index but no explicit calibration expectation can be derived from AFAO 1.0.

Code: `REVIEW:NO_REGRESSION_EXPECTATIONS`

## 5. Informational Warnings

### I-001 — Moderate Confidence

A scored value with confidence from **60% through 74%** receives:

`INFO:MODERATE_CONFIDENCE`

This records material uncertainty without automatically routing every such case to review.

### I-002 — Path Sensitive

Any scored value with `Path Sensitive: Yes` receives:

`INFO:PATH_SENSITIVE`

This warning alone MUST NOT require review.

### I-003 — Filename-Based Source Resolution

When the source resolver uses its deterministic normalized-filename fallback rather than an
explicit source mapping, record:

`INFO:SOURCE_RESOLVED_BY_FILENAME`

This is informational only when the match is unique.

## 6. Review Disposition

After hard validation succeeds:

- if any `REVIEW:` code exists at package or metric level, disposition is `REVIEW_REQUIRED`;
- otherwise disposition is `NO_AUTOMATIC_REVIEW_TRIGGER`.

Both dispositions remain subordinate to package status `PROPOSED`.

The automated utility MUST NOT emit `Accepted` or otherwise declare its own proposal
canonical.

## 7. Regression Blindness

Regression expectations MUST NOT be supplied to the scoring model.

The implementation MUST separate:

1. the workbook-defined set of referenced Adventure IDs;
2. the blind scoring pass;
3. target-specific AFAO benchmark scrubbing from scorer-visible rubric text; and
4. post-score extraction/comparison of explicit AFAO calibration expectations.

The reference workbook may be inspected before scoring to identify which Adventure IDs are
eligible for regression. Expected score values are derived only after the proposal exists.

## 8. Revision Policy

These rules are intentionally conservative and provisional. Thresholds and routing rules
may be revised after measuring regression performance and human-review workload, without
changing AFAO dimension meanings.

Any change that materially alters automatic review disposition SHOULD receive a new
version of this specification.
