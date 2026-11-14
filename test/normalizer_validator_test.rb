# frozen_string_literal: true
require_relative "test_helper"

class NormalizerValidatorTest < Minitest::Test
  def build_package(score: 3)
    normalizer = AFScoring::Normalizer.new
    metrics = AFScoring::DimensionGroups::GROUPS.keys.flat_map do |group|
      normalizer.normalize(group, TestSupport.scored_group_payload(group, score: score)).metrics
    end
    adv = AFScoring::Adventure.new(id: "ADV-0001", title: "Fixture", source_book: "Book", publisher: "Pub", start_page: 1, end_page: 2)
    AFScoring::AssessmentPackage.new(
      run_id: "run", adventure: adv, afao_version: "1.0", assessment_spec_version: "0.1",
      provider: "fake", model: "fake", source_file: "source.md", source_scope: "canonical_page_slice",
      source_warnings: [], metrics: metrics, status: "PROPOSED", package_review_flags: []
    )
  end

  def test_complete_package_validates
    package = build_package
    assert_equal 20, package.metrics.length
    assert AFScoring::Validator.new.validate!(package)
  end

  def test_validator_accepts_explicit_experimental_metric_subset_but_default_still_requires_full_package
    normalized = AFScoring::Normalizer.new.normalize(
      "play_mix",
      TestSupport.scored_group_payload("play_mix")
    )
    package = AFScoring::AssessmentPackage.new(metrics: normalized.metrics)
    validator = AFScoring::Validator.new

    assert validator.validate!(
      package,
      expected_metrics: AFScoring::DimensionGroups.fetch("play_mix")
    )

    error = assert_raises(AFScoring::ValidationError) do
      validator.validate!(package)
    end
    assert_includes error.message, "Missing required metrics"
  end

  def test_single_interpretive_dimension_schema_and_normalization
    dimensions = ["Combat Emphasis"]
    schema = AFScoring::SchemaBuilder.for_group("play_mix", dimensions: dimensions)
    dimension_schema = schema.fetch("properties").fetch("dimensions")

    assert_equal 1, dimension_schema.fetch("minItems")
    assert_equal 1, dimension_schema.fetch("maxItems")
    assert_equal dimensions,
      dimension_schema.fetch("items").fetch("properties").fetch("dimension").fetch("enum")

    payload = TestSupport.scored_group_payload("play_mix")
    payload["dimensions"] = payload["dimensions"].select { |item| item["dimension"] == "Combat Emphasis" }
    normalized = AFScoring::Normalizer.new.normalize(
      "play_mix",
      payload,
      expected_dimensions: dimensions
    )

    assert_equal ["Combat Emphasis"], normalized.metrics.map(&:metric)
  end

  def test_sessions_dimension_can_be_scored_without_levels
    schema = AFScoring::SchemaBuilder.for_group("sessions_levels", dimensions: ["# of Sessions"])
    assert schema.fetch("properties").key?("sessions")
    refute schema.fetch("properties").key?("level_start")
    refute schema.fetch("properties").key?("level_end")

    payload = TestSupport.scored_group_payload("sessions_levels")
    payload.delete("level_start")
    payload.delete("level_end")
    normalized = AFScoring::Normalizer.new.normalize(
      "sessions_levels",
      payload,
      expected_dimensions: ["# of Sessions"]
    )

    assert_equal ["# of Sessions"], normalized.metrics.map(&:metric)
  end

  def test_sessions_schema_makes_assessment_state_and_values_mutually_consistent
    schema = AFScoring::SchemaBuilder.for_group(
      "sessions_levels",
      dimensions: ["# of Sessions"]
    )
    sessions = schema.fetch("properties").fetch("sessions")
    branches = sessions.fetch("oneOf")

    assert_equal 2, branches.length

    scored = branches.find do |branch|
      branch.fetch("properties").fetch("assessment_state").fetch("enum") == ["Scored"]
    end
    insufficient = branches.find do |branch|
      branch.fetch("properties").fetch("assessment_state").fetch("enum") == ["Insufficient Evidence"]
    end

    refute_nil scored
    refute_nil insufficient

    assert_equal "integer", scored.fetch("properties").fetch("normalized_sessions").fetch("type")
    assert_equal "integer", scored.fetch("properties").fetch("practical_range_low").fetch("type")
    assert_equal "integer", scored.fetch("properties").fetch("practical_range_high").fetch("type")
    assert_equal "integer", scored.fetch("properties").fetch("confidence").fetch("type")
    assert_equal "boolean", scored.fetch("properties").fetch("path_sensitive").fetch("type")
    assert_equal [true], scored.fetch("properties").fetch("evidence_sufficient").fetch("enum")

    assert_equal "null", insufficient.fetch("properties").fetch("normalized_sessions").fetch("type")
    assert_equal "null", insufficient.fetch("properties").fetch("confidence").fetch("type")
    assert_equal "null", insufficient.fetch("properties").fetch("path_sensitive").fetch("type")
    assert_equal [false], insufficient.fetch("properties").fetch("evidence_sufficient").fetch("enum")
  end

  def test_levels_dimension_returns_start_and_end_without_sessions
    schema = AFScoring::SchemaBuilder.for_group("sessions_levels", dimensions: ["Levels"])
    refute schema.fetch("properties").key?("sessions")
    assert schema.fetch("properties").key?("level_start")
    assert schema.fetch("properties").key?("level_end")

    payload = TestSupport.scored_group_payload("sessions_levels")
    payload.delete("sessions")
    normalized = AFScoring::Normalizer.new.normalize(
      "sessions_levels",
      payload,
      expected_dimensions: ["Levels"]
    )

    assert_equal ["Level Start", "Level End"], normalized.metrics.map(&:metric)
  end

  def test_out_of_range_score_fails
    package = build_package(score: 6)
    error = assert_raises(AFScoring::ValidationError) { AFScoring::Validator.new.validate!(package) }
    assert error.failures.any? { |f| f.include?("score must be an integer") }
  end
end
