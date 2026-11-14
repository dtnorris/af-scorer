# CSV Output Contract — v0.1

The primary assessment CSV is **long-form**: one row per logical assessment value.
A complete AFAO 1.0 package therefore contains 20 rows:

- 1 `# of Sessions` row;
- 1 `Level Start` row;
- 1 `Level End` row;
- 17 interpretive dimension rows.

AFAO still has 19 matching dimensions because Levels is one ontology dimension represented
by two canonical endpoint values.

## Columns

| Column | Meaning |
| --- | --- |
| `run_id` | Unique scoring-run identifier. |
| `status` | Always `PROPOSED` for CLI-generated assessments. |
| `review_disposition` | `REVIEW_REQUIRED` or `NO_AUTOMATIC_REVIEW_TRIGGER`. |
| `adventure_id` | Canonical AMC Adventure ID. |
| `adventure_title` | Canonical AMC title. |
| `source_book` | Canonical containing source. |
| `book_publisher` | AMC publisher. |
| `start_page`, `end_page` | Canonical AMC boundaries. |
| `afao_version` | Governing ontology version. |
| `assessment_spec_version` | Governing assessment-protocol version. |
| `provider`, `model` | LLM provenance. |
| `source_file`, `source_scope` | Local evidence source and extraction mode. |
| `group` | Focused scoring-pass group. |
| `metric_kind` | `sessions`, `level`, or `interpretive`. |
| `metric` | Logical matching/analysis value name. |
| `assessment_state` | AFAO-defined state. |
| `value` | Sessions, level endpoint, or 1–5 score when scored. |
| `range_low`, `range_high` | # of Sessions Practical Range only. |
| `confidence` | AFAO confidence where applicable. |
| `path_sensitive` | AFAO path-sensitivity flag where applicable. |
| `path_variation_affects_anchor` | Whether authored path variation materially pressures the canonical placement. |
| `rationale` | Concise source-grounded assessment rationale. |
| `adjacent_lower_reason`, `adjacent_higher_reason` | Interpretive adjacent-anchor falsification. |
| `evidence` | JSON array of `{locator,note}` evidence items encoded inside the CSV cell. |
| `metric_review_flags` | Pipe-delimited metric-level review/info codes. |
| `package_review_flags` | Pipe-delimited package-level review/info codes. |

No CSV emitted by this utility is canonical merely because validation succeeds.
