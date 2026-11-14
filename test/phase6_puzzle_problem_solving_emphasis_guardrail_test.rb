# frozen_string_literal: true

require_relative "test_helper"

class Phase6PuzzleProblemSolvingEmphasisGuardrailTest < Minitest::Test
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
    @previous_profile = ENV[AFScoring::Phase6PuzzleProblemSolvingEmphasisGuardrail::PROFILE_ENV]
    ENV.delete(AFScoring::Phase6PuzzleProblemSolvingEmphasisGuardrail::PROFILE_ENV)
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
    env_name = AFScoring::Phase6PuzzleProblemSolvingEmphasisGuardrail::PROFILE_ENV
    if @previous_profile.nil?
      ENV.delete(env_name)
    else
      ENV[env_name] = @previous_profile
    end
  end

  def test_default_profile_remains_frozen_v0_1
    prompt = builder.build(
      group_name: "play_mix",
      dimensions: ["Puzzle / Problem-Solving Emphasis"],
      adventure: @adventure,
      source_extraction: @extraction
    )

    assert_includes prompt.input, "# Puzzle / Problem-Solving Emphasis 1 ↔ 2 Boundary Guardrail v0.1"
    refute_includes prompt.input, "# Puzzle / Problem-Solving Emphasis Low-Anchor Admission Guardrail v0.2"
  end

  def test_phase6_profile_appends_only_low_anchor_admission_clarification
    ENV[AFScoring::Phase6PuzzleProblemSolvingEmphasisGuardrail::PROFILE_ENV] =
      AFScoring::Phase6PuzzleProblemSolvingEmphasisGuardrail::PROFILE

    prompt = builder.build(
      group_name: "play_mix",
      dimensions: ["Puzzle / Problem-Solving Emphasis"],
      adventure: @adventure,
      source_extraction: @extraction
    )

    assert_includes prompt.input, "# Puzzle / Problem-Solving Emphasis 1 ↔ 2 Boundary Guardrail v0.1"
    assert_includes prompt.input, "# Puzzle / Problem-Solving Emphasis Low-Anchor Admission Guardrail v0.2"
    assert_includes prompt.input, "Admission Test — Meaningful How-Problem, Not Independent Puzzle Mode"
    assert_includes prompt.input, "None of those properties is a standalone reason to assign score 1."
    assert_includes prompt.input, "Preserve Minimal — A How-Problem Must Actually Remain"
    assert_includes prompt.input, "It changes only the admission calibration at the frozen 1 ↔ 2 boundary."
    assert_equal 1,
      prompt.input.scan("# Puzzle / Problem-Solving Emphasis Low-Anchor Admission Guardrail v0.2").length
  end

  def test_phase6_profile_does_not_inject_into_unrelated_dimension
    ENV[AFScoring::Phase6PuzzleProblemSolvingEmphasisGuardrail::PROFILE_ENV] =
      AFScoring::Phase6PuzzleProblemSolvingEmphasisGuardrail::PROFILE

    prompt = builder.build(
      group_name: "play_mix",
      dimensions: ["Exploration Emphasis"],
      adventure: @adventure,
      source_extraction: @extraction
    )

    refute_includes prompt.input, "# Puzzle / Problem-Solving Emphasis Low-Anchor Admission Guardrail v0.2"
  end

  def test_unknown_profile_fails_closed
    ENV[AFScoring::Phase6PuzzleProblemSolvingEmphasisGuardrail::PROFILE_ENV] = "bogus"

    error = assert_raises(AFScoring::ConfigurationError) do
      builder.build(
        group_name: "play_mix",
        dimensions: ["Puzzle / Problem-Solving Emphasis"],
        adventure: @adventure,
        source_extraction: @extraction
      )
    end

    assert_includes error.message, "Unsupported Puzzle / Problem-Solving Emphasis guardrail profile"
  end

  def test_guardrail_text_is_benchmark_blind_and_scoped_to_lower_boundary
    text = AFScoring::Phase6PuzzleProblemSolvingEmphasisGuardrail::TEXT

    refute_match(/Call of the Wild/i, text)
    refute_match(/No Honour/i, text)
    refute_match(/House of Lament/i, text)
    refute_match(/Tomb of Horrors/i, text)
    refute_match(/White Plume Mountain/i, text)

    assert_includes text, "applies only to the Minimal ↔ Low"
    assert_includes text, "It does not alter"
    assert_includes text, "Do not decide 1 ↔ 2 by asking whether Puzzle / Problem-Solving is a recurring"
  end

  private

  def builder
    AFScoring::PromptBuilder.new(afao: @afao, assessment_spec: @assessment_spec)
  end
end
