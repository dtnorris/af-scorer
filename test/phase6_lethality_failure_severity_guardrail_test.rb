# frozen_string_literal: true

require_relative "test_helper"

class Phase6LethalityFailureSeverityGuardrailTest < Minitest::Test
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
    @previous_profile = ENV[AFScoring::Phase6LethalityFailureSeverityGuardrail::PROFILE_ENV]
    ENV.delete(AFScoring::Phase6LethalityFailureSeverityGuardrail::PROFILE_ENV)
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
    env_name = AFScoring::Phase6LethalityFailureSeverityGuardrail::PROFILE_ENV
    if @previous_profile.nil?
      ENV.delete(env_name)
    else
      ENV[env_name] = @previous_profile
    end
  end

  def test_default_profile_remains_unchanged
    prompt = builder.build(
      group_name: "challenge_character",
      dimensions: ["Lethality / Failure Severity"],
      adventure: @adventure,
      source_extraction: @extraction
    )

    assert_includes prompt.input, "# Lethality / Failure Severity Failure-Conversion Guardrail v0.1"
    refute_includes prompt.input, "# Lethality / Failure Severity Failure-State Topology Guardrail v0.3"
  end

  def test_phase6_profile_appends_failure_state_topology_protocol
    ENV[AFScoring::Phase6LethalityFailureSeverityGuardrail::PROFILE_ENV] =
      AFScoring::Phase6LethalityFailureSeverityGuardrail::PROFILE

    prompt = builder.build(
      group_name: "challenge_character",
      dimensions: ["Lethality / Failure Severity"],
      adventure: @adventure,
      source_extraction: @extraction
    )

    assert_includes prompt.input, "# Lethality / Failure Severity Failure-Conversion Guardrail v0.1"
    assert_includes prompt.input, "# Lethality / Failure Severity Failure-State Topology Guardrail v0.3"
    assert_includes prompt.input,
                    "pre-failure state → failure threshold → immediate post-failure state → mitigation / recovery → final state"
    assert_includes prompt.input, "success guidance —"
    assert_includes prompt.input, "exposure prevention —"
    assert_includes prompt.input, "pre-lock-in escape —"
    assert_includes prompt.input, "consequence conversion —"
    assert_includes prompt.input, "post-failure recovery —"
    assert_includes prompt.input, "continuation despite consequence —"
    assert_includes prompt.input, "no conversion —"
    assert_includes prompt.input, "Mandatory Escalation Counts as Expected Play"
    assert_includes prompt.input, "if a rule says that no additional effect occurs"
    refute_includes prompt.input, "# Lethality / Failure Severity Mitigation-Conversion Guardrail v0.2"
    assert_equal 1,
      prompt.input.scan("# Lethality / Failure Severity Failure-State Topology Guardrail v0.3").length
  end

  def test_retired_v0_2_profile_fails_closed
    ENV[AFScoring::Phase6LethalityFailureSeverityGuardrail::PROFILE_ENV] = "phase6-v0.2"

    error = assert_raises(AFScoring::ConfigurationError) do
      builder.build(
        group_name: "challenge_character",
        dimensions: ["Lethality / Failure Severity"],
        adventure: @adventure,
        source_extraction: @extraction
      )
    end

    assert_includes error.message, 'expected "phase6-v0.3"'
  end

  def test_phase6_profile_does_not_inject_into_unrelated_dimension
    ENV[AFScoring::Phase6LethalityFailureSeverityGuardrail::PROFILE_ENV] =
      AFScoring::Phase6LethalityFailureSeverityGuardrail::PROFILE

    prompt = builder.build(
      group_name: "challenge_character",
      dimensions: ["Rules / System-Mastery Demand"],
      adventure: @adventure,
      source_extraction: @extraction
    )

    refute_includes prompt.input, "# Lethality / Failure Severity Failure-State Topology Guardrail v0.3"
  end

  def test_unknown_profile_fails_closed
    ENV[AFScoring::Phase6LethalityFailureSeverityGuardrail::PROFILE_ENV] = "bogus"

    error = assert_raises(AFScoring::ConfigurationError) do
      builder.build(
        group_name: "challenge_character",
        dimensions: ["Lethality / Failure Severity"],
        adventure: @adventure,
        source_extraction: @extraction
      )
    end

    assert_includes error.message, "Unsupported Lethality / Failure Severity guardrail profile"
  end

  def test_guardrail_text_is_benchmark_blind
    text = AFScoring::Phase6LethalityFailureSeverityGuardrail::TEXT

    refute_match(/Tomb of Horrors/i, text)
    refute_match(/Witchlight/i, text)
    refute_match(/No Honour/i, text)
    refute_match(/House of Lament/i, text)
    refute_match(/Salvage Operation/i, text)
    refute_match(/ADV-\d{4}/i, text)
  end

  private

  def builder
    AFScoring::PromptBuilder.new(afao: @afao, assessment_spec: @assessment_spec)
  end
end
