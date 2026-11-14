# frozen_string_literal: true

require_relative "test_helper"

class TacticalComplexityMorphologyEquivalenceGuardrailTest < Minitest::Test
  EXPECTED_DIAGNOSTIC_IDS = %w[
    ADV-0303
    ADV-0062
    ADV-0248
    ADV-0230
    ADV-0232
    ADV-0223
  ].freeze

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

  def test_six_case_diagnostic_fixture_is_exact_and_unique
    path = File.expand_path("../docs/tactical-complexity-upper-end-v0.2-diagnostic.txt", __dir__)
    actual = File.readlines(path, chomp: true).map(&:strip).reject(&:empty?)

    assert_equal EXPECTED_DIAGNOSTIC_IDS, actual
    assert_equal 6, actual.uniq.length
  end

  def test_single_tactical_complexity_prompt_receives_v0_4_once
    prompt = builder.build(
      group_name: "challenge_character",
      dimensions: ["Tactical Complexity"],
      adventure: @adventure,
      source_extraction: @extraction
    )

    assert_equal 1, prompt.input.scan(heading).length
    assert_operator prompt.input.index(heading), :<, prompt.input.index("# Focused Assessment Task")
  end

  def test_default_challenge_character_prompt_receives_v0_4_once
    prompt = builder.build(
      group_name: "challenge_character",
      adventure: @adventure,
      source_extraction: @extraction
    )

    assert_equal 1, prompt.input.scan(heading).length
  end

  def test_rsmd_only_prompt_does_not_receive_v0_4
    prompt = builder.build(
      group_name: "challenge_character",
      dimensions: ["Rules / System-Mastery Demand"],
      adventure: @adventure,
      source_extraction: @extraction
    )

    refute_includes prompt.input, heading
  end

  def test_v0_4_replaces_v0_2_adjudication_and_does_not_inherit_v0_3
    guardrail = AFScoring::TacticalComplexityMorphologyEquivalenceGuardrail::TEXT

    refute_includes guardrail, "Morphology-Equivalence Guardrail v0.2"
    refute_includes guardrail, "major means substantively major"
    refute_includes guardrail, "a single keyed encounter can itself constitute"
    assert_match(/only after the ordinary AFAO analysis has independently\s+established score 4/i, guardrail)
    assert_match(/inert for the 1 ↔ 2, 2 ↔ 3, and 3 ↔ 4 boundaries/, guardrail)
  end

  def test_guardrail_uses_direct_live_decision_load_and_forbids_proxy_gates
    guardrail = normalized_guardrail

    assert_includes guardrail, "Do not infer Tactical Complexity from structural exceptionalism."
    assert_includes guardrail, "does not need multiple objectives, unpredictable state, majority table-time coverage, continuous peak density, or adventure-wide prevalence"
    assert_includes guardrail, "Compare 4 and 5 directly by the density, coupling, substantive weight, and repeated tactical reprioritization of the live decision problem."
    assert_includes guardrail, "most, ordinary, or characteristic play is simpler"
    assert_includes guardrail, "a distributed qualifying sequence is not itself dominant"
    assert_includes guardrail, "overall objective is single, clear, or stable"
    assert_includes guardrail, "relevant state changes are predictable"
    assert_includes guardrail, "simpler play intervenes"
    assert_includes guardrail, "one keyed encounter or location"
    assert_includes guardrail, "multiple simultaneous objectives are absent"
  end

  def test_guardrail_preserves_v0_2_two_route_core_without_cross_route_requirements
    guardrail = normalized_guardrail

    assert_includes guardrail, "Route A — multiple substantively major encounters or encounter sequences"
    assert_includes guardrail, "Route B — one dominant sustained mandatory encounter sequence"
    assert_includes guardrail, "Either route is sufficient."
    assert_includes guardrail, "Do not import Route-B continuity, dominance, or coverage requirements into Route A"
    assert_includes guardrail, "do not require Route A merely because Route B is absent"
  end

  def test_guardrail_keeps_short_score_4_counterpressure
    guardrail = normalized_guardrail

    assert_includes guardrail, "mostly stable or separable"
    assert_includes guardrail, "rare, optional, or insufficiently weighted in expected play"
    assert_includes guardrail, "between scenes or encounters rather than the live encounter-time decision problem"
    assert_includes guardrail, "Encounter count, difficulty, spectacle, lethality, rules density"
    assert_includes guardrail, "mere presence of several tactical considerations does not establish score 5"
  end

  def test_adjacent_anchor_falsification_returns_to_reprioritization
    guardrail = normalized_guardrail

    assert_includes guardrail, "identify the live factors"
    assert_includes guardrail, "changes on one axis repeatedly alter priorities on others"
    assert_includes guardrail, "judge their substantive weight under Route A or Route B"
    assert_includes guardrail, "do not reject score 5 using any structural proxy forbidden above"
  end

  def test_production_guardrail_contains_no_benchmark_specific_leakage
    guardrail = AFScoring::TacticalComplexityMorphologyEquivalenceGuardrail::TEXT

    refute_match(
      /ADV-\d{4}|Witchlight Carnival|Storm King's Thunder|No Honour Among Thieves|Siege of Kalaman|Salvage Operation|The Final Enemy|Sunblight|Tockworth's Clockworks/,
      guardrail
    )
  end

  private

  def builder
    AFScoring::PromptBuilder.new(afao: @afao, assessment_spec: @assessment_spec)
  end

  def heading
    "# Tactical Complexity 4 ↔ 5 Direct Decision-Load Guardrail v0.4"
  end

  def normalized_guardrail
    AFScoring::TacticalComplexityMorphologyEquivalenceGuardrail::TEXT.gsub(/\s+/, " ")
  end
end
