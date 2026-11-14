# frozen_string_literal: true

require_relative "test_helper"

class ConfidenceSemanticsTest < Minitest::Test
  FakeAFAO = Struct.new(:version) do
    def rubric_for_group(group_name, target_id:, target_title:)
      "fixture rubric for #{group_name} / #{target_id} / #{target_title}"
    end

    def rubric_for_dimensions(dimensions, target_id:, target_title:)
      "fixture rubric for #{dimensions.join(', ')} / #{target_id} / #{target_title}"
    end
  end

  FakeAssessmentSpec = Struct.new(:prompt_text)
  AdventureFixture = Struct.new(
    :id, :title, :source_book, :publisher, :start_page, :end_page,
    keyword_init: true
  )
  ExtractionFixture = Struct.new(:text, :scope, :source_file, keyword_init: true)

  def setup
    @builder = AFScoring::PromptBuilder.new(
      afao: FakeAFAO.new("1.6"),
      assessment_spec: FakeAssessmentSpec.new("fixture assessment rules")
    )
    @adventure = AdventureFixture.new(
      id: "ADV-9999",
      title: "Confidence Fixture",
      source_book: "Fixture Book",
      publisher: "Fixture Publisher",
      start_page: 10,
      end_page: 20
    )
    @extraction = ExtractionFixture.new(
      text: "<!-- PAGE: 10 -->\nfixture canonical source",
      scope: "canonical_page_slice",
      source_file: "/tmp/confidence-fixture.md"
    )
  end

  def test_interpretive_schema_requires_documented_confidence_with_existing_range
    item = AFScoring::SchemaBuilder.for_group(
      "play_mix",
      dimensions: ["Combat Emphasis"]
    ).dig("properties", "dimensions", "items")
    confidence = item.dig("properties", "confidence")

    assert_includes item.fetch("required"), "confidence"
    assert_equal ["integer", "null"], confidence.fetch("type")
    assert_equal 0, confidence.fetch("minimum")
    assert_equal 100, confidence.fetch("maximum")
    assert_includes confidence.fetch("description"), "best-supported value"
    assert_includes confidence.fetch("description"), "does not alter the score"
  end

  def test_common_and_dedicated_interpretive_prompts_share_confidence_semantics
    prompts = [
      build_prompt("play_mix", "Combat Emphasis"),
      build_prompt("play_mix", "Exploration Emphasis"),
      build_prompt("gm_demands", "GM Preparation Burden"),
      build_prompt("beginner_suitability", "GM Beginner Suitability")
    ]

    prompts.each do |prompt|
      assert_includes prompt.input, "# Interpretive Confidence Semantics"
      assert_includes prompt.input,
        "confidence that the assigned rubric value is the best-supported permitted"
      assert_includes prompt.input, "A confidence of 0 means essentially no confidence"
      assert_includes prompt.input, "confidence 0 is exceptional"
      assert_includes prompt.input,
        "never move the score toward the middle because confidence is low"
    end

    assert_equal AFScoring::PromptBuilder::EE_QUALIFIED_SYSTEM_INSTRUCTIONS_V0_5,
      prompts.fetch(1).instructions
    assert_includes prompts.fetch(2).input,
      AFScoring::PromptBuilder::GM_PREPARATION_BURDEN_GUARDRAIL_V0_6
    assert_equal AFScoring::PromptBuilder::GMBS_SYSTEM_INSTRUCTIONS,
      prompts.fetch(3).instructions

    levels_prompt = build_prompt("sessions_levels", "Levels")
    refute_includes levels_prompt.input, "# Interpretive Confidence Semantics"
  end

  def test_zero_confidence_is_preserved_valid_and_flagged_without_coercion
    payload = TestSupport.scored_group_payload("play_mix", score: 3, confidence: 0)
    payload.fetch("dimensions").each do |dimension|
      dimension["rationale"] = "Substantive evidence supports 3 despite unexplained confidence uncertainty."
      dimension["evidence"] = [
        { "locator" => "PAGE: 10", "note" => "Substantive recurring evidence." },
        { "locator" => "PAGE: 12", "note" => "Adjacent anchors are clearly separated." }
      ]
      dimension["rubric_ambiguity"] = false
      dimension["evidence_sufficient"] = true
    end

    normalized = AFScoring::Normalizer.new.normalize("play_mix", payload)
    package = AFScoring::AssessmentPackage.new(
      metrics: normalized.metrics,
      source_warnings: [],
      package_review_flags: []
    )

    assert normalized.metrics.all? { |metric| metric.confidence == 0 }
    assert AFScoring::Validator.new.validate!(
      package,
      expected_metrics: AFScoring::DimensionGroups.fetch("play_mix")
    )

    AFScoring::ReviewRules.new.apply!(package)
    assert_equal "REVIEW_REQUIRED", package.review_disposition
    normalized.metrics.each do |metric|
      assert_equal 0, metric.confidence
      assert_includes metric.review_flags, "REVIEW:LOW_CONFIDENCE"
    end
  end

  private

  def build_prompt(group_name, dimension)
    @builder.build(
      group_name: group_name,
      dimensions: [dimension],
      adventure: @adventure,
      source_extraction: @extraction
    )
  end
end
