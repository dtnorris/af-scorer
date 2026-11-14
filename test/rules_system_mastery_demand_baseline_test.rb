# frozen_string_literal: true

require_relative "test_helper"

class RulesSystemMasteryDemandBaselineTest < Minitest::Test
  EXPECTED_BENCHMARK_IDS = %w[
    ADV-0053
    ADV-0262
    ADV-0277
    ADV-0287
    ADV-0303
    ADV-0034
    ADV-0031
    ADV-0062
    ADV-0040
    ADV-0227
    ADV-0335
    ADV-0032
    ADV-0337
    ADV-0345
  ].freeze

  EXPECTED_SCALE_BAND_FIREWALL_IDS = %w[
    ADV-0053
    ADV-0262
    ADV-0277
    ADV-0287
    ADV-0303
    ADV-0040
  ].freeze

  EXPECTED_ANCHOR_LOCAL_SUFFICIENCY_IDS = %w[
    ADV-0262
    ADV-0287
    ADV-0062
    ADV-0031
    ADV-0335
    ADV-0040
    ADV-0227
    ADV-0345
    ADV-0032
    ADV-0337
  ].freeze

  FakeAFAO = Struct.new(:version) do
    def rubric_for_group(*)
      raise "focused RSMD baseline should request only the RSMD rubric"
    end

    def rubric_for_dimensions(dimensions, target_id:, target_title:)
      raise "unexpected focused dimensions: #{dimensions.inspect}" unless dimensions == ["Rules / System-Mastery Demand"]
      raise "missing target id" if target_id.to_s.empty?
      raise "missing target title" if target_title.to_s.empty?

      "AFAO-1.3-RSMD-RUBRIC-MARKER"
    end
  end

  FakeAssessmentSpec = Struct.new(:prompt_text)
  AdventureFixture = Struct.new(:id, :title, :source_book, :publisher, :start_page, :end_page, keyword_init: true)
  ExtractionFixture = Struct.new(:text, :scope, :source_file, keyword_init: true)

  def test_baseline_batch_fixture_covers_full_afao_1_3_rsmd_benchmark_set
    path = File.expand_path("../docs/rules-system-mastery-demand-baseline-v0.1.txt", __dir__)
    actual = File.readlines(path, chomp: true).map(&:strip).reject(&:empty?)

    assert_equal EXPECTED_BENCHMARK_IDS, actual
    assert_equal 14, actual.uniq.length
  end

  def test_scale_band_firewall_fixture_covers_targeted_six_adventure_diagnostic_set
    path = File.expand_path("../docs/rules-system-mastery-demand-v0.6-scale-band-firewall.txt", __dir__)
    actual = File.readlines(path, chomp: true).map(&:strip).reject(&:empty?)

    assert_equal EXPECTED_SCALE_BAND_FIREWALL_IDS, actual
    assert_equal 6, actual.uniq.length
  end

  def test_anchor_local_sufficiency_fixture_covers_cross_ladder_diagnostic_set
    path = File.expand_path("../docs/rules-system-mastery-demand-v0.9-anchor-local-sufficiency.txt", __dir__)
    actual = File.readlines(path, chomp: true).map(&:strip).reject(&:empty?)

    assert_equal EXPECTED_ANCHOR_LOCAL_SUFFICIENCY_IDS, actual
    assert_equal 10, actual.uniq.length
  end

  def test_focused_rsmd_baseline_appends_guardrail_v0_9_after_the_afao_1_3_rubric
    prompt = AFScoring::PromptBuilder.new(
      afao: FakeAFAO.new("1.3"),
      assessment_spec: FakeAssessmentSpec.new("fixture assessment rules")
    ).build(
      group_name: "challenge_character",
      dimensions: ["Rules / System-Mastery Demand"],
      adventure: AdventureFixture.new(
        id: "ADV-9999",
        title: "Fixture Adventure",
        source_book: "Fixture Book",
        publisher: "Fixture Publisher",
        start_page: 1,
        end_page: 2
      ),
      source_extraction: ExtractionFixture.new(
        text: "<!-- PAGE: 1 -->\nfixture source",
        scope: "canonical_page_slice",
        source_file: "/tmp/fixture.md"
      )
    )

    assert_includes prompt.input, "# AFAO 1.3 Rubric for This Focused Pass"
    assert_equal 1, prompt.input.scan("AFAO-1.3-RSMD-RUBRIC-MARKER").length
    rubric_match = prompt.input.match(
      /# AFAO 1\.3 Rubric for This Focused Pass\n\n(?<rubric>.*?)\n\n# Rules \/ System-Mastery Demand — Upper-Scale Adjudication Guardrail/m
    )
    refute_nil rubric_match, "expected focused AFAO rubric immediately before RSMD guardrail"
    assert_equal "AFAO-1.3-RSMD-RUBRIC-MARKER", rubric_match[:rubric].strip
    assert_includes prompt.input, "# Rules / System-Mastery Demand — Upper-Scale Adjudication Guardrail"
    assert_includes prompt.input, "Do not require a score of 4 to involve a single persistent or player-controlled system."
    assert_includes prompt.input, "Do not require a score of 5 to use one persistent subsystem, one type of mechanic, or adventure-wide universal coverage."
    assert_includes prompt.input, "explicitly taught, stable once learned, discoverable, or straightforward to execute after it is understood does not by itself reduce its System-Mastery Demand"
    assert_includes prompt.input, "different from one another rather than components of one unified system"
    assert_includes prompt.input, "3 → 4:"
    assert_includes prompt.input, "4 → 5:"
    assert_includes prompt.input, "# Score-5 Stable Learned Operation Clarification v0.2"
    normalized_prompt = prompt.input.gsub(/\s+/, " ")
    assert_includes normalized_prompt, "do not ask whether each individual operation remains difficult after the rules are learned"
    assert_includes normalized_prompt, "Repetition of a stable learned procedure can itself constitute repeated system operation"
    assert_includes normalized_prompt, "Distinguish execution difficulty from progression role"
    assert_includes normalized_prompt, "merely repeating a simple rule is not sufficient for score 5"
    assert_includes prompt.input, "# Score-5 Persistent-System Progression Accounting / Morphology Isolation v0.3"
    assert_equal 1, prompt.input.scan("# Rules / System-Mastery Demand — Upper-Scale Adjudication Guardrail").length
    assert_equal 1, prompt.input.scan("# Score-5 Stable Learned Operation Clarification v0.2").length
    assert_equal 1, prompt.input.scan("# Score-5 Persistent-System Progression Accounting / Morphology Isolation v0.3").length
    assert_includes normalized_prompt, "Evaluate the recognized Extreme-demand forms independently"
    assert_includes normalized_prompt, "Those are alternative ways Extreme demand can arise, not cumulative requirements of the persistent-system route"
    assert_includes normalized_prompt, "assess the **whole system-mediated progression loop**"
    assert_includes normalized_prompt, "Do not automatically reclassify those activities as merely \"exploration,\" \"finding keys,\" \"locating objectives,\" or another nonmechanical progression structure"
    assert_includes normalized_prompt, "**\"principal progression challenge\" is a structural test, not a difficulty test**"
    assert_includes normalized_prompt, "Across multiple major progression steps, does advancement repeatedly require players to retain, acquire, select, transfer, apply, or otherwise correctly operate the persistent mechanical system?"
    assert_includes normalized_prompt, "Preserve score 4 when the continuing system mainly modifies access, convenience, traversal, options, or resources"
    assert_includes normalized_prompt, "Do not inflate to score 5 merely because an adventure contains keys, gates, repeated checks, or a recurring procedure"
    assert_includes prompt.input, "# Rules / System-Mastery Demand 1 ↔ 2 Player-Knowledge Dependency Clarification v0.4"
    assert_equal 1, prompt.input.scan("# Rules / System-Mastery Demand 1 ↔ 2 Player-Knowledge Dependency Clarification v0.4").length
    assert_includes normalized_prompt, "**Mechanical exposure is not itself System-Mastery Demand.**"
    assert_includes normalized_prompt, "**ordinary basic rules use is broader than attacks and ability checks alone**"
    assert_includes normalized_prompt, "Breadth of ordinary rules exposure is not equivalent to player system mastery"
    assert_includes normalized_prompt, "bounded but meaningful player-facing mechanical-knowledge dependency"
    assert_includes normalized_prompt, "Could players generally participate effectively through straightforward or intuitive choices while the GM administers the relevant mechanics"
    assert_includes normalized_prompt, "Preserve score 2 when a localized mechanical interaction genuinely makes player understanding consequential"
    assert_includes normalized_prompt, "Low does not require recurrence, a persistent subsystem, sustained mastery, or a mechanic that carries across the adventure"
    assert_includes normalized_prompt, "Do not choose 2 merely because there are many mechanics"
    assert_includes prompt.input, "# Rules / System-Mastery Demand 1 ↔ 2 Advantage-vs-Dependency Clarification v0.5"
    assert_equal 1, prompt.input.scan("# Rules / System-Mastery Demand 1 ↔ 2 Advantage-vs-Dependency Clarification v0.5").length
    assert_includes normalized_prompt, "**A mechanically informed advantage is not automatically a mechanical-knowledge dependency.**"
    assert_includes normalized_prompt, "bonus, shortcut, safer route, optional resource, alternate tactic, or improved local outcome"
    assert_includes normalized_prompt, "lack of the cited mechanical understanding must create a meaningful player-facing disadvantage in effective participation or resolution"
    assert_includes normalized_prompt, "Score 2 does not require the mechanic to be mandatory or the only successful solution"
    assert_includes normalized_prompt, "**Do not convert intuitive fictional reasoning into system mastery merely because the GM resolves that choice mechanically.**"
    assert_includes normalized_prompt, "discovering that an authored feature grants a stated benefit and then choosing to use that benefit does not automatically establish Low demand"
    assert_includes normalized_prompt, "**Preserve score 2 when the mechanical relationship itself—not merely the fictional premise or the availability of an advantageous option—meaningfully determines"
    assert_includes normalized_prompt, 'Do not let "mechanically useful" substitute for "successful play meaningfully depends on mechanical understanding."'
    assert_includes prompt.input, "# RSMD Scale-Band Precedence / 1↔2 and 2↔3 Firewall v0.6"
    assert_equal 1, prompt.input.scan("# RSMD Scale-Band Precedence / 1↔2 and 2↔3 Firewall v0.6").length
    assert_includes normalized_prompt, "Apply this as a decision-order rule so lower-boundary clarifications do not override evidence for Moderate or higher"
    assert_includes normalized_prompt, "does not modify the existing 3 ↔ 4 or 4 ↔ 5 adjudication rules"
    assert_includes normalized_prompt, "Routine mechanical exposure, GM-administered procedures, intuitive fictional choices, and merely optional mechanical advantages do not become qualifying demand merely because they recur"
    assert_includes normalized_prompt, "the adventure has crossed the **2 → 3 threshold**"
    assert_includes normalized_prompt, "Do not reuse the v0.4/v0.5 lower-boundary discounts as an adventure-global completion test to demote the candidate to 1 or 2"
    assert_includes normalized_prompt, "For the **2 ↔ 3 boundary, persistence is not required**"
    assert_includes normalized_prompt, "Continuing cross-location state, tools, procedures, or system continuity belongs to the 3 ↔ 4 boundary, not the 2 ↔ 3 boundary"
    assert_includes normalized_prompt, "a genuine mechanical-knowledge dependency may be bounded to one substantive challenge or resolution"
    assert_includes normalized_prompt, "Do not require the cited mechanic to recur, govern every route, or be necessary for overall adventure completion"
    assert_includes normalized_prompt, "**Explicit teaching, clear publication, or easy discovery does not by itself erase a score-2 dependency.**"
    assert_includes normalized_prompt, "stop and adjudicate 3–5 instead"
    assert_includes prompt.input, "# RSMD Anchor-Local Sufficiency / Next-Band Leakage Firewall v0.9"
    assert_equal 1, prompt.input.scan("# RSMD Anchor-Local Sufficiency / Next-Band Leakage Firewall v0.9").length
    assert_includes normalized_prompt, "test that score against **its own positive AFAO conditions**"
    assert_includes normalized_prompt, "failure to establish score N+1 is a reason to stop at N, not a reason to fall back below N"
    assert_includes normalized_prompt, "**explicitly taught, prescribed, scripted, or clearly discoverable is not synonymous with GM-administered**"
    assert_includes normalized_prompt, "**Localized, discrete, heterogeneous, or separately resolved mechanical problems are compatible with score 3.**"
    assert_includes normalized_prompt, "Do not require a continuing player-operated system, persistent state, carry-forward tool, sustained operating layer, or progression-shaping mechanical ecology to award score 3"
    assert_includes normalized_prompt, "Score 4 can be established through either:"
    assert_includes normalized_prompt, "**Do not require score-5 progression-bearing operation to establish score 4.**"
    assert_includes normalized_prompt, "Mechanical variety or density alone does not establish score 4"
    assert_includes normalized_prompt, "Score 5 is established when, across multiple major challenges, successful progression or effective resolution repeatedly consists of correctly operating, interpreting, exploiting, or adapting to consequential mechanics"
    assert_includes normalized_prompt, "Those stricter conditions are not a hidden score-6 gate"
    assert_includes normalized_prompt, "do not inflate to 5 from mechanical density, variety, a large collection of optional or completionist interactions"
    assert_includes normalized_prompt, "this firewall forbids next-band leakage, not conservative judgment"
    assert_includes prompt.input, "Scoring dimension: Rules / System-Mastery Demand"
    refute_match(/advanced mastery|adventure-wide coverage|ordinary competence being insufficient/i, prompt.input)
  end


  def test_rsmd_v0_9_inherits_directly_from_v0_6_without_benchmark_hardcoding
    v0_6 = AFScoring::PromptBuilder::RULES_SYSTEM_MASTERY_DEMAND_GUARDRAIL_V0_6
    v0_9 = AFScoring::PromptBuilder::RULES_SYSTEM_MASTERY_DEMAND_GUARDRAIL_V0_9

    assert v0_9.start_with?(v0_6)
    assert_equal 1, v0_9.scan("# RSMD Anchor-Local Sufficiency / Next-Band Leakage Firewall v0.9").length
    refute_includes v0_9, "Differentiated-Response Morphology Isolation / Anti-Inflation v0.7"
    refute_includes v0_9, "Differentiated-Response Expected-Play / Optionality Accounting v0.8"
    refute_match(/ADV-\d{4}|Mad Wizard|Obstacle Course|Barrier Peaks|Doom of Ythryn|Trobriand|White Plume|House of Lament|No Honour/i, v0_9)
  end

  def test_rsmd_upper_scale_guardrail_is_dimension_scoped
    builder = AFScoring::PromptBuilder.new(
      afao: FakeAFAO.new("1.3"),
      assessment_spec: FakeAssessmentSpec.new("fixture assessment rules")
    )

    assert_equal "", builder.send(:rules_system_mastery_demand_guardrail_block, ["Tactical Complexity"])
    assert_includes(
      builder.send(:rules_system_mastery_demand_guardrail_block, ["Rules / System-Mastery Demand"]),
      "# RSMD Anchor-Local Sufficiency / Next-Band Leakage Firewall v0.9"
    )
  end
end
