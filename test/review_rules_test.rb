# frozen_string_literal: true
require_relative "test_helper"

class ReviewRulesTest < Minitest::Test
  def test_low_confidence_and_path_anchor_pressure_require_review
    metric = AFScoring::MetricAssessment.new(
      metric: "Combat Emphasis", kind: "interpretive", assessment_state: "Scored", value: 3,
      confidence: 55, path_sensitive: true, path_variation_affects_anchor: true,
      rationale: "r", evidence: [AFScoring::Evidence.new(locator: "p1", note: "n")],
      adjacent_lower_reason: "lower", adjacent_higher_reason: "higher",
      rubric_ambiguity: false, evidence_sufficient: true, review_flags: [], group: "play_mix"
    )
    package = AFScoring::AssessmentPackage.new(metrics: [metric], source_warnings: [], package_review_flags: [])
    AFScoring::ReviewRules.new.apply!(package)
    assert_equal "REVIEW_REQUIRED", package.review_disposition
    assert_includes metric.review_flags, "REVIEW:LOW_CONFIDENCE"
    assert_includes metric.review_flags, "INFO:PATH_SENSITIVE"
    assert_includes metric.review_flags, "REVIEW:PATH_VARIATION_PRESSURES_ANCHOR"
  end

  def test_path_sensitive_alone_is_informational
    metric = AFScoring::MetricAssessment.new(
      metric: "Combat Emphasis", kind: "interpretive", assessment_state: "Scored", value: 3,
      confidence: 90, path_sensitive: true, path_variation_affects_anchor: false,
      rationale: "r", evidence: [AFScoring::Evidence.new(locator: "p1", note: "n")],
      adjacent_lower_reason: "lower", adjacent_higher_reason: "higher",
      rubric_ambiguity: false, evidence_sufficient: true, review_flags: [], group: "play_mix"
    )
    package = AFScoring::AssessmentPackage.new(metrics: [metric], source_warnings: [], package_review_flags: [])
    AFScoring::ReviewRules.new.apply!(package)
    assert_equal "NO_AUTOMATIC_REVIEW_TRIGGER", package.review_disposition
  end
end
