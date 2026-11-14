# frozen_string_literal: true

require_relative "test_helper"

class GmpbSurgicalHybridTest < Minitest::Test
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
      afao: FakeAFAO.new("1.6.1"),
      assessment_spec: FakeAssessmentSpec.new("fixture production assessment rules")
    )
    @adventure = AdventureFixture.new(
      id: "ADV-9999",
      title: "Dependency Fan-Out Fixture",
      source_book: "Fixture Book",
      publisher: "Fixture Publisher",
      start_page: 10,
      end_page: 20
    )
    @extraction = ExtractionFixture.new(
      text: "<!-- PAGE: 10 -->\nfixture canonical source",
      scope: "canonical_page_slice",
      source_file: "/tmp/gmpb-dependency-fanout-fixture.md"
    )
  end

  def test_v0_6_is_frozen_qualified_profile_without_v0_4_or_v0_5_runtime_constants
    refute AFScoring::PromptBuilder.const_defined?(
      :GM_PREPARATION_BURDEN_GUARDRAIL_V0_4, false
    )
    refute AFScoring::PromptBuilder.const_defined?(
      :GM_PREPARATION_BURDEN_GUARDRAIL_V0_5, false
    )

    guardrail = AFScoring::PromptBuilder::GM_PREPARATION_BURDEN_GUARDRAIL_V0_6

    assert_includes guardrail, "# Localized-Read Rule — 1 ↔ 2"
    assert_includes guardrail, "# Authored-Sequence Rule — 2 ↔ 3"
    assert_includes guardrail, "# Compact Whole-Unit Read Clarification — 1 ↔ 2"
    assert_includes guardrail, "# Precision-Sensitive Bounded-Site Clarification — 3 ↔ 4"
    assert_includes guardrail, "# Pre-Selection Readiness — 2 ↔ 3"
    assert_includes guardrail, "# Cross-Cutting Bounded Structure — 3 ↔ 4"

    assert_equal 1,
      guardrail.scan(
        "# GM Preparation Burden 4 ↔ 5 Dependency-Fan-Out Procedure v0.6"
      ).length

    refute_includes guardrail,
      "# Sustained Campaign-Management Clarification — 4 ↔ 5"
    refute_includes guardrail,
      "# Ordered Stages vs Campaign Management — 4 ↔ 5"
    refute_includes guardrail,
      "# Persistent Preparation Infrastructure Clarification — 4 ↔ 5"
    refute_includes guardrail,
      "# Ordered Stages vs Persistent Preparation Infrastructure — 4 ↔ 5"
    refute_includes guardrail,
      "# GM Preparation Burden 4 ↔ 5 Decision Procedure v0.5"

    assert_includes guardrail,
      "Do not equate the\namount of information needed to RECORD a state with the amount of preparation"
    assert_includes guardrail, "# Step 2 — Evaluate dependency fan-out"
    assert_includes guardrail,
      "A state variable can be compact to write down and still have broad preparation"
    assert_includes guardrail,
      "Compact representation does not cap the score when dependency fan-out remains"
    assert_includes guardrail,
      "Broad fan-out must create actual ordinary advance-preparation work."
  end

  def test_focused_gmpb_uses_v0_6_on_production_prompt_stack
    prompt = build_gmpb_prompt

    assert_equal AFScoring::PromptBuilder::SYSTEM_INSTRUCTIONS, prompt.instructions
    assert_includes prompt.input, "# AdventureFinder Production Assessment Rules"
    assert_includes prompt.input, "fixture production assessment rules"
    assert_includes prompt.input,
      AFScoring::PromptBuilder::GM_PREPARATION_BURDEN_GUARDRAIL_V0_6
    assert_equal 1,
      prompt.input.scan(
        "# GM Preparation Burden 4 ↔ 5 Dependency-Fan-Out Procedure v0.6"
      ).length
    refute_includes prompt.input, "wide active campaign-level field"
    refute_includes prompt.input,
      "# GM Preparation Burden 4 ↔ 5 Decision Procedure v0.5"
  end

  def test_v0_6_remains_benchmark_blind
    prompt = build_gmpb_prompt

    [
      "ADV-0200",
      "ADV-0288",
      "ADV-0262",
      "ADV-0287",
      "ADV-0032",
      "Lake Monster",
      "A Friend in Need",
      "Lost Mine of Phandelver",
      "House of Lament",
      "Dead in Thay",
      "Doomvault"
    ].each do |benchmark_marker|
      refute_includes prompt.input, benchmark_marker
    end
  end

  def test_unrelated_focused_dimension_does_not_receive_v0_6
    prompt = @builder.build(
      group_name: "gm_demands",
      dimensions: ["GM Improvisation Demand"],
      adventure: @adventure,
      source_extraction: @extraction
    )

    refute_includes prompt.input,
      "# GM Preparation Burden 4 ↔ 5 Dependency-Fan-Out Procedure v0.6"
  end

  private

  def build_gmpb_prompt
    @builder.build(
      group_name: "gm_demands",
      dimensions: ["GM Preparation Burden"],
      adventure: @adventure,
      source_extraction: @extraction
    )
  end
end
