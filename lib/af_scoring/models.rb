# frozen_string_literal: true

module AFScoring
  Evidence = Struct.new(:locator, :note, keyword_init: true)

  MetricAssessment = Struct.new(
    :metric, :kind, :assessment_state, :value, :range_low, :range_high,
    :confidence, :path_sensitive, :path_variation_affects_anchor,
    :rationale, :evidence, :adjacent_lower_reason, :adjacent_higher_reason,
    :rubric_ambiguity, :evidence_sufficient, :review_flags, :group,
    keyword_init: true
  ) do
    def scored?
      assessment_state == "Scored"
    end

    def insufficient_evidence?
      assessment_state == "Insufficient Evidence"
    end

    def uncertain?
      assessment_state == "Uncertain / Requires Source Verification"
    end
  end

  NormalizedGroup = Struct.new(:metrics, :observations, keyword_init: true)

  AssessmentPackage = Struct.new(
    :run_id, :adventure, :afao_version, :assessment_spec_version,
    :provider, :model, :source_file, :source_scope, :source_warnings,
    :metrics, :status, :review_disposition, :package_review_flags,
    keyword_init: true
  )
end
