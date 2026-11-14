# frozen_string_literal: true

require_relative "test_helper"

class GmbsBlindPromptResetTest < Minitest::Test
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
      assessment_spec: FakeAssessmentSpec.new("fixture production assessment rules")
    )
    @adventure = AdventureFixture.new(
      id: "ADV-9999",
      title: "Blind Fixture",
      source_book: "Fixture Book",
      publisher: "Fixture Publisher",
      start_page: 10,
      end_page: 20
    )
    @extraction = ExtractionFixture.new(
      text: "<!-- PAGE: 10 -->\nfixture canonical source",
      scope: "canonical_page_slice",
      source_file: "/tmp/blind-fixture.md"
    )
  end

  def test_focused_gmbs_uses_blind_reset_system_profile
    prompt = build_gmbs_prompt

    assert_equal AFScoring::PromptBuilder::GMBS_SYSTEM_INSTRUCTIONS,
      prompt.instructions
    refute_equal AFScoring::PromptBuilder::SYSTEM_INSTRUCTIONS, prompt.instructions
    assert_includes prompt.instructions,
      "independent blind AdventureFinder GM Beginner Suitability assessment"
    assert_includes prompt.instructions,
      "Do not search for, infer, or use any prior AdventureFinder score"
  end

  def test_focused_gmbs_excludes_production_prompt_and_gmbs_guardrails
    prompt = build_gmbs_prompt

    refute_includes prompt.input, "# AdventureFinder Production Assessment Rules"
    refute_includes prompt.input, "fixture production assessment rules"
    refute_includes prompt.input, "# GM Beginner Suitability Application Guardrail v0.1"
    refute_includes prompt.input, "# GM Beginner Suitability Exceptional-Pedagogy Decision Audit v0.5"
  end

  def test_focused_gmbs_contains_source_frozen_rubric_and_blind_task
    prompt = build_gmbs_prompt

    assert_includes prompt.input, "# Published Source Material"
    assert_includes prompt.input, "<!-- PAGE: 10 -->"
    assert_includes prompt.input, "fixture canonical source"
    assert_includes prompt.input, "# Frozen AFAO 1.6 GM Beginner Suitability Rubric"
    assert_includes prompt.input,
      "fixture rubric for GM Beginner Suitability / ADV-9999 / Blind Fixture"
    assert_includes prompt.input, "# Blind Assessment Task"
    assert_includes prompt.input,
      "Return the best-supported GM Beginner Suitability assessment required by the response schema."
    assert_includes prompt.input,
      "Populate adjacent_lower_reason when the assigned score is above 1"
  end

  def test_focused_gmbs_includes_operational_support_clarification_without_benchmark_answers
    prompt = build_gmbs_prompt

    assert_includes prompt.instructions, "# GMBS Operational-Support Clarification v0.3"
    assert_includes prompt.instructions,
      "A clear premise, objectives, sequence of events, encounter descriptions, or ending"
    assert_includes prompt.instructions,
      "do not by themselves establish score 2"
    assert_includes prompt.instructions,
      "Conceptual structure is not the same as"
    assert_includes prompt.instructions,
      "executable operating support"

    [
      "Blood Night",
      "The Eyes of At'ar",
      "Tomb of Horrors",
      "Lost Mine of Phandelver",
      "The House of Lament",
      "ADV-0168",
      "ADV-0132",
      "ADV-0034",
      "ADV-0262",
      "ADV-0287"
    ].each { |benchmark| refute_includes prompt.instructions, benchmark }
  end

  def test_player_beginner_suitability_remains_on_existing_production_prompt
    prompt = @builder.build(
      group_name: "beginner_suitability",
      dimensions: ["Player Beginner Suitability"],
      adventure: @adventure,
      source_extraction: @extraction
    )

    assert_equal AFScoring::PromptBuilder::SYSTEM_INSTRUCTIONS, prompt.instructions
    assert_includes prompt.input, "# AdventureFinder Production Assessment Rules"
    assert_includes prompt.input, "fixture production assessment rules"
    refute_includes prompt.input, "# Blind Assessment Task"
  end

  def test_gmbs_scorer_rubric_excludes_calibration_history_but_keeps_rules
    Dir.mktmpdir do |dir|
      path = File.join(dir, "afao.md")
      afao_text = TestSupport.minimal_afao(
        target_id: "ADV-0002",
        target_title: "Other Benchmark"
      )

      benchmark_heading = "#### Calibration Benchmarks"
      benchmark_index = afao_text.rindex(benchmark_heading)
      raise "GMBS calibration heading fixture not found" unless benchmark_index

      afao_text.insert(
        benchmark_index,
        <<~MD
          #### Calibration Rules

          This normative GMBS rule must remain available to the scorer.

        MD
      )
      afao_text << <<~MD

        #### Adjacent-Boundary Calibration

        Historical GMBS boundary discussion names calibrated cases and must be hidden.
      MD
      File.write(path, afao_text)

      rubric = AFScoring::AFAO.new(path).rubric_for_dimension(
        "GM Beginner Suitability",
        target_id: "ADV-9999",
        target_title: "Blind Future Adventure"
      )

      assert_includes rubric, "#### Calibration Rules"
      assert_includes rubric, "This normative GMBS rule must remain available to the scorer."
      assert_includes rubric, "| **1 — Minimal** | minimal |"
      assert_includes rubric, "| **5 — Dominant** | dominant |"
      refute_includes rubric, "#### Calibration Benchmarks"
      refute_includes rubric, "ADV-0002"
      refute_includes rubric, "Other Benchmark"
      refute_includes rubric, "#### Adjacent-Boundary Calibration"
      refute_includes rubric, "Historical GMBS boundary discussion"
    end
  end

  private

  def build_gmbs_prompt
    @builder.build(
      group_name: "beginner_suitability",
      dimensions: ["GM Beginner Suitability"],
      adventure: @adventure,
      source_extraction: @extraction
    )
  end
end
