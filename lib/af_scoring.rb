# frozen_string_literal: true

require_relative "af_scoring/errors"
require_relative "af_scoring/config"
require_relative "af_scoring/xlsx_reader"
require_relative "af_scoring/catalog"
require_relative "af_scoring/source_resolver"
require_relative "af_scoring/source_document"
require_relative "af_scoring/markdown_sections"
require_relative "af_scoring/afao"
require_relative "af_scoring/assessment_spec"
require_relative "af_scoring/selected_method"
require_relative "af_scoring/target_eligibility"
require_relative "af_scoring/dimension_groups"
require_relative "af_scoring/scoring_target"
require_relative "af_scoring/progress"
require_relative "af_scoring/models"
require_relative "af_scoring/schema_builder"
require_relative "af_scoring/prompt_builder"
require_relative "af_scoring/tactical_complexity_morphology_equivalence_guardrail"
require_relative "af_scoring/providers/base"
require_relative "af_scoring/providers/openai_provider"
require_relative "af_scoring/providers/ollama_provider"
require_relative "af_scoring/providers/gpt_oss_qualification_provider"
require_relative "af_scoring/normalizer"
require_relative "af_scoring/validator"
require_relative "af_scoring/review_rules"
require_relative "af_scoring/csv_writer"
require_relative "af_scoring/regression/reference_set"
require_relative "af_scoring/regression/comparator"
require_relative "af_scoring/runner"
require_relative "af_scoring/cli"

# Completed experimental profiles are retained under `af_scoring/experiments`
# and are intentionally absent from the canonical production load path.

module AFScoring
  VERSION = "0.1.0"
end
