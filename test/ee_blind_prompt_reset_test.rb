# frozen_string_literal: true

require_relative "test_helper"

class EeBlindPromptResetTest < Minitest::Test
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

  def test_focused_ee_uses_qualified_system_profile
    prompt = build_ee_prompt

    assert_equal AFScoring::PromptBuilder::EE_QUALIFIED_SYSTEM_INSTRUCTIONS_V0_5,
      prompt.instructions
    refute_equal AFScoring::PromptBuilder::SYSTEM_INSTRUCTIONS, prompt.instructions
    assert_includes prompt.instructions,
      "independent blind AdventureFinder Exploration Emphasis assessment"
    assert_includes prompt.instructions,
      "Do not search for, infer, or use any prior AdventureFinder score"
  end

  def test_focused_ee_excludes_production_prompt_shell
    prompt = build_ee_prompt

    refute_includes prompt.input, "# AdventureFinder Production Assessment Rules"
    refute_includes prompt.input, "fixture production assessment rules"
    refute_includes prompt.input, "# Focused Assessment Task"
  end

  def test_focused_ee_contains_source_frozen_rubric_and_blind_task
    prompt = build_ee_prompt

    assert_includes prompt.input, "# Published Source Material"
    assert_includes prompt.input, "<!-- PAGE: 10 -->"
    assert_includes prompt.input, "fixture canonical source"
    assert_includes prompt.input, "# Frozen AFAO 1.6 Exploration Emphasis Rubric"
    assert_includes prompt.input,
      "fixture rubric for Exploration Emphasis / ADV-9999 / Blind Fixture"
    assert_includes prompt.input, "# Blind Assessment Task"
    assert_includes prompt.input,
      "Return the best-supported Exploration Emphasis assessment required by the response schema."
    assert_includes prompt.input,
      "Populate adjacent_lower_reason when the assigned score is above 1"
  end

  def test_qualified_system_instructions_do_not_encode_known_ee_benchmarks
    instructions = AFScoring::PromptBuilder::EE_QUALIFIED_SYSTEM_INSTRUCTIONS_V0_5

    [
      "Salvage Operation",
      "No Honour Among Thieves",
      "Call of the Wild",
      "Lost Mine of Phandelver",
      "Tomb of Horrors",
      "ADV-0230",
      "ADV-0062",
      "ADV-0053",
      "ADV-0262",
      "ADV-0034"
    ].each { |benchmark| refute_includes instructions, benchmark }
  end

  def test_ee_v0_5_clarification_distinguishes_substantive_progression_from_required_access
    instructions = AFScoring::PromptBuilder::EE_QUALIFIED_SYSTEM_INSTRUCTIONS_V0_5

    assert_includes instructions, "# Exploration Emphasis Operational Clarification v0.5"
    assert_includes instructions, "Environmental features are not automatically exploration play."
    assert_includes instructions,
      "Do not accumulate many discrete rooms, obstacles, checks,"
    assert_includes instructions,
      "Use a substantive-progression test, not a necessity test."
    assert_includes instructions,
      "Necessity, recurrence, and gating are not by themselves"
    assert_includes instructions, "Use a compression counterfactual"
    refute_includes instructions, "Use a progression-carrier test."
  end

  def test_ee_v0_5_clarification_does_not_compress_environment_centered_challenges
    instructions = AFScoring::PromptBuilder::EE_QUALIFIED_SYSTEM_INSTRUCTIONS_V0_5

    assert_includes instructions,
      "Apply that counterfactual to environmental access or connective procedure, not to erase"
    assert_includes instructions,
      "environment-centered challenges themselves."
    assert_match(
      /compressing\s+that environmental activity would remove part of the challenge/,
      instructions
    )
  end

  def test_ee_v0_5_clarification_preserves_overlapping_dimensions
    instructions = AFScoring::PromptBuilder::EE_QUALIFIED_SYSTEM_INSTRUCTIONS_V0_5

    assert_includes instructions,
      "AdventureFinder dimensions are analytically independent but are not mutually"
    assert_includes instructions,
      "Do not subtract from Exploration Emphasis merely because the same play"
    assert_includes instructions,
      "even when another dimension also applies."
    assert_includes instructions,
      "do not automatically displace Exploration as a dominant mode."
  end

  def test_ee_v0_5_clarification_preserves_compact_linear_site_guardrail
    instructions = AFScoring::PromptBuilder::EE_QUALIFIED_SYSTEM_INSTRUCTIONS_V0_5

    assert_includes instructions,
      "Do not lower Exploration Emphasis because a site is compact, linear, bounded,"
    assert_includes instructions,
      "Structural Openness and geographic scale are separate."
    assert_includes instructions,
      "A compact or linear site can still have high Exploration Emphasis"
  end

  def test_ee_v0_5_clarification_preserves_bidirectional_middle_scale_pressure
    instructions = AFScoring::PromptBuilder::EE_QUALIFIED_SYSTEM_INSTRUCTIONS_V0_5

    assert_includes instructions, "For the 1 <-> 2 boundary"
    assert_includes instructions, "For the 2 <-> 3 boundary"
    assert_includes instructions,
      "recurrence or necessity alone does not promote it to Score 4."
    assert_includes instructions, "For the 3 <-> 4 boundary"
    assert_includes instructions,
      "It does not require Exploration to dominate the overall narrative,"
    assert_includes instructions,
      "may be equally important without falsifying Score 4."
    assert_includes instructions,
      "Score 3 is not the default"
    assert_includes instructions,
      "not whether it exceeds the others."
    assert_includes instructions,
      "principally functions as access, transition, gating, or implementation"
  end

  def test_ee_v0_5_clarification_uses_organizational_dominance_for_upper_endpoint
    instructions = AFScoring::PromptBuilder::EE_QUALIFIED_SYSTEM_INSTRUCTIONS_V0_5

    assert_includes instructions, "For the 4 <-> 5 boundary"
    assert_includes instructions,
      "Score 5 does not require the absence of combat, puzzles,"
    assert_includes instructions,
      "Treat Dominant as an organizational test, not an exclusivity or majority-of-table-time"
    assert_match(
      /do not by\s+themselves hold an adventure at Score 4/,
      instructions
    )
    assert_includes instructions,
      "organizationally independent of environmental"
  end

  def test_combat_emphasis_remains_on_existing_production_prompt
    prompt = @builder.build(
      group_name: "play_mix",
      dimensions: ["Combat Emphasis"],
      adventure: @adventure,
      source_extraction: @extraction
    )

    assert_equal AFScoring::PromptBuilder::SYSTEM_INSTRUCTIONS, prompt.instructions
    assert_includes prompt.input, "# AdventureFinder Production Assessment Rules"
    assert_includes prompt.input, "fixture production assessment rules"
    refute_includes prompt.input, "# Blind Assessment Task"
  end

  def test_ee_scorer_rubric_excludes_calibration_history_but_keeps_normative_rules
    Dir.mktmpdir do |dir|
      path = File.join(dir, "afao.md")
      afao_text = TestSupport.minimal_afao(
        target_id: "ADV-0002",
        target_title: "Other Benchmark"
      )

      ee_start = afao_text.index("### 4. Exploration Emphasis")
      ee_finish = afao_text.index("### 5. Social Interaction Emphasis", ee_start)
      benchmark_index = afao_text.index("#### Calibration Benchmarks", ee_start)
      unless ee_start && ee_finish && benchmark_index && benchmark_index < ee_finish
        raise "Exploration Emphasis calibration heading fixture not found"
      end

      afao_text.insert(
        benchmark_index,
        <<~MD
          #### Calibration Rules

          This normative Exploration Emphasis rule must remain available to the scorer.

        MD
      )
      File.write(path, afao_text)

      rubric = AFScoring::AFAO.new(path).rubric_for_dimension(
        "Exploration Emphasis",
        target_id: "ADV-9999",
        target_title: "Blind Future Adventure"
      )

      assert_includes rubric, "#### Calibration Rules"
      assert_includes rubric,
        "This normative Exploration Emphasis rule must remain available to the scorer."
      assert_includes rubric, "| **1 — Minimal** | minimal |"
      assert_includes rubric, "| **5 — Dominant** | dominant |"
      refute_includes rubric, "#### Calibration Benchmarks"
      refute_includes rubric, "ADV-0002"
      refute_includes rubric, "Other Benchmark"
    end
  end

  private

  def build_ee_prompt
    @builder.build(
      group_name: "play_mix",
      dimensions: ["Exploration Emphasis"],
      adventure: @adventure,
      source_extraction: @extraction
    )
  end
end
