# frozen_string_literal: true

require_relative "test_helper"

class Phase6SeriousnessGuardrailTest < Minitest::Test
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
    @previous_profile = ENV[AFScoring::Phase6SeriousnessGuardrail::PROFILE_ENV]
    ENV.delete(AFScoring::Phase6SeriousnessGuardrail::PROFILE_ENV)
    @afao = FakeAFAO.new("1.5")
    @assessment_spec = FakeAssessmentSpec.new("fixture assessment rules")
    @adventure = AdventureFixture.new(
      id: "ADV-0001",
      title: "Fixture Adventure",
      source_book: "Fixture Book",
      publisher: "Fixture Publisher",
      start_page: 1,
      end_page: 2
    )
    @extraction = ExtractionFixture.new(
      text: "<!-- PAGE: 1 -->\nfixture source",
      scope: "canonical_page_slice",
      source_file: "/tmp/fixture.md"
    )
  end

  def teardown
    env_name = AFScoring::Phase6SeriousnessGuardrail::PROFILE_ENV
    if @previous_profile.nil?
      ENV.delete(env_name)
    else
      ENV[env_name] = @previous_profile
    end
  end

  def test_default_profile_uses_reset_baseline_only
    prompt = builder.build(
      group_name: "experience_tone",
      dimensions: ["Seriousness"],
      adventure: @adventure,
      source_extraction: @extraction
    )

    refute_includes prompt.input, "# Seriousness Adversarial-Play Guardrail"
    refute_includes prompt.input, "# Seriousness Tonal-Hierarchy / Proxy-Weighting Guardrail"
    refute_includes prompt.input, "# Seriousness Direct Register-Comparison Decision Guardrail v0.3"
  end

  def test_phase6_profile_appends_direct_register_comparison_after_production_guardrail
    ENV[AFScoring::Phase6SeriousnessGuardrail::PROFILE_ENV] =
      AFScoring::Phase6SeriousnessGuardrail::PROFILE

    prompt = builder.build(
      group_name: "experience_tone",
      dimensions: ["Seriousness"],
      adventure: @adventure,
      source_extraction: @extraction
    )

    assert_includes prompt.input, "# Seriousness Tonal-Hierarchy / Proxy-Weighting Guardrail"
    assert_includes prompt.input, "# Seriousness Direct Register-Comparison Decision Guardrail v0.3"
    assert_includes prompt.input, "Build the Two Player-Facing Registers Independently"
    assert_includes prompt.input, "Objective Gravity Is Not Tonal Weight"
    assert_includes prompt.input, "Symmetric Treatment of the Lighter Register"
    assert_includes prompt.input, "For 4 ↔ 5:"
    assert_includes prompt.input, "This clarification is not a numeric correction"
    assert_operator(
      prompt.input.index("# Seriousness Direct Register-Comparison Decision Guardrail v0.3"),
      :>,
      prompt.input.index("# Seriousness Tonal-Hierarchy / Proxy-Weighting Guardrail")
    )
    assert_equal 1,
      prompt.input.scan("# Seriousness Direct Register-Comparison Decision Guardrail v0.3").length
  end

  def test_phase6_profile_does_not_inject_into_unrelated_dimension
    ENV[AFScoring::Phase6SeriousnessGuardrail::PROFILE_ENV] =
      AFScoring::Phase6SeriousnessGuardrail::PROFILE

    prompt = builder.build(
      group_name: "experience_tone",
      dimensions: ["Fantastic Weirdness"],
      adventure: @adventure,
      source_extraction: @extraction
    )

    refute_includes prompt.input, "# Seriousness Direct Register-Comparison Decision Guardrail v0.3"
  end

  def test_unknown_profile_fails_closed
    ENV[AFScoring::Phase6SeriousnessGuardrail::PROFILE_ENV] = "bogus"

    error = assert_raises(AFScoring::ConfigurationError) do
      builder.build(
        group_name: "experience_tone",
        dimensions: ["Seriousness"],
        adventure: @adventure,
        source_extraction: @extraction
      )
    end

    assert_includes error.message, "Unsupported Seriousness guardrail profile"
  end

  def test_guardrail_is_benchmark_blind_and_not_a_downward_score_instruction
    text = AFScoring::Phase6SeriousnessGuardrail::TEXT
    normalized = text.gsub(/\s+/, " ")

    refute_match(/Witchlight Carnival/i, text)
    refute_match(/Barrier Peaks/i, text)
    refute_match(/No Honour/i, text)
    refute_match(/Lost Mine/i, text)
    refute_match(/Tomb of Horrors/i, text)
    refute_match(/subtract one point/i, text)

    assert_includes normalized, "does not direct the scorer toward lower Seriousness values"
    assert_includes normalized, "Preserve score 4"
    assert_includes normalized, "Preserve score 5"
    assert_includes normalized, "The decision must follow the player-facing tonal evidence in either direction."
  end

  def test_guardrail_preserves_scope_and_blocks_proxy_substitution
    text = AFScoring::Phase6SeriousnessGuardrail::TEXT
    normalized = text.gsub(/\s+/, " ")

    assert_includes normalized, "Apply this clarification to the 2 ↔ 3, 3 ↔ 4, and 4 ↔ 5 boundaries."
    assert_includes normalized, "Preserve the existing production treatment of the 1 ↔ 2 boundary."
    assert_includes normalized, "Danger, urgency, lethality"
    assert_includes normalized, "none is standalone evidence"
    assert_includes normalized, "Less plot-central than the serious material"
  end

  private

  def builder
    AFScoring::PromptBuilder.new(afao: @afao, assessment_spec: @assessment_spec)
  end
end
