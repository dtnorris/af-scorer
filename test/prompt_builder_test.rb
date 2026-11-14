# frozen_string_literal: true
require_relative "test_helper"
require "digest"

class PromptBuilderTest < Minitest::Test
  FakeAFAO = Struct.new(:version) do
    def rubric_for_group(group_name, target_id:, target_title:)
      "fixture rubric for #{group_name} / #{target_id} / #{target_title}"
    end

    def rubric_for_dimensions(dimensions, target_id:, target_title:)
      "fixture rubric for #{dimensions.join(', ')} / #{target_id} / #{target_title}"
    end
  end

  FakeAssessmentSpec = Struct.new(:prompt_text)
  AdventureFixture = Struct.new(:id, :title, :source_book, :publisher, :start_page, :end_page, keyword_init: true)
  ExtractionFixture = Struct.new(:text, :scope, :source_file, keyword_init: true)

  EXPECTED_GUARDRAIL = <<~TEXT.freeze
    # Combat Emphasis Application Guardrail

    When assessing Combat Emphasis, evaluate the role of combat across the expected
    substantive table play of the entire canonical adventure.

    Do not infer Combat Emphasis mechanically from encounter count, hostile-creature
    density, the presence of multiple combat-ready locations, the violence of the
    premise, encounter difficulty, or the importance of particular fights. These
    features may be evidence, but none is sufficient by itself to establish a high
    Combat Emphasis score.

    Weight optional, bypassable, negotiable, avoidable, and path-dependent combats
    according to their expected presence in substantially-as-published play. A
    supported combat-forward route does not by itself establish the Combat Emphasis
    of ordinary expected play.

    For the 1 ↔ 2 boundary:
    - Score 1 when combat may recur, matter, and carry consequences but remains
      structurally substitutable as a mode of canonical progression: the adventure
      supports its substantive progression through other modes without active hostile
      opposition becoming a materially embedded part of ordinary completion.
    - Score 2 when combat remains clearly secondary but active hostile opposition is
      structurally embedded as a genuine mode of canonical progression: ordinary
      completion includes materially consequential hostile resistance that must be
      overcome, survived, escaped, driven off, or otherwise resolved rather than being
      systematically replaceable by authored noncombat alternatives.
    - When distinguishing score 1 from score 2, do not treat recurrence,
      consequence, likelihood, rarity, concentration, or the presence or absence of
      repeated mandatory fights as sufficient evidence in either direction. Assess
      whether active hostile opposition remains structurally substitutable across
      ordinary canonical progression or is instead embedded as a genuine secondary
      mode of that progression.
    - Score 1 remains appropriate when combat can recur or become consequential but
      authored noncombat alternatives systematically preserve substantive canonical
      progression without active hostile opposition becoming materially embedded in
      ordinary completion. Recurring hostile creatures, a supported fight-through
      route, or combat that is likely to occur somewhere in ordinary play do not by
      themselves establish score 2.
    - Score 2 remains appropriate when active hostile opposition is structurally
      embedded in ordinary canonical progression even if combat is infrequent,
      concentrated, or occupies a small share of expected play. Score 2 does not
      require combat throughout most of the adventure, a large share of table time,
      repeated mandatory battles, or killing opponents. Do not use the presence of a
      single mandatory fight as a standalone test for score 2.

    For the 2 ↔ 3 boundary:
    - Score 2 when combat occurs and matters but remains clearly secondary across the
      canonical adventure.
    - Score 3 when combat functions as a substantial recurring component across
      ordinary canonical play alongside comparably important noncombat modes.
    - Consequential or repeated combat does not by itself establish score 3 when it
      is concentrated, strongly path-dependent, or largely confined to a phase or
      climax.
    - When combat is materially concentrated within a phase, do not treat that
      concentration as sufficient evidence either for score 2 or against score 3.
      Assess the structural role of the combat-bearing phase in ordinary canonical
      progression: whether it is itself a substantial operational body of that
      progression, and whether active hostile opposition repeatedly carries or gates
      progress through that body.
    - Score 3 can be supported despite geographic or narrative concentration when
      the combat-bearing phase is itself a substantial operational body of ordinary
      canonical progression and active hostile opposition repeatedly functions as
      progress-bearing play through it. The phase being merely decisive, central, or
      combat-heavy is not sufficient.
    - Score 2 remains appropriate when repeated hostile play principally occupies a
      bounded, route-dependent, terminal, or otherwise secondary resolution layer
      within progression substantially carried elsewhere by other modes. Do not
      assign score 2 merely because most combat occurs within one identifiable phase.
    - Do not accumulate mutually exclusive combat paths, endings, or encounter
      branches as though they all occur in one ordinary playthrough. Weight them
      according to their expected presence in substantially-as-published play.

    For the 3 ↔ 4 boundary:
    - Score 3 when combat is a substantial recurring component but comparably
      important noncombat modes also carry meaningful portions of progression.
    - Score 4 only when combat is genuinely one of the adventure's dominant modes
      across the canonical unit and regularly drives progress.
    - Several mandatory combats, a combat-heavy act or dungeon, or an important
      combat climax do not by themselves establish score 4 if combat remains
      concentrated or shares progression with comparably structural noncombat play.

    For the 4 ↔ 5 boundary:
    - Score 4 when combat is highly prominent and regularly progress-bearing but
      major canonical progression is also substantially organized by noncombat
      structures that carry progression independently of combat.
    - Score 5 when fighting or overcoming combat opposition is itself a
      fundamental organizing structure of expected progression across the canonical
      adventure.
    - When distinguishing score 4 from score 5, do not treat the mere presence of
      substantial noncombat activity as sufficient evidence for score 4, and do not
      require combat to be the sole or exclusive organizer of progression for score
      5. Assess whether the cited noncombat structures independently carry major
      canonical progression or instead principally operate within, connect, locate,
      modify, intensify, or resolve progression fundamentally organized around
      overcoming combat opposition.
    - Score 4 remains appropriate when major noncombat structures genuinely carry
      progression independently of combat rather than principally serving an
      encounter-organized progression. Their significance must be structural, not
      merely the presence of exploration, traversal, environmental hazards, mission
      objectives, logistics, investigation, social interaction, or escape play.
    - Score 5 remains appropriate when fighting or overcoming combat opposition is a
      fundamental organizing structure of expected progression even though
      significant noncombat play also occurs. "Fundamentally organized around
      combat" does not mean "organized exclusively around combat." Score 5 does not
      require combat in every scene, every hostile encounter to be resolved by
      fighting, or the absence of significant noncombat play.
    - Optional, bypassable, negotiable, or avoidable encounters do not by
      themselves prevent score 5 when the expected progression of the canonical
      adventure remains fundamentally organized around overcoming combat
      opposition.
    - The fact that removing most combat would substantially change the adventure
      is supporting evidence for score 5, not a sufficient standalone test.
      Important combats can be indispensable to an adventure without combat being
      its fundamental organizing mode.

    Adjacent-anchor falsification for Combat Emphasis must be structural:
    - When distinguishing score 1 from score 2, explicitly test both adjacent
      interpretations before assigning either score. Determine whether active hostile
      opposition remains structurally substitutable across ordinary canonical
      progression or is instead embedded as a genuine secondary mode of that
      progression. To assign 1, explain how authored noncombat alternatives
      systematically preserve substantive progression without hostile opposition
      becoming materially embedded in ordinary completion. To assign 2, explain why
      that substitutability fails and how hostile resistance is structurally embedded
      even if combat is infrequent or concentrated. Recurrence, consequence,
      frequency, rarity, or a single mandatory fight must not resolve the boundary in
      either direction.
    - When distinguishing score 2 from score 3, explicitly test both adjacent
      interpretations before assigning either score. If combat is materially
      concentrated within a phase, determine whether that phase is itself a
      substantial operational body of ordinary canonical progression and whether
      active hostile opposition repeatedly carries or gates progress through it.
      To assign 3, explain why those conditions make combat a substantial recurring
      component rather than merely consequential concentrated play. To assign 2,
      explain why they are not satisfied and why the hostile play instead remains
      principally a bounded, route-dependent, terminal, or otherwise secondary
      resolution layer. Phase concentration alone must not resolve the boundary in
      either direction.
    - Before assigning 4, identify why the adventure exceeds 3 rather than merely
      containing substantial recurring combat alongside comparably important
      noncombat play.
    - When distinguishing score 4 from score 5, explicitly test both adjacent
      interpretations before assigning either score. Determine whether substantial
      noncombat structures independently carry major canonical progression or
      principally operate within, connect, locate, modify, intensify, or resolve
      progression fundamentally organized around overcoming combat opposition. To
      assign 4, identify the major independently progress-bearing noncombat
      structure rather than relying on the mere presence of significant noncombat
      activity. To assign 5, explain why the cited noncombat activity does not supply
      a coequal independent progression structure and why overcoming combat
      opposition remains a fundamental organizer. Neither "combat is not the sole
      organizer" nor "significant noncombat play exists" may resolve the boundary in
      either direction.


    Do not presume that a lower Combat Emphasis score is preferable. Assign 4 or 5
    whenever the whole-adventure evidence satisfies those anchors.
  TEXT

  def setup
    @afao = FakeAFAO.new("1.0")
    @assessment_spec = FakeAssessmentSpec.new("fixture assessment rules")
    @adventure = AdventureFixture.new(
      id: "ADV-0001", title: "Fixture Adventure", source_book: "Fixture Book",
      publisher: "Fixture Publisher", start_page: 1, end_page: 2
    )
    @extraction = ExtractionFixture.new(
      text: "<!-- PAGE: 1 -->\nfixture source",
      scope: "canonical_page_slice",
      source_file: "/tmp/fixture.md"
    )
  end

  def test_default_play_mix_prompt_contains_production_combat_guardrail
    prompt = builder.build(group_name: "play_mix", adventure: @adventure, source_extraction: @extraction)

    assert_includes prompt.input, AFScoring::PromptBuilder::COMBAT_GUARDRAIL_V0_7_1
    assert_equal 1, prompt.input.scan("# Combat Emphasis Application Guardrail").length
    assert_equal 1, prompt.input.scan("# Combat-Mode Accounting Clarification").length
  end

  def test_v0_7_calibration_control_remains_frozen
    assert_equal EXPECTED_GUARDRAIL, AFScoring::PromptBuilder::EXPERIMENTAL_COMBAT_GUARDRAIL_V0_7
    assert_equal "e7dee31726cdf74ed0ffc4e63cccfe489beedfd1e0cfb631c1a7f9b5becbb22b",
      Digest::SHA256.hexdigest(AFScoring::PromptBuilder::EXPERIMENTAL_COMBAT_GUARDRAIL_V0_7)
  end

  def test_production_combat_prompt_appends_v0_7_1_combat_mode_accounting_clarification
    prompt = builder.build(
      group_name: "play_mix",
      dimensions: ["Combat Emphasis"],
      adventure: @adventure,
      source_extraction: @extraction
    )

    assert AFScoring::PromptBuilder::COMBAT_GUARDRAIL_V0_7_1.start_with?(
      AFScoring::PromptBuilder::EXPERIMENTAL_COMBAT_GUARDRAIL_V0_7
    )
    assert_includes prompt.input, "# Combat-Mode Accounting Clarification"
    assert_includes prompt.input,
      'Do not use "hostile opposition must be resolved somehow" as a proxy for combat.'
    assert_equal 1, prompt.input.scan("# Combat-Mode Accounting Clarification").length
  end

  def test_combat_guardrail_is_not_injected_into_unrelated_groups
    prompt = builder.build(group_name: "challenge_character", adventure: @adventure, source_extraction: @extraction)

    refute_includes prompt.input, "# Combat Emphasis Application Guardrail"
  end

  def test_single_dimension_prompt_requests_only_that_dimension
    prompt = builder.build(
      group_name: "play_mix",
      dimensions: ["Combat Emphasis"],
      adventure: @adventure,
      source_extraction: @extraction
    )

    assert_includes prompt.input, "Scoring dimension: Combat Emphasis"
    assert_includes prompt.input, "Assess only the required dimension/value in this focused pass."
    refute_includes prompt.input, "Required dimensions/values: Combat Emphasis; Exploration Emphasis"
  end

  def test_single_combat_dimension_receives_production_guardrail
    prompt = builder.build(
      group_name: "play_mix",
      dimensions: ["Combat Emphasis"],
      adventure: @adventure,
      source_extraction: @extraction
    )

    assert_includes prompt.input, AFScoring::PromptBuilder::COMBAT_GUARDRAIL_V0_7_1
  end

  def test_default_play_mix_prompt_contains_investigation_guardrail_once
    prompt = builder.build(
      group_name: "play_mix",
      adventure: @adventure,
      source_extraction: @extraction
    )

    assert_includes prompt.input, AFScoring::PromptBuilder::INVESTIGATION_EMPHASIS_GUARDRAIL_V0_1
    assert_equal 1, prompt.input.scan("# Investigation Emphasis Application Guardrail v0.1").length
  end

  def test_single_investigation_dimension_receives_application_guardrail_once
    prompt = builder.build(
      group_name: "play_mix",
      dimensions: ["Investigation Emphasis"],
      adventure: @adventure,
      source_extraction: @extraction
    )

    assert_includes prompt.input, AFScoring::PromptBuilder::INVESTIGATION_EMPHASIS_GUARDRAIL_V0_1
    assert_equal 1, prompt.input.scan("# Investigation Emphasis Application Guardrail v0.1").length
    assert_includes prompt.input,
      "Investigation does not require ambiguous evidence, competing hypotheses"
    assert_includes prompt.input,
      "aggregate qualifying inquiry across the whole canonical"
    assert_includes prompt.input,
      "does not automatically dilute Investigation when that downstream"
    assert_includes prompt.input,
      "Determining how to traverse a route, operate or bypass a"
  end

  def test_investigation_guardrail_is_not_injected_into_other_focused_play_mix_dimensions
    prompt = builder.build(
      group_name: "play_mix",
      dimensions: ["Combat Emphasis"],
      adventure: @adventure,
      source_extraction: @extraction
    )

    refute_includes prompt.input, "# Investigation Emphasis Application Guardrail v0.1"
  end

  def test_investigation_guardrail_is_not_injected_into_unrelated_groups
    prompt = builder.build(
      group_name: "challenge_character",
      adventure: @adventure,
      source_extraction: @extraction
    )

    refute_includes prompt.input, "# Investigation Emphasis Application Guardrail v0.1"
  end

  def test_v0_3_investigation_guardrail_extends_v0_1_without_rewriting_it
    guardrail = AFScoring::PromptBuilder::INVESTIGATION_EMPHASIS_GUARDRAIL_V0_3

    assert guardrail.start_with?(
      AFScoring::PromptBuilder::INVESTIGATION_EMPHASIS_GUARDRAIL_V0_1
    )
    assert_includes guardrail,
      "# Investigation Emphasis Upper-Anchor Decision Isolation v0.3"
    assert_equal 1,
      guardrail.scan("# Investigation Emphasis Upper-Anchor Decision Isolation v0.3").length
    assert_includes guardrail, "Evaluate 3 ↔ 4 on its own terms"
    assert_includes guardrail, "Absence of a score-5 property is not evidence for score 3"
    assert_includes guardrail, "# Independent-Spine Audit — 4 ↔ 5"
    assert_includes guardrail, "Judge the lineage between major phases"
    assert_includes guardrail, "final discovered objective may resolve through confrontation"
  end

  def test_single_investigation_dimension_receives_v0_3_upper_anchor_audit_once
    prompt = builder.build(
      group_name: "play_mix",
      dimensions: ["Investigation Emphasis"],
      adventure: @adventure,
      source_extraction: @extraction
    )

    assert_includes prompt.input, AFScoring::PromptBuilder::INVESTIGATION_EMPHASIS_GUARDRAIL_V0_3
    assert_equal 1,
      prompt.input.scan("# Investigation Emphasis Application Guardrail v0.1").length
    assert_equal 1,
      prompt.input.scan("# Investigation Emphasis Upper-Anchor Decision Isolation v0.3").length
  end

  def test_default_play_mix_prompt_receives_v0_3_upper_anchor_audit_once
    prompt = builder.build(
      group_name: "play_mix",
      adventure: @adventure,
      source_extraction: @extraction
    )

    assert_includes prompt.input, AFScoring::PromptBuilder::INVESTIGATION_EMPHASIS_GUARDRAIL_V0_3
    assert_equal 1,
      prompt.input.scan("# Investigation Emphasis Upper-Anchor Decision Isolation v0.3").length
  end

  def test_single_puzzle_problem_solving_dimension_receives_v0_1_guardrail_once
    prompt = builder.build(
      group_name: "play_mix",
      dimensions: ["Puzzle / Problem-Solving Emphasis"],
      adventure: @adventure,
      source_extraction: @extraction
    )

    assert_includes prompt.input,
      AFScoring::PromptBuilder::PUZZLE_PROBLEM_SOLVING_EMPHASIS_GUARDRAIL_V0_1
    assert_equal 1,
      prompt.input.scan("# Puzzle / Problem-Solving Emphasis 1 ↔ 2 Boundary Guardrail v0.1").length
  end

  def test_default_play_mix_prompt_contains_puzzle_problem_solving_guardrail_once
    prompt = builder.build(
      group_name: "play_mix",
      adventure: @adventure,
      source_extraction: @extraction
    )

    assert_includes prompt.input,
      AFScoring::PromptBuilder::PUZZLE_PROBLEM_SOLVING_EMPHASIS_GUARDRAIL_V0_1
    assert_equal 1,
      prompt.input.scan("# Puzzle / Problem-Solving Emphasis 1 ↔ 2 Boundary Guardrail v0.1").length
  end

  def test_puzzle_problem_solving_v0_1_encodes_qualifying_unit_and_counter_pressure_without_benchmarks
    guardrail =
      AFScoring::PromptBuilder::PUZZLE_PROBLEM_SOLVING_EMPHASIS_GUARDRAIL_V0_1

    assert_includes guardrail, "# Qualifying-Unit Audit"
    assert_match(/identify at least one meaningfully developed\s+player-facing how-problem/, guardrail)
    assert_match(/Do not reach score 2 by adding together several situations that would each fail\s+this test on their own/, guardrail)
    assert_includes guardrail, "ordinary route selection"
    assert_includes guardrail, "generic opportunities to improvise cleverly around an encounter"
    assert_includes guardrail, "# Low-Anchor Counter-Pressure"
    assert_match(/Do not overcorrect by requiring recurrence, multiple puzzles, formal riddles,\s+difficult deduction, or a large share of total play/, guardrail)
    assert_match(/resource-allocation problem, mechanism problem, or open-ended obstacle/, guardrail)
    assert_match(/Multiple non-qualifying candidates do not become a\s+qualifying unit merely by accumulation/, guardrail)
    refute_match(/ADV-\d{4}/, guardrail)
    refute_match(
      /Expedition to the Barrier Peaks|Lost Mine of Phandelver|No Honour Among Thieves|Call of the Wild/,
      guardrail
    )
  end

  def test_puzzle_problem_solving_guardrail_is_not_injected_into_other_focused_play_mix_dimensions
    prompt = builder.build(
      group_name: "play_mix",
      dimensions: ["Exploration Emphasis"],
      adventure: @adventure,
      source_extraction: @extraction
    )

    refute_includes prompt.input,
      "# Puzzle / Problem-Solving Emphasis 1 ↔ 2 Boundary Guardrail v0.1"
  end

  def test_single_social_interaction_dimension_receives_boundary_guardrail_once
    prompt = builder.build(
      group_name: "play_mix",
      dimensions: ["Social Interaction Emphasis"],
      adventure: @adventure,
      source_extraction: @extraction
    )

    assert_includes prompt.input,
      AFScoring::PromptBuilder::SOCIAL_INTERACTION_EMPHASIS_GUARDRAIL_V0_2
    assert_equal 1,
      prompt.input.scan("# Social Interaction Emphasis Boundary Application Guardrail v0.1").length
    assert_equal 1,
      prompt.input.scan("# Social Interaction Emphasis 3 ↔ 4 Dominance Preservation v0.2").length
    assert_includes prompt.input, '"Alongside comparably important non-social play"'
    assert_includes prompt.input,
      '"Fundamentally organized around" does not mean "organized only"'
    assert_includes prompt.input, '"other modes combined are larger"'
    assert_includes prompt.input, "significant non-social play"
  end

  def test_default_play_mix_prompt_contains_social_interaction_guardrail_once
    prompt = builder.build(
      group_name: "play_mix",
      adventure: @adventure,
      source_extraction: @extraction
    )

    assert_includes prompt.input,
      AFScoring::PromptBuilder::SOCIAL_INTERACTION_EMPHASIS_GUARDRAIL_V0_2
    assert_equal 1,
      prompt.input.scan("# Social Interaction Emphasis Boundary Application Guardrail v0.1").length
    assert_equal 1,
      prompt.input.scan("# Social Interaction Emphasis 3 ↔ 4 Dominance Preservation v0.2").length
  end

  def test_social_interaction_v0_2_extends_v0_1_with_3_4_preservation
    v0_1 = AFScoring::PromptBuilder::SOCIAL_INTERACTION_EMPHASIS_GUARDRAIL_V0_1
    v0_2 = AFScoring::PromptBuilder::SOCIAL_INTERACTION_EMPHASIS_GUARDRAIL_V0_2

    assert v0_2.start_with?(v0_1)
    assert_includes v0_2,
      "# Social Interaction Emphasis 3 ↔ 4 Dominance Preservation v0.2"
    assert_includes v0_2,
      "Do not require Social Interaction to independently carry major canonical plot"
    assert_match(
      /Repeated major\s+interaction-centered events or phases can support score 4/,
      v0_2
    )
    assert_includes v0_2,
      "principally frames, directs, or supplements a separately dominant body"
    assert_includes v0_2,
      "Do not import the 4 ↔ 5 tests concerning fundamental organizing structure"
    refute_match(/ADV-\d{4}/, v0_2)
    refute_match(
      /Magister|Barrier Peaks|Witchlight|Lost Mine|Danger at Dunwater|House of Lament/,
      v0_2
    )
  end

  def test_social_interaction_v0_1_control_remains_3_4_neutral
    v0_1 = AFScoring::PromptBuilder::SOCIAL_INTERACTION_EMPHASIS_GUARDRAIL_V0_1

    refute_includes v0_1, "# 3 ↔ 4 Boundary"
    refute_includes v0_1,
      "# Social Interaction Emphasis 3 ↔ 4 Dominance Preservation v0.2"
  end

  def test_social_interaction_guardrail_is_boundary_specific_without_benchmark_leakage
    guardrail =
      AFScoring::PromptBuilder::SOCIAL_INTERACTION_EMPHASIS_GUARDRAIL_V0_1

    assert_includes guardrail, "# 2 ↔ 3 Boundary"
    assert_includes guardrail, "# 4 ↔ 5 Boundary"
    refute_includes guardrail, "# 1 ↔ 2 Boundary"
    refute_includes guardrail, "# 3 ↔ 4 Boundary"
    refute_match(/ADV-\d{4}/, guardrail)
    refute_match(
      /Barrier Peaks|Witchlight|Lost Mine|Danger at Dunwater|House of Lament/,
      guardrail
    )
  end

  def test_social_interaction_guardrail_is_not_injected_into_other_focused_dimensions
    prompt = builder.build(
      group_name: "play_mix",
      dimensions: ["Exploration Emphasis"],
      adventure: @adventure,
      source_extraction: @extraction
    )

    refute_includes prompt.input,
      "# Social Interaction Emphasis Boundary Application Guardrail v0.1"
    refute_includes prompt.input,
      "# Social Interaction Emphasis 3 ↔ 4 Dominance Preservation v0.2"
  end

  def test_focused_investigation_and_social_prompts_do_not_cross_inject_guardrails
    investigation_prompt = builder.build(
      group_name: "play_mix",
      dimensions: ["Investigation Emphasis"],
      adventure: @adventure,
      source_extraction: @extraction
    )
    social_prompt = builder.build(
      group_name: "play_mix",
      dimensions: ["Social Interaction Emphasis"],
      adventure: @adventure,
      source_extraction: @extraction
    )

    refute_includes investigation_prompt.input,
      "# Social Interaction Emphasis Boundary Application Guardrail v0.1"
    refute_includes social_prompt.input,
      "# Investigation Emphasis Application Guardrail v0.1"
  end

  def test_single_fantastic_weirdness_dimension_receives_application_guardrail_once
    prompt = builder.build(
      group_name: "experience_tone",
      dimensions: ["Fantastic Weirdness"],
      adventure: @adventure,
      source_extraction: @extraction
    )

    assert_includes prompt.input, AFScoring::PromptBuilder::FANTASTIC_WEIRDNESS_GUARDRAIL_V0_2
    assert_equal 1, prompt.input.scan("# Fantastic Weirdness Application Guardrail").length
    assert_equal 1, prompt.input.scan("# Fantastic Weirdness 4 ↔ 5 Counter-Guardrail").length
    assert_includes prompt.input,
      "Apply the AFAO replacement test to the adventure's substantive playable"
    assert_includes prompt.input,
      "This guardrail clarifies application of the frozen AFAO rubric"
    assert_includes prompt.input,
      "A bizarre, surreal, or convention-breaking site, setting, or fictional"
    assert_includes prompt.input,
      "For score 5, the weirdness must materially constitute those operative"
  end

  def test_v0_2_fantastic_weirdness_guardrail_extends_v0_1_without_rewriting_it
    assert AFScoring::PromptBuilder::FANTASTIC_WEIRDNESS_GUARDRAIL_V0_2.start_with?(
      AFScoring::PromptBuilder::FANTASTIC_WEIRDNESS_GUARDRAIL_V0_1
    )
    assert_includes AFScoring::PromptBuilder::FANTASTIC_WEIRDNESS_GUARDRAIL_V0_2,
      "# Fantastic Weirdness 4 ↔ 5 Counter-Guardrail"
    assert_includes AFScoring::PromptBuilder::FANTASTIC_WEIRDNESS_GUARDRAIL_V0_2,
      "Score 4 remains appropriate when conventionalizing the weird material"
  end

  def test_default_experience_tone_prompt_contains_fantastic_weirdness_guardrail_once
    prompt = builder.build(
      group_name: "experience_tone",
      adventure: @adventure,
      source_extraction: @extraction
    )

    assert_includes prompt.input, AFScoring::PromptBuilder::FANTASTIC_WEIRDNESS_GUARDRAIL_V0_2
    assert_equal 1, prompt.input.scan("# Fantastic Weirdness Application Guardrail").length
    assert_equal 1, prompt.input.scan("# Fantastic Weirdness 4 ↔ 5 Counter-Guardrail").length
  end

  def test_fantastic_weirdness_guardrail_is_not_injected_into_other_focused_dimensions
    prompt = builder.build(
      group_name: "experience_tone",
      dimensions: ["Seriousness"],
      adventure: @adventure,
      source_extraction: @extraction
    )

    refute_includes prompt.input, "# Fantastic Weirdness Application Guardrail"
    refute_includes prompt.input, "# Fantastic Weirdness 4 ↔ 5 Counter-Guardrail"
  end

  def test_fantastic_weirdness_guardrail_is_not_injected_into_unrelated_groups
    prompt = builder.build(
      group_name: "challenge_character",
      adventure: @adventure,
      source_extraction: @extraction
    )

    refute_includes prompt.input, "# Fantastic Weirdness Application Guardrail"
    refute_includes prompt.input, "# Fantastic Weirdness 4 ↔ 5 Counter-Guardrail"
  end

  def test_single_seriousness_dimension_uses_reset_baseline_without_production_guardrails
    prompt = builder.build(
      group_name: "experience_tone",
      dimensions: ["Seriousness"],
      adventure: @adventure,
      source_extraction: @extraction
    )

    refute_includes prompt.input, AFScoring::PromptBuilder::SERIOUSNESS_GUARDRAIL_V0_2
    assert_equal 0, prompt.input.scan("# Seriousness Adversarial-Play Guardrail").length
    assert_equal 0, prompt.input.scan("# Seriousness Tonal-Hierarchy / Proxy-Weighting Guardrail").length
  end

  def test_default_experience_tone_prompt_uses_seriousness_reset_baseline
    prompt = builder.build(
      group_name: "experience_tone",
      adventure: @adventure,
      source_extraction: @extraction
    )

    refute_includes prompt.input, AFScoring::PromptBuilder::SERIOUSNESS_GUARDRAIL_V0_2
    assert_equal 0, prompt.input.scan("# Seriousness Adversarial-Play Guardrail").length
    assert_equal 0, prompt.input.scan("# Seriousness Tonal-Hierarchy / Proxy-Weighting Guardrail").length
  end

  def test_v0_2_seriousness_guardrail_extends_v0_1_without_rewriting_it
    assert AFScoring::PromptBuilder::SERIOUSNESS_GUARDRAIL_V0_2.start_with?(
      AFScoring::PromptBuilder::SERIOUSNESS_ADVERSARIAL_PLAY_GUARDRAIL_V0_1
    )
    assert_includes AFScoring::PromptBuilder::SERIOUSNESS_GUARDRAIL_V0_2,
      "# Seriousness Tonal-Hierarchy / Proxy-Weighting Guardrail"
    assert_includes AFScoring::PromptBuilder::SERIOUSNESS_GUARDRAIL_V0_2,
      "Score 4 requires a clear tonal hierarchy"
    assert_includes AFScoring::PromptBuilder::SERIOUSNESS_GUARDRAIL_V0_2,
      "Score 3 is appropriate when recurring earnest/dramatic material"
  end

  def test_seriousness_v0_2_prompt_contains_both_boundary_proxy_corrections
    text = AFScoring::PromptBuilder::SERIOUSNESS_GUARDRAIL_V0_2

    assert_includes text, "strict deadline"
    assert_includes text, "do not by themselves establish that the"
    assert_includes text, "fairy-tale"
    assert_includes text, "Do not reduce substantive earnest/dramatic material to an"
  end

  def test_seriousness_guardrail_is_not_injected_into_other_focused_dimensions
    prompt = builder.build(
      group_name: "experience_tone",
      dimensions: ["Fantastic Weirdness"],
      adventure: @adventure,
      source_extraction: @extraction
    )

    refute_includes prompt.input, "# Seriousness Adversarial-Play Guardrail"
    refute_includes prompt.input, "# Seriousness Tonal-Hierarchy / Proxy-Weighting Guardrail"
  end

  def test_seriousness_guardrail_is_not_injected_into_unrelated_groups
    prompt = builder.build(
      group_name: "challenge_character",
      adventure: @adventure,
      source_extraction: @extraction
    )

    refute_includes prompt.input, "# Seriousness Adversarial-Play Guardrail"
    refute_includes prompt.input, "# Seriousness Tonal-Hierarchy / Proxy-Weighting Guardrail"
  end


  def test_single_darkness_horror_dimension_receives_lower_boundary_guardrail_once
    prompt = builder.build(
      group_name: "experience_tone",
      dimensions: ["Darkness / Horror Intensity"],
      adventure: @adventure,
      source_extraction: @extraction
    )

    assert_includes prompt.input,
      AFScoring::PromptBuilder::DARKNESS_HORROR_INTENSITY_GUARDRAIL_V0_1
    assert_equal 1,
      prompt.input.scan("# Darkness / Horror Intensity Lower-Boundary Application Guardrail v0.1").length
    assert_includes prompt.input,
      "not promote 1 to 2 merely because grim material is consequential"
    assert_includes prompt.input,
      "Do not require score 3 darkness to become the dominant, primary, coequal"
    assert_includes prompt.input,
      "Evaluate Path Sensitive independently of the integer score."
  end

  def test_default_experience_tone_prompt_contains_darkness_horror_guardrail_once
    prompt = builder.build(
      group_name: "experience_tone",
      adventure: @adventure,
      source_extraction: @extraction
    )

    assert_includes prompt.input,
      AFScoring::PromptBuilder::DARKNESS_HORROR_INTENSITY_GUARDRAIL_V0_1
    assert_equal 1,
      prompt.input.scan("# Darkness / Horror Intensity Lower-Boundary Application Guardrail v0.1").length
  end

  def test_darkness_horror_guardrail_targets_score_2_attractor_without_benchmark_leakage
    guardrail = AFScoring::PromptBuilder::DARKNESS_HORROR_INTENSITY_GUARDRAIL_V0_1

    assert_includes guardrail, "# 1 ↔ 2 Boundary"
    assert_includes guardrail, "# 2 ↔ 3 Boundary"
    assert_includes guardrail, "meaningful player-facing dark experiential strand"
    assert_includes guardrail, "substantial recurring component"
    assert_includes guardrail, "danger, stakes, lore, possible consequences, or genre dressing"
    assert_includes guardrail, "dominant, primary, coequal"
    refute_includes guardrail, "# 3 ↔ 4 Boundary"
    refute_includes guardrail, "# 4 ↔ 5 Boundary"
    refute_match(/No Honour Among Thieves|Lost Mine of Phandelver/, guardrail)
  end

  def test_darkness_horror_guardrail_is_not_injected_into_other_focused_dimensions
    prompt = builder.build(
      group_name: "experience_tone",
      dimensions: ["Seriousness"],
      adventure: @adventure,
      source_extraction: @extraction
    )

    refute_includes prompt.input,
      "# Darkness / Horror Intensity Lower-Boundary Application Guardrail v0.1"
  end

  def test_darkness_horror_guardrail_is_not_injected_into_unrelated_groups
    prompt = builder.build(
      group_name: "challenge_character",
      adventure: @adventure,
      source_extraction: @extraction
    )

    refute_includes prompt.input,
      "# Darkness / Horror Intensity Lower-Boundary Application Guardrail v0.1"
  end

  def test_single_consequential_player_agency_dimension_receives_v0_1_guardrail_once
    prompt = builder.build(
      group_name: "adventure_structure",
      dimensions: ["Consequential Player Agency"],
      adventure: @adventure,
      source_extraction: @extraction
    )

    assert_includes prompt.input, AFScoring::PromptBuilder::CONSEQUENTIAL_PLAYER_AGENCY_GUARDRAIL_V0_1
    assert_equal 1, prompt.input.scan("# Consequential Player Agency 1 ↔ 2 Application Guardrail").length
    assert_includes prompt.input,
      "distinguish an authored player-caused adventure-state consequence from the"
    assert_includes prompt.input,
      "do not convert puzzle correctness, successful checks, trap"
    assert_includes prompt.input,
      "received as the payoff for successfully resolving a challenge does not by"
    assert_includes prompt.input,
      "One genuinely qualifying localized consequence is sufficient."
  end

  def test_default_adventure_structure_prompt_contains_cpa_v0_1_guardrail_once
    prompt = builder.build(
      group_name: "adventure_structure",
      adventure: @adventure,
      source_extraction: @extraction
    )

    assert_includes prompt.input, AFScoring::PromptBuilder::CONSEQUENTIAL_PLAYER_AGENCY_GUARDRAIL_V0_1
    assert_equal 1, prompt.input.scan("# Consequential Player Agency 1 ↔ 2 Application Guardrail").length
  end

  def test_cpa_v0_1_guardrail_preserves_score_2_positive_control_language
    text = AFScoring::PromptBuilder::CONSEQUENTIAL_PLAYER_AGENCY_GUARDRAIL_V0_1

    assert_includes text, "a player decision establishing or changing a continuing NPC or faction"
    assert_includes text, "accepting, rejecting, or altering an objective"
    assert_includes text, "Qualifying consequences may remain localized or optional and may"
    assert_includes text, "Do not require recurring consequences, broad branching, or a changed ending"
  end

  def test_cpa_v0_2_guardrail_extends_v0_1_with_major_outcome_clarification
    v0_1 = AFScoring::PromptBuilder::CONSEQUENTIAL_PLAYER_AGENCY_GUARDRAIL_V0_1
    v0_2 = AFScoring::PromptBuilder::CONSEQUENTIAL_PLAYER_AGENCY_GUARDRAIL_V0_2

    assert v0_2.start_with?(v0_1)
    assert_includes v0_2, "# Consequential Player Agency 2 ↔ 3 Major-Outcome Clarification"
    assert_includes v0_2, "does not become score 3 merely"
    assert_includes v0_2, "assess the magnitude of the authored adventure outcome"
    assert_includes v0_2, "major-outcome clause requires a substantively authored alternate outcome"
  end

  def test_single_cpa_prompt_receives_v0_2_major_outcome_clarification_once
    prompt = builder.build(
      group_name: "adventure_structure",
      dimensions: ["Consequential Player Agency"],
      adventure: @adventure,
      source_extraction: @extraction
    )

    assert_includes prompt.input, AFScoring::PromptBuilder::CONSEQUENTIAL_PLAYER_AGENCY_GUARDRAIL_V0_2
    assert_equal 1, prompt.input.scan("# Consequential Player Agency 1 ↔ 2 Application Guardrail").length
    assert_equal 1, prompt.input.scan("# Consequential Player Agency 2 ↔ 3 Major-Outcome Clarification").length
  end

  def test_cpa_v0_3_guardrail_extends_v0_2_with_upper_boundary_clarification
    v0_2 = AFScoring::PromptBuilder::CONSEQUENTIAL_PLAYER_AGENCY_GUARDRAIL_V0_2
    v0_3 = AFScoring::PromptBuilder::CONSEQUENTIAL_PLAYER_AGENCY_GUARDRAIL_V0_3

    assert v0_3.start_with?(v0_2)
    assert_includes v0_3, "# Consequential Player Agency 3 ↔ 5 Structural Consequence Clarification"
    assert_includes v0_3, "Do not generalize macro reconvergence into a ceiling"
    assert_includes v0_3, "Score 4 can arise through either:"
    assert_includes v0_3, "one deeply integrated, repeatedly reactive relationship or state system"
    assert_includes v0_3, "Score 5 does not require multiple wholly different plotlines"
    assert_includes v0_3, "consulting accumulated player-caused history across multiple independent"
    assert_includes v0_3, "decision history a fundamental organizing feature"
  end

  def test_single_cpa_prompt_receives_v0_3_upper_boundary_clarification_once
    prompt = builder.build(
      group_name: "adventure_structure",
      dimensions: ["Consequential Player Agency"],
      adventure: @adventure,
      source_extraction: @extraction
    )

    assert_includes prompt.input, AFScoring::PromptBuilder::CONSEQUENTIAL_PLAYER_AGENCY_GUARDRAIL_V0_3
    assert_equal 1, prompt.input.scan("# Consequential Player Agency 1 ↔ 2 Application Guardrail").length
    assert_equal 1, prompt.input.scan("# Consequential Player Agency 2 ↔ 3 Major-Outcome Clarification").length
    assert_equal 1, prompt.input.scan("# Consequential Player Agency 3 ↔ 5 Structural Consequence Clarification").length
  end

  def test_default_adventure_structure_prompt_contains_cpa_v0_3_upper_boundary_clarification_once
    prompt = builder.build(
      group_name: "adventure_structure",
      adventure: @adventure,
      source_extraction: @extraction
    )

    assert_includes prompt.input, AFScoring::PromptBuilder::CONSEQUENTIAL_PLAYER_AGENCY_GUARDRAIL_V0_3
    assert_equal 1, prompt.input.scan("# Consequential Player Agency 3 ↔ 5 Structural Consequence Clarification").length
  end

  def test_cpa_guardrail_is_not_injected_into_other_focused_adventure_structure_dimensions
    prompt = builder.build(
      group_name: "adventure_structure",
      dimensions: ["Structural Openness"],
      adventure: @adventure,
      source_extraction: @extraction
    )

    refute_includes prompt.input, "# Consequential Player Agency 1 ↔ 2 Application Guardrail"
  end

  def test_cpa_guardrail_is_not_injected_into_unrelated_groups
    prompt = builder.build(
      group_name: "challenge_character",
      adventure: @adventure,
      source_extraction: @extraction
    )

    refute_includes prompt.input, "# Consequential Player Agency 1 ↔ 2 Application Guardrail"
  end

  def test_single_gm_improvisation_dimension_receives_v0_1_guardrail_once
    prompt = builder.build(
      group_name: "gm_demands",
      dimensions: ["GM Improvisation Demand"],
      adventure: @adventure,
      source_extraction: @extraction
    )

    assert_includes prompt.input, AFScoring::PromptBuilder::GM_IMPROVISATION_DEMAND_GUARDRAIL_V0_1
    assert_equal 1, prompt.input.scan("# GM Improvisation Demand 3 ↔ 5 Runtime-Synthesis Guardrail").length
    assert_includes prompt.input, "do not treat the amount, detail"
    assert_includes prompt.input, "actually specify the playable response"
    assert_includes prompt.input, "Do not hold an adventure at score 3 merely"
    assert_includes prompt.input, "Score 5 does not require the GM to invent the adventure"
    assert_includes prompt.input, "Do not award score 4 or 5 merely because an adventure is open-ended"
  end

  def test_default_gm_demands_prompt_contains_gm_improvisation_guardrail_once
    prompt = builder.build(
      group_name: "gm_demands",
      adventure: @adventure,
      source_extraction: @extraction
    )

    assert_includes prompt.input, AFScoring::PromptBuilder::GM_IMPROVISATION_DEMAND_GUARDRAIL_V0_1
    assert_equal 1, prompt.input.scan("# GM Improvisation Demand 3 ↔ 5 Runtime-Synthesis Guardrail").length
  end

  def test_gm_improvisation_guardrail_is_not_injected_into_prep_only_focused_pass
    prompt = builder.build(
      group_name: "gm_demands",
      dimensions: ["GM Preparation Burden"],
      adventure: @adventure,
      source_extraction: @extraction
    )

    refute_includes prompt.input, "# GM Improvisation Demand 3 ↔ 5 Runtime-Synthesis Guardrail"
  end

  def test_gm_improvisation_guardrail_is_not_injected_into_unrelated_groups
    prompt = builder.build(
      group_name: "adventure_structure",
      adventure: @adventure,
      source_extraction: @extraction
    )

    refute_includes prompt.input, "# GM Improvisation Demand 3 ↔ 5 Runtime-Synthesis Guardrail"
  end

  def test_single_gm_preparation_burden_dimension_receives_active_hybrid_once
    prompt = builder.build(
      group_name: "gm_demands",
      dimensions: ["GM Preparation Burden"],
      adventure: @adventure,
      source_extraction: @extraction
    )

    assert_includes prompt.input,
      AFScoring::PromptBuilder::GM_PREPARATION_BURDEN_GUARDRAIL_V0_6
    assert_equal 1,
      prompt.input.scan("# GM Preparation Burden Application Guardrail v0.1").length
    assert_equal 1, prompt.input.scan("# Localized-Read Rule — 1 ↔ 2").length
    assert_equal 1, prompt.input.scan("# Authored-Sequence Rule — 2 ↔ 3").length
    assert_equal 1,
      prompt.input.scan("# Organization-Is-Not-Prep-Reduction Rule — 3 ↔ 4 ↔ 5").length
    assert_equal 1,
      prompt.input.scan("# GM Preparation Burden 4 ↔ 5 Dependency-Fan-Out Procedure v0.6").length
    refute_includes prompt.input,
      "# Persistent Preparation Infrastructure Clarification — 4 ↔ 5"
    refute_includes prompt.input,
      "# Ordered Stages vs Persistent Preparation Infrastructure — 4 ↔ 5"
    refute_includes prompt.input, "wide active campaign-level field"
  end

  def test_default_gm_demands_prompt_contains_gm_preparation_guardrail_once
    prompt = builder.build(
      group_name: "gm_demands",
      adventure: @adventure,
      source_extraction: @extraction
    )

    assert_includes prompt.input,
      AFScoring::PromptBuilder::GM_PREPARATION_BURDEN_GUARDRAIL_V0_6
    assert_equal 1,
      prompt.input.scan("# GM Preparation Burden Application Guardrail v0.1").length
    assert_equal 1,
      prompt.input.scan("# GM Preparation Burden 4 ↔ 5 Dependency-Fan-Out Procedure v0.6").length
  end

  def test_gm_preparation_guardrail_encodes_three_calibrated_distinctions_without_benchmarks
    guardrail = AFScoring::PromptBuilder::GM_PREPARATION_BURDEN_GUARDRAIL_V0_1

    assert_match(/absorbing that\s+localized material is essentially the preparation/, guardrail)
    assert_includes guardrail, "distributed across an explicitly authored chain is not automatically an"
    assert_match(/Several\s+materially different upcoming alternatives can establish Moderate burden/, guardrail)
    assert_match(/they do not\s+erase the amount or dependency structure of the preparation itself/, guardrail)
    assert_includes guardrail, "Score 4 does not require extensive"
    assert_includes guardrail, "distinguish score 5 from score 4"
    refute_match(/Lake Monster|A Friend in Need|No Honour Among Thieves|House of Lament/, guardrail)
  end

  def test_gm_preparation_v0_2_extends_v0_1_with_boundary_counter_guardrails
    v0_1 = AFScoring::PromptBuilder::GM_PREPARATION_BURDEN_GUARDRAIL_V0_1
    v0_2 = AFScoring::PromptBuilder::GM_PREPARATION_BURDEN_GUARDRAIL_V0_2

    assert v0_2.start_with?(v0_1)
    assert_includes v0_2, "# GM Preparation Burden Boundary Counter-Guardrails v0.2"
    assert_includes v0_2, "# Compact Whole-Unit Read Clarification — 1 ↔ 2"
    assert_includes v0_2, "# Precision-Sensitive Bounded-Site Clarification — 3 ↔ 4"
    assert_includes v0_2, "# Sustained Campaign-Management Clarification — 4 ↔ 5"
  end

  def test_single_gm_preparation_prompt_receives_v0_2_counter_guardrails_once
    prompt = builder.build(
      group_name: "gm_demands",
      dimensions: ["GM Preparation Burden"],
      adventure: @adventure,
      source_extraction: @extraction
    )

    assert_includes prompt.input,
      AFScoring::PromptBuilder::GM_PREPARATION_BURDEN_GUARDRAIL_V0_6
    assert_equal 1,
      prompt.input.scan("# GM Preparation Burden Boundary Counter-Guardrails v0.2").length
    assert_equal 1,
      prompt.input.scan("# Compact Whole-Unit Read Clarification — 1 ↔ 2").length
    assert_equal 1,
      prompt.input.scan("# Precision-Sensitive Bounded-Site Clarification — 3 ↔ 4").length
    assert_equal 1,
      prompt.input.scan("# GM Preparation Burden 4 ↔ 5 Dependency-Fan-Out Procedure v0.6").length
    refute_includes prompt.input,
      "# Persistent Preparation Infrastructure Clarification — 4 ↔ 5"
    refute_includes prompt.input,
      "# Sustained Campaign-Management Clarification — 4 ↔ 5"
  end

  def test_gm_preparation_v0_2_preserves_bidirectional_boundary_pressure_without_benchmarks
    guardrail = AFScoring::PromptBuilder::GM_PREPARATION_BURDEN_GUARDRAIL_V0_2

    assert_match(/immediately relevant material may be\s+essentially the whole adventure/, guardrail)
    assert_match(/Calling the same pass a "deliberate whole-unit read," "encounter\s+review," or "careful review" does not by itself/, guardrail)
    assert_includes guardrail, "The fact that a GM cannot reliably read only the next room"
    assert_includes guardrail, "precision-sensitive procedures can make"
    assert_includes guardrail, "Several substantive alternatives can establish score 3"
    assert_match(/Score 5\s+does not require a bespoke tracking artifact/, guardrail)
    assert_match(/simultaneous mastery of every possible path/, guardrail)
    assert_includes guardrail, "The GM may still prepare only the selected and likely next material"
    assert_match(/Carrying a\s+compact tracker or a limited set of callbacks/, guardrail)
    refute_match(
      /Lake Monster|A Friend in Need|Tomb of Horrors|No Honour Among Thieves|Call of the Wild|Lost Mine of Phandelver|Expedition to the Barrier Peaks|House of Lament|The Wild Beyond the Witchlight|Storm King's Thunder/,
      guardrail
    )
  end

  def test_gm_preparation_v0_3_extends_v0_2_with_narrow_boundary_preservation
    v0_2 = AFScoring::PromptBuilder::GM_PREPARATION_BURDEN_GUARDRAIL_V0_2
    v0_3 = AFScoring::PromptBuilder::GM_PREPARATION_BURDEN_GUARDRAIL_V0_3

    assert v0_3.start_with?(v0_2)
    assert_equal 1,
      v0_3.scan("# GM Preparation Burden Boundary Preservation v0.3").length
    assert_includes v0_3, "# Pre-Selection Readiness — 2 ↔ 3"
    assert_includes v0_3, "# Cross-Cutting Bounded Structure — 3 ↔ 4"
    assert_includes v0_3, "# Ordered Stages vs Campaign Management — 4 ↔ 5"
  end

  def test_single_gm_preparation_prompt_receives_v0_6_hybrid_once
    prompt = builder.build(
      group_name: "gm_demands",
      dimensions: ["GM Preparation Burden"],
      adventure: @adventure,
      source_extraction: @extraction
    )

    assert_includes prompt.input,
      AFScoring::PromptBuilder::GM_PREPARATION_BURDEN_GUARDRAIL_V0_6
    assert_equal 1,
      prompt.input.scan("# GM Preparation Burden Boundary Preservation v0.3").length
    assert_equal 1,
      prompt.input.scan("# GM Preparation Burden 4 ↔ 5 Dependency-Fan-Out Procedure v0.6").length
    refute_includes prompt.input,
      "# Persistent Preparation Infrastructure Clarification — 4 ↔ 5"
    refute_includes prompt.input,
      "# Ordered Stages vs Persistent Preparation Infrastructure — 4 ↔ 5"
    refute_includes prompt.input, "# Ordered Stages vs Campaign Management — 4 ↔ 5"
  end

  def test_gm_preparation_v0_3_preserves_middle_boundaries_without_benchmarks
    guardrail = AFScoring::PromptBuilder::GM_PREPARATION_BURDEN_GUARDRAIL_V0_3
    suffix = guardrail.delete_prefix(
      AFScoring::PromptBuilder::GM_PREPARATION_BURDEN_GUARDRAIL_V0_2
    )

    assert_match(/defer full execution preparation until after a player choice does\s+not erase preparation/, suffix)
    assert_match(/several substantive alternatives well enough to present their\s+distinct premises/, suffix)
    assert_match(/"Bounded" and "partitionable" are operational, not merely geographic/, suffix)
    assert_match(/cross-cutting states, selected scenario\s+tracks, staged information/, suffix)
    assert_match(/Precision and nonlinear routing alone still do not establish\s+substantial cross-cutting preparation/, suffix)
    assert_match(/Persistent callbacks, a tracker, or open navigation inside successive bounded\s+regions do not by themselves/, suffix)
    assert_match(/wide active campaign-level field while carrying earlier state across many\s+sessions/, suffix)
    assert_includes suffix, "They do not alter the Minimal endpoint"
    assert_includes suffix, "This does not narrow the existing score-5 test."
    refute_match(
      /Lake Monster|A Friend in Need|Tomb of Horrors|No Honour Among Thieves|Call of the Wild|Lost Mine of Phandelver|Expedition to the Barrier Peaks|House of Lament|The Wild Beyond the Witchlight|Storm King's Thunder/,
      suffix
    )
  end

  def test_gm_preparation_guardrail_is_not_injected_into_improvisation_only_focused_pass
    prompt = builder.build(
      group_name: "gm_demands",
      dimensions: ["GM Improvisation Demand"],
      adventure: @adventure,
      source_extraction: @extraction
    )

    refute_includes prompt.input, "# GM Preparation Burden Application Guardrail v0.1"
  end

  def test_gm_preparation_guardrail_is_not_injected_into_unrelated_groups
    prompt = builder.build(
      group_name: "adventure_structure",
      adventure: @adventure,
      source_extraction: @extraction
    )

    refute_includes prompt.input, "# GM Preparation Burden Application Guardrail v0.1"
  end

  def test_single_player_beginner_suitability_dimension_receives_v0_1_guardrail_once
    prompt = builder.build(
      group_name: "beginner_suitability",
      dimensions: ["Player Beginner Suitability"],
      adventure: @adventure,
      source_extraction: @extraction
    )

    assert_includes prompt.input,
      AFScoring::PromptBuilder::PLAYER_BEGINNER_SUITABILITY_GUARDRAIL_V0_1
    assert_equal 1,
      prompt.input.scan("# Player Beginner Suitability Support-vs-Difficulty Guardrail v0.1").length
    assert_includes prompt.input, "Raw challenge is not a downward-scoring proxy."
    assert_includes prompt.input, "Assess the residual unsupported beginner burden"
    assert_match(
      /Do\s+not treat ordinary delivery of published guidance as the "active GM guidance"/,
      prompt.input
    )
  end

  def test_default_beginner_suitability_prompt_contains_player_guardrail_once
    prompt = builder.build(
      group_name: "beginner_suitability",
      adventure: @adventure,
      source_extraction: @extraction
    )

    assert_includes prompt.input,
      AFScoring::PromptBuilder::PLAYER_BEGINNER_SUITABILITY_GUARDRAIL_V0_1
    assert_equal 1,
      prompt.input.scan("# Player Beginner Suitability Support-vs-Difficulty Guardrail v0.1").length
  end

  def test_player_beginner_guardrail_preserves_upper_anchor_counter_pressure
    guardrail = AFScoring::PromptBuilder::PLAYER_BEGINNER_SUITABILITY_GUARDRAIL_V0_1

    assert_includes guardrail, "Score 5 requires a sustained onboarding function"
    assert_includes guardrail, "Score 5 does not require perfect safety"
    assert_includes guardrail,
      "Score 4 remains appropriate when beginner support is strong and recurring"
    assert_includes guardrail, "Do not promote isolated or phase-limited support to 5."
    assert_includes guardrail, "the mere presence of support elements does not"
  end

  def test_player_beginner_guardrail_is_not_injected_into_gm_beginner_only_pass
    prompt = builder.build(
      group_name: "beginner_suitability",
      dimensions: ["GM Beginner Suitability"],
      adventure: @adventure,
      source_extraction: @extraction
    )

    refute_includes prompt.input,
      "# Player Beginner Suitability Support-vs-Difficulty Guardrail v0.1"
  end

  def test_player_beginner_guardrail_is_not_injected_into_unrelated_groups
    prompt = builder.build(
      group_name: "challenge_character",
      adventure: @adventure,
      source_extraction: @extraction
    )

    refute_includes prompt.input,
      "# Player Beginner Suitability Support-vs-Difficulty Guardrail v0.1"
  end


  def test_player_beginner_v0_2_extends_v0_1_with_progressive_onboarding_clarification
    v0_1 = AFScoring::PromptBuilder::PLAYER_BEGINNER_SUITABILITY_GUARDRAIL_V0_1
    v0_2 = AFScoring::PromptBuilder::PLAYER_BEGINNER_SUITABILITY_GUARDRAIL_V0_2

    assert v0_2.start_with?(v0_1)
    assert_includes v0_2,
      "# Player Beginner Suitability 4 ↔ 5 Progressive-Onboarding Clarification v0.2"
    assert_includes v0_2,
      "Later openness or difficulty can therefore be evidence that the onboarding"
    assert_includes v0_2, "Cumulative learning should be meaningfully transferable."
    assert_includes v0_2, "Uneven local support by itself is not a score-5 veto."
    assert_includes v0_2, "# Anti-Inflation Counter-Guardrail"
    assert_includes v0_2,
      "Strong recurring support is not enough for score 5 unless it forms a"
    assert_includes v0_2,
      "A bounded introductory phase followed by a longer open adventure also does not"
  end

  def test_single_player_beginner_prompt_receives_v0_2_progressive_onboarding_clarification_once
    prompt = builder.build(
      group_name: "beginner_suitability",
      dimensions: ["Player Beginner Suitability"],
      adventure: @adventure,
      source_extraction: @extraction
    )

    assert_includes prompt.input,
      AFScoring::PromptBuilder::PLAYER_BEGINNER_SUITABILITY_GUARDRAIL_V0_2
    assert_equal 1,
      prompt.input.scan("# Player Beginner Suitability 4 ↔ 5 Progressive-Onboarding Clarification v0.2").length
    assert_equal 1, prompt.input.scan("# Anti-Inflation Counter-Guardrail").length
    assert_equal 1,
      prompt.input.scan("# Player Beginner Suitability Support-vs-Difficulty Guardrail v0.1").length
  end

  def test_single_gm_beginner_suitability_dimension_uses_blind_reset_without_v0_1_guardrail
    prompt = builder.build(
      group_name: "beginner_suitability",
      dimensions: ["GM Beginner Suitability"],
      adventure: @adventure,
      source_extraction: @extraction
    )

    assert_equal AFScoring::PromptBuilder::GMBS_SYSTEM_INSTRUCTIONS, prompt.instructions
    assert_includes prompt.input, "# Frozen AFAO 1.0 GM Beginner Suitability Rubric"
    assert_includes prompt.input, "# Blind Assessment Task"
    refute_includes prompt.input,
      AFScoring::PromptBuilder::GM_BEGINNER_SUITABILITY_GUARDRAIL_V0_1
    refute_includes prompt.input, "# GM Beginner Suitability Application Guardrail v0.1"
  end

  def test_default_beginner_suitability_prompt_contains_gm_guardrail_once
    prompt = builder.build(
      group_name: "beginner_suitability",
      adventure: @adventure,
      source_extraction: @extraction
    )

    assert_includes prompt.input,
      AFScoring::PromptBuilder::GM_BEGINNER_SUITABILITY_GUARDRAIL_V0_1
    assert_equal 1,
      prompt.input.scan("# GM Beginner Suitability Application Guardrail v0.1").length
  end

  def test_gm_beginner_guardrail_preserves_bidirectional_boundary_pressure_without_benchmarks
    guardrail = AFScoring::PromptBuilder::GM_BEGINNER_SUITABILITY_GUARDRAIL_V0_1

    assert_includes guardrail, "Specified content is not automatically specified play."
    assert_match(/Authored setup and authored endpoints do not rescue\s+a missing central runtime/, guardrail)
    assert_includes guardrail, "one weak optional branch, sparse aftermath, or localized omission does"
    assert_includes guardrail, "condition/action -> defined"
    assert_includes guardrail, "ordinary GM judgment within a supplied mechanism is not"
    assert_includes guardrail, "None of them should hold GM Beginner"
    assert_includes guardrail, "Detailed keying or exact procedures alone do not force score 4."
    assert_includes guardrail, "Recognize either of two valid score-5 support architectures"
    assert_includes guardrail, "The presence of a tracker, flowchart, boxed advice, beginner"
    assert_includes guardrail, "Do not presume that this guardrail should raise or lower scores."
    refute_match(
      /Blood Night|Eyes of At'ar|A Restless Eternity|Shadow of the Watch|Dallabad Curse|Tomb of Horrors|Expedition to the Barrier Peaks|An Actor's Life|Lost Mine of Phandelver|The Wild Beyond the Witchlight|House of Lament|ADV-\d{4}/,
      guardrail
    )
  end

  def test_gm_beginner_guardrail_is_not_injected_into_player_beginner_only_pass
    prompt = builder.build(
      group_name: "beginner_suitability",
      dimensions: ["Player Beginner Suitability"],
      adventure: @adventure,
      source_extraction: @extraction
    )

    refute_includes prompt.input, "# GM Beginner Suitability Application Guardrail v0.1"
  end

  def test_gm_beginner_guardrail_is_not_injected_into_unrelated_groups
    prompt = builder.build(
      group_name: "challenge_character",
      adventure: @adventure,
      source_extraction: @extraction
    )

    refute_includes prompt.input, "# GM Beginner Suitability Application Guardrail v0.1"
  end

  def test_gm_beginner_v0_2_extends_v0_1_with_decision_procedure_and_boundary_preservation
    v0_1 = AFScoring::PromptBuilder::GM_BEGINNER_SUITABILITY_GUARDRAIL_V0_1
    v0_2 = AFScoring::PromptBuilder::GM_BEGINNER_SUITABILITY_GUARDRAIL_V0_2

    assert v0_2.start_with?(v0_1)
    assert_equal 1,
      v0_2.scan("# GM Beginner Suitability Decision Procedure / Boundary Preservation v0.2").length
    assert_includes v0_2, "# Support-Failure Audit — All Boundaries"
    assert_includes v0_2, "# Operational Continuity — 1 ↔ 2"
    assert_includes v0_2, "# Authored-State Continuity — 2 ↔ 3"
    assert_includes v0_2, "# Supported-Demand Audit — 3 ↔ 4"
    assert_includes v0_2, "# Pedagogical Scope / Upper-Anchor Audit — 4 ↔ 5"
    assert_includes v0_2, "# Path-Sensitivity Preservation"
  end

  def test_single_gm_beginner_prompt_excludes_v0_2_production_control
    prompt = builder.build(
      group_name: "beginner_suitability",
      dimensions: ["GM Beginner Suitability"],
      adventure: @adventure,
      source_extraction: @extraction
    )

    assert_equal AFScoring::PromptBuilder::GMBS_SYSTEM_INSTRUCTIONS, prompt.instructions
    refute_includes prompt.input,
      AFScoring::PromptBuilder::GM_BEGINNER_SUITABILITY_GUARDRAIL_V0_2
    refute_includes prompt.input,
      "# GM Beginner Suitability Decision Procedure / Boundary Preservation v0.2"
  end

  def test_gm_beginner_v0_2_requires_concrete_support_failures_and_rejects_raw_demand_proxies
    suffix = AFScoring::PromptBuilder::GM_BEGINNER_SUITABILITY_GUARDRAIL_V0_2.delete_prefix(
      AFScoring::PromptBuilder::GM_BEGINNER_SUITABILITY_GUARDRAIL_V0_1
    )

    assert_match(/identify the concrete support failure/, suffix)
    assert_match(/not automatically an unsupported task/, suffix)
    assert_match(/remove that proxy from the argument/, suffix)
    assert_match(/proxy cannot resolve\s+the adjacent boundary downward/, suffix)
    assert_match(/still has to apply that guidance does not recreate the\s+support failure/, suffix)
  end

  def test_gm_beginner_v0_2_preserves_all_boundaries_without_benchmark_leakage
    suffix = AFScoring::PromptBuilder::GM_BEGINNER_SUITABILITY_GUARDRAIL_V0_2.delete_prefix(
      AFScoring::PromptBuilder::GM_BEGINNER_SUITABILITY_GUARDRAIL_V0_1
    )

    assert_match(/runnable spine must carry the substantive middle/, suffix)
    assert_match(/condition\/action -> defined consequential resolution/, suffix)
    assert_match(/broken authored-state continuity is a substantive support gap/, suffix)
    assert_match(/functional scope, not by how many pages repeat/, suffix)
    assert_match(/explicitly perform the 4 ↔ 5 test/, suffix)
    assert_match(/does not automatically lower the scalar score/, suffix)
    assert_match(/support works only on an unusually\s+favorable path/, suffix)
    refute_match(
      /Blood Night|Eyes of At'ar|A Restless Eternity|Shadow of the Watch|Dallabad Curse|Tomb of Horrors|Expedition to the Barrier Peaks|An Actor's Life|Lost Mine of Phandelver|The Wild Beyond the Witchlight|House of Lament|ADV-\d{4}/,
      suffix
    )
  end

  def test_gm_beginner_v0_3_extends_v0_2_with_adjacent_anchor_materiality_and_coverage_preservation
    v0_2 = AFScoring::PromptBuilder::GM_BEGINNER_SUITABILITY_GUARDRAIL_V0_2
    v0_3 = AFScoring::PromptBuilder::GM_BEGINNER_SUITABILITY_GUARDRAIL_V0_3

    assert v0_3.start_with?(v0_2)
    assert_equal 1,
      v0_3.scan("# GM Beginner Suitability Adjacent-Anchor Materiality / Coverage-Preservation v0.3").length
    assert_includes v0_3, "# Anchor-Crossing Materiality Test — All Boundaries"
    assert_includes v0_3, "# Allowed Residual — 1 ↔ 2: Coherent Progression May End in a Major Gap"
    assert_includes v0_3, "# Allowed Residual — 2 ↔ 3: Authored Resolution Survives Implementation Gaps"
    assert_includes v0_3, "# Allowed Residual — 3 ↔ 4: Consistent Support Is Not Exhaustive Support"
    assert_includes v0_3, "# Allowed Residual — 4 ↔ 5: Pedagogy May Be Compositional and Transferable"
  end

  def test_gm_beginner_v0_3_historical_profile_preserves_prior_controls
    v0_3 = AFScoring::PromptBuilder::GM_BEGINNER_SUITABILITY_GUARDRAIL_V0_3

    assert_includes v0_3,
      AFScoring::PromptBuilder::GM_BEGINNER_SUITABILITY_GUARDRAIL_V0_2
    assert_equal 1,
      v0_3.scan("# GM Beginner Suitability Application Guardrail v0.1").length
    assert_equal 1,
      v0_3.scan("# GM Beginner Suitability Decision Procedure / Boundary Preservation v0.2").length
    assert_equal 1,
      v0_3.scan("# GM Beginner Suitability Adjacent-Anchor Materiality / Coverage-Preservation v0.3").length
  end

  def test_gm_beginner_v0_3_requires_anchor_crossing_materiality_not_gap_importance
    suffix = AFScoring::PromptBuilder::GM_BEGINNER_SUITABILITY_GUARDRAIL_V0_3.delete_prefix(
      AFScoring::PromptBuilder::GM_BEGINNER_SUITABILITY_GUARDRAIL_V0_2
    )

    assert_match(/important residual support gap is not by itself sufficient/, suffix)
    assert_match(/what residual burden the higher adjacent anchor still allows/, suffix)
    assert_match(/A lower score must survive step 3/, suffix)
    assert_match(/coverage and\s+materiality test, not a completeness test/, suffix)
    assert_match(/unsupported residue materially exceeds what the higher anchor\s+permits/, suffix)
  end

  def test_gm_beginner_v0_3_preserves_allowed_residuals_without_benchmark_leakage
    suffix = AFScoring::PromptBuilder::GM_BEGINNER_SUITABILITY_GUARDRAIL_V0_3.delete_prefix(
      AFScoring::PromptBuilder::GM_BEGINNER_SUITABILITY_GUARDRAIL_V0_2
    )

    assert_match(/does not require end-to-end operational continuity through the climax/, suffix)
    assert_match(/Do not move that\s+score-2 gap downward into the 1 ↔ 2 boundary/, suffix)
    assert_match(/do not relabel ordinary\s+implementation gaps as a missing central resolution/, suffix)
    assert_match(/do not treat every mentioned player method as a coequal authored route/, suffix)
    assert_match(/"Consistent" operational support at score 4 does not mean that every important/, suffix)
    assert_match(/without usable operating support/, suffix)
    assert_match(/may satisfy the what\/why\/how pedagogical test\s+together/, suffix)
    assert_match(/need not be co-located, repeated beside every later application/, suffix)
    assert_match(/repeatedly lacks both meaningful reusable teaching and adventure-specific\s+scaffolding/, suffix)
    refute_match(
      /Blood Night|Eyes of At'ar|A Restless Eternity|Shadow of the Watch|Dallabad Curse|Tomb of Horrors|Expedition to the Barrier Peaks|An Actor's Life|Lost Mine of Phandelver|The Wild Beyond the Witchlight|House of Lament|ADV-\d{4}/,
      suffix
    )
  end

  def test_gm_beginner_v0_4_branches_from_v0_2_and_excludes_rejected_v0_3
    v0_2 = AFScoring::PromptBuilder::GM_BEGINNER_SUITABILITY_GUARDRAIL_V0_2
    v0_3 = AFScoring::PromptBuilder::GM_BEGINNER_SUITABILITY_GUARDRAIL_V0_3
    v0_4 = AFScoring::PromptBuilder::GM_BEGINNER_SUITABILITY_GUARDRAIL_V0_4

    assert v0_4.start_with?(v0_2)
    refute v0_4.start_with?(v0_3)
    assert_includes v0_4,
      "# GM Beginner Suitability Lower-Boundary Structural Clarification v0.4"
    refute_includes v0_4,
      "# GM Beginner Suitability Adjacent-Anchor Materiality / Coverage-Preservation v0.3"
  end

  def test_single_gm_beginner_prompt_excludes_v0_4_and_rejected_v0_3_controls
    prompt = builder.build(
      group_name: "beginner_suitability",
      dimensions: ["GM Beginner Suitability"],
      adventure: @adventure,
      source_extraction: @extraction
    )

    assert_equal AFScoring::PromptBuilder::GMBS_SYSTEM_INSTRUCTIONS, prompt.instructions
    refute_includes prompt.input,
      AFScoring::PromptBuilder::GM_BEGINNER_SUITABILITY_GUARDRAIL_V0_4
    refute_includes prompt.input,
      "# GM Beginner Suitability Lower-Boundary Structural Clarification v0.4"
    refute_includes prompt.input,
      "# GM Beginner Suitability Adjacent-Anchor Materiality / Coverage-Preservation v0.3"
  end

  def test_default_beginner_suitability_prompt_receives_v0_4_without_v0_3_experiment
    prompt = builder.build(
      group_name: "beginner_suitability",
      adventure: @adventure,
      source_extraction: @extraction
    )

    assert_includes prompt.input,
      AFScoring::PromptBuilder::GM_BEGINNER_SUITABILITY_GUARDRAIL_V0_4
    assert_equal 1,
      prompt.input.scan("# GM Beginner Suitability Lower-Boundary Structural Clarification v0.4").length
    refute_includes prompt.input,
      "# GM Beginner Suitability Adjacent-Anchor Materiality / Coverage-Preservation v0.3"
  end

  def test_gm_beginner_v0_4_distinguishes_playable_progression_from_conceptual_sequence
    suffix = AFScoring::PromptBuilder::GM_BEGINNER_SUITABILITY_GUARDRAIL_V0_4.delete_prefix(
      AFScoring::PromptBuilder::GM_BEGINNER_SUITABILITY_GUARDRAIL_V0_2
    )

    assert_includes suffix, "# Playable-State Generation / Progression Shape — 1 ↔ 2"
    assert_match(/Authored sequential progression/, suffix)
    assert_match(/Authored runtime\/state mechanism/, suffix)
    assert_match(/architectures are alternatives, not cumulative requirements/, suffix)
    assert_match(/A conceptual sequence is not enough/, suffix)
    assert_match(/does not establish score 2 when the\s+publication still leaves the GM to invent/, suffix)
    assert_match(/do not require the score-2 architecture to remain operationally\s+complete through the final climax/, suffix)
    assert_match(/do not reject score 2 merely because a procedural runtime is sparse\s+in connective presentation/, suffix)
    assert_match(/Assign 1 when neither authored sequential\s+progression nor an authored runtime\/state mechanism/, suffix)
  end

  def test_gm_beginner_v0_4_distinguishes_authored_path_from_player_method
    suffix = AFScoring::PromptBuilder::GM_BEGINNER_SUITABILITY_GUARDRAIL_V0_4.delete_prefix(
      AFScoring::PromptBuilder::GM_BEGINNER_SUITABILITY_GUARDRAIL_V0_2
    )

    assert_includes suffix, "# Authored Path vs Player Method — 2 ↔ 3"
    assert_match(/player method becomes a route-level support obligation only when/, suffix)
    assert_match(/distinct authored body of play/, suffix)
    assert_match(/do not by\s+themselves create coequal authored routes/, suffix)
    assert_match(/remains implementation\s+detail unless the omission leaves the substantive resolution state/, suffix)
    assert_match(/Preserve score 2 when the publication truly authors a substantive alternative\s+pathway/, suffix)
    assert_match(/distinguish implementation methods inside\s+that mechanism from separately authored pathways/, suffix)
  end

  def test_gm_beginner_v0_4_is_lower_boundary_only_and_has_no_benchmark_leakage
    suffix = AFScoring::PromptBuilder::GM_BEGINNER_SUITABILITY_GUARDRAIL_V0_4.delete_prefix(
      AFScoring::PromptBuilder::GM_BEGINNER_SUITABILITY_GUARDRAIL_V0_2
    )

    assert_match(/does not\s+modify the v0.2 rules for 3 ↔ 4, 4 ↔ 5/, suffix)
    refute_includes suffix, "# Allowed Residual — 3 ↔ 4"
    refute_includes suffix, "# Allowed Residual — 4 ↔ 5"
    refute_match(
      /Blood Night|Eyes of At'ar|A Restless Eternity|Shadow of the Watch|Dallabad Curse|Tomb of Horrors|Expedition to the Barrier Peaks|An Actor's Life|Lost Mine of Phandelver|The Wild Beyond the Witchlight|House of Lament|ADV-\d{4}/,
      suffix
    )
  end

  def test_gm_beginner_v0_5_extends_v0_4_with_exceptional_pedagogy_decision_audit
    v0_4 = AFScoring::PromptBuilder::GM_BEGINNER_SUITABILITY_GUARDRAIL_V0_4
    v0_5 = AFScoring::PromptBuilder::GM_BEGINNER_SUITABILITY_GUARDRAIL_V0_5

    assert v0_5.start_with?(v0_4)
    assert_equal 1,
      v0_5.scan("# GM Beginner Suitability Exceptional-Pedagogy Decision Audit v0.5").length
    assert_includes v0_5, "# Teaching-to-Application Pairing — Broad-Instruction Architecture"
    assert_includes v0_5, "# Concentrated Procedural Teaching Preservation"
    assert_includes v0_5, "# Anti-Inflation Counter-Guardrail — Preserve Strong 4s"
  end

  def test_single_gm_beginner_prompt_excludes_v0_5_production_stack
    prompt = builder.build(
      group_name: "beginner_suitability",
      dimensions: ["GM Beginner Suitability"],
      adventure: @adventure,
      source_extraction: @extraction
    )

    assert_equal AFScoring::PromptBuilder::GMBS_SYSTEM_INSTRUCTIONS, prompt.instructions
    refute_includes prompt.input,
      AFScoring::PromptBuilder::GM_BEGINNER_SUITABILITY_GUARDRAIL_V0_5
    refute_includes prompt.input,
      "# GM Beginner Suitability Application Guardrail v0.1"
    refute_includes prompt.input,
      "# GM Beginner Suitability Decision Procedure / Boundary Preservation v0.2"
    refute_includes prompt.input,
      "# GM Beginner Suitability Lower-Boundary Structural Clarification v0.4"
    refute_includes prompt.input,
      "# GM Beginner Suitability Exceptional-Pedagogy Decision Audit v0.5"
    refute_includes prompt.input,
      "# GM Beginner Suitability Adjacent-Anchor Materiality / Coverage-Preservation v0.3"
  end

  def test_default_beginner_suitability_prompt_receives_v0_5_once
    prompt = builder.build(
      group_name: "beginner_suitability",
      adventure: @adventure,
      source_extraction: @extraction
    )

    assert_includes prompt.input,
      AFScoring::PromptBuilder::GM_BEGINNER_SUITABILITY_GUARDRAIL_V0_5
    assert_equal 1,
      prompt.input.scan("# GM Beginner Suitability Exceptional-Pedagogy Decision Audit v0.5").length
    refute_includes prompt.input,
      "# GM Beginner Suitability Adjacent-Anchor Materiality / Coverage-Preservation v0.3"
  end

  def test_gm_beginner_v0_5_pairs_broad_teaching_with_adventure_specific_application
    suffix = AFScoring::PromptBuilder::GM_BEGINNER_SUITABILITY_GUARDRAIL_V0_5.delete_prefix(
      AFScoring::PromptBuilder::GM_BEGINNER_SUITABILITY_GUARDRAIL_V0_4
    )

    assert_match(/Build an evidence pairing across several materially different GM\s+responsibilities/, suffix)
    assert_match(/Teaching evidence: direct novice-oriented guidance that explains how or why/, suffix)
    assert_match(/Application evidence: procedures, preparation instructions, trackers/, suffix)
    assert_match(/need not be co-located, repeated beside every later\s+application, or explicitly cross-referenced/, suffix)
    assert_match(/Count breadth by materially different GM responsibilities/, suffix)
    assert_match(/affirmative score-5 evidence when\s+several materially different responsibilities receive genuine teaching/, suffix)
    assert_match(/need not eliminate the tasks/, suffix)
  end

  def test_gm_beginner_v0_5_is_upper_boundary_only_with_counter_pressure_and_no_benchmark_leakage
    suffix = AFScoring::PromptBuilder::GM_BEGINNER_SUITABILITY_GUARDRAIL_V0_5.delete_prefix(
      AFScoring::PromptBuilder::GM_BEGINNER_SUITABILITY_GUARDRAIL_V0_4
    )

    assert_match(/only to the 4 ↔ 5 boundary/, suffix)
    assert_match(/does not modify the\s+v0.4 rules for 1 ↔ 2 or 2 ↔ 3, the v0.2 rule for 3 ↔ 4/, suffix)
    assert_match(/not a general instruction to choose score 5/, suffix)
    assert_match(/Do not require broad general GM instruction in order to assign score 5/, suffix)
    assert_match(/Strong organization, runnable procedures, trackers, clear objectives, fallback\s+routes, forgiving design, boxed advice, or abundant GM-facing detail do not\s+establish score 5 by themselves/, suffix)
    assert_match(/Teaching\s+without meaningful application support can remain score 4; application\s+scaffolding without meaningful teaching can remain score 4/, suffix)
    refute_includes suffix, "# Playable-State Generation / Progression Shape — 1 ↔ 2"
    refute_includes suffix, "# Authored Path vs Player Method — 2 ↔ 3"
    refute_match(
      /Blood Night|Eyes of At'ar|A Restless Eternity|Shadow of the Watch|Dallabad Curse|Tomb of Horrors|Expedition to the Barrier Peaks|An Actor's Life|Lost Mine of Phandelver|The Wild Beyond the Witchlight|House of Lament|ADV-\d{4}/,
      suffix
    )
  end


  def test_levels_prompt_receives_nested_context_guardrail_and_precanonical_context
    prompt = builder.build(
      group_name: "sessions_levels",
      dimensions: ["Levels"],
      adventure: @adventure,
      source_extraction: @extraction,
      levels_context: "<!-- PAGE: 4 -->\nCharacter Advancement: characters start at 1st level."
    )

    assert_includes prompt.input, AFScoring::PromptBuilder::LEVELS_NESTED_CONTEXT_GUARDRAIL_V0_1
    assert_includes prompt.input, "# Supplemental Pre-Canonical Levels Context"
    assert_includes prompt.input, "characters start at 1st level"
    assert_includes prompt.input, "Level End may equal Level Start"
    assert_includes prompt.input, "must not be used to score # of Sessions"
  end

  def test_sessions_only_prompt_does_not_receive_levels_guardrail_or_context
    prompt = builder.build(
      group_name: "sessions_levels",
      dimensions: ["# of Sessions"],
      adventure: @adventure,
      source_extraction: @extraction,
      levels_context: "characters start at 1st level"
    )

    refute_includes prompt.input, "# Levels Nested-Adventure Context / Inherited Entry-State Guardrail v0.1"
    refute_includes prompt.input, "# Supplemental Pre-Canonical Levels Context"
  end

  def test_sessions_only_prompt_uses_canonical_nos_profile
    prompt = builder.build(
      group_name: "sessions_levels",
      dimensions: ["# of Sessions"],
      adventure: @adventure,
      source_extraction: @extraction
    )

    assert_equal AFScoring::PromptBuilder::NOS_SYSTEM_INSTRUCTIONS,
      prompt.instructions
    assert_includes prompt.input, "# Blind Assessment Task"
    refute_includes prompt.input, "# AdventureFinder Production Assessment Rules"
    refute_includes prompt.input, "# Number of Sessions Compact-Phase Aggregation Guardrail"
    refute_includes prompt.input, "# Anti-Compression Counter-Guardrail"
  end

  def test_sessions_and_levels_cannot_share_a_prompt
    error = assert_raises(AFScoring::SpecificationError) do
      builder.build(
        group_name: "sessions_levels",
        adventure: @adventure,
        source_extraction: @extraction
      )
    end

    assert_includes error.message, "# of Sessions must be scored independently from Levels"
  end

  def test_levels_guardrail_preserves_qualitative_only_uncertainty_rule
    guardrail = AFScoring::PromptBuilder::LEVELS_NESTED_CONTEXT_GUARDRAIL_V0_1
    assert_includes guardrail, "qualitative guidance"
    assert_includes guardrail, 'such as "high-level characters"'
    assert_includes AFScoring::PromptBuilder::LEVELS_NESTED_CONTEXT_GUARDRAIL_V0_1,
      "Do not guess from difficulty or placement alone."
  end

  def test_single_structural_openness_dimension_receives_v0_1_guardrail_once
    prompt = builder.build(
      group_name: "adventure_structure",
      dimensions: ["Structural Openness"],
      adventure: @adventure,
      source_extraction: @extraction
    )

    assert_includes prompt.input,
      AFScoring::PromptBuilder::STRUCTURAL_OPENNESS_GUARDRAIL_V0_1
    assert_equal 1,
      prompt.input.scan("# Structural Openness Structural-Scale / Play-Coverage Guardrail v0.1").length
    assert_includes prompt.input, "# Structural Scale / Lower-Boundary Accounting"
    assert_includes prompt.input, "# Gate Non-Absolutism / Upper-Boundary Accounting"
    assert_includes prompt.input, "# Expected-Play Coverage"
  end

  def test_default_adventure_structure_prompt_contains_structural_openness_guardrail_once
    prompt = builder.build(
      group_name: "adventure_structure",
      adventure: @adventure,
      source_extraction: @extraction
    )

    assert_includes prompt.input,
      AFScoring::PromptBuilder::STRUCTURAL_OPENNESS_GUARDRAIL_V0_1
    assert_equal 1,
      prompt.input.scan("# Structural Openness Structural-Scale / Play-Coverage Guardrail v0.1").length
  end

  def test_structural_openness_guardrail_is_not_injected_into_cpa_only_pass
    prompt = builder.build(
      group_name: "adventure_structure",
      dimensions: ["Consequential Player Agency"],
      adventure: @adventure,
      source_extraction: @extraction
    )

    refute_includes prompt.input,
      "# Structural Openness Structural-Scale / Play-Coverage Guardrail v0.1"
  end

  def test_structural_openness_guardrail_is_not_injected_into_unrelated_group
    prompt = builder.build(
      group_name: "challenge_character",
      adventure: @adventure,
      source_extraction: @extraction
    )

    refute_includes prompt.input,
      "# Structural Openness Structural-Scale / Play-Coverage Guardrail v0.1"
  end

  def test_structural_openness_v0_1_encodes_play_coverage_and_bidirectional_boundaries_without_benchmarks
    guardrail = AFScoring::PromptBuilder::STRUCTURAL_OPENNESS_GUARDRAIL_V0_1

    assert_match(/weight a choice or constraint by the amount\s+of expected substantive adventure progression it governs/, guardrail)
    assert_match(/same prescribed objective and next major destination intact does not by\s+itself increase Structural Openness/, guardrail)
    assert_match(/do not cap an otherwise High structure at 3 merely\s+because a meaningful spine or fixed gates exist/, guardrail)
    assert_match(/Preserve score 3 when the fixed spine, mandatory sequence, or major gates\s+repeatedly determine substantial next phases/, guardrail)
    assert_match(/do not cap an otherwise Dominant structure at 4 merely\s+because it has a common entrance, endpoint, clock, transition, or light access/, guardrail)
    assert_match(/Preserve score 4 when player-directed progression is dominant across much of\s+play but a meaningful macrosequence or campaign spine still shapes substantial/, guardrail)
    assert_match(/Do not underweight authored wandering, quest selection, location selection, or\s+route selection merely because it is optional/, guardrail)
    assert_match(/structural\s+coverage, not mere feature presence/, guardrail)

    refute_match(
      /ADV-\d{4}|Lake Monster|A Friend in Need|No Honour Among Thieves|Call of the Wild|Lost Mine of Phandelver|Tomb of Horrors|House of Lament|Expedition to the Barrier Peaks|The Wild Beyond the Witchlight|Storm King's Thunder|Witchlight Carnival|Dungeon Level/,
      guardrail
    )
  end

  def test_structural_openness_v0_2_extends_v0_1_without_rewriting_it
    v0_1 = AFScoring::PromptBuilder::STRUCTURAL_OPENNESS_GUARDRAIL_V0_1
    v0_2 = AFScoring::PromptBuilder::STRUCTURAL_OPENNESS_GUARDRAIL_V0_2

    assert v0_2.start_with?(v0_1)
    assert_equal 1,
      v0_2.scan("# Structural Openness Structural-Scale / Play-Coverage Guardrail v0.1").length
    assert_equal 1,
      v0_2.scan("# Structural Openness Container-vs-Progression Counter-Guardrail v0.2").length
  end

  def test_single_structural_openness_prompt_receives_v0_2_counter_guardrail_once
    prompt = builder.build(
      group_name: "adventure_structure",
      dimensions: ["Structural Openness"],
      adventure: @adventure,
      source_extraction: @extraction
    )

    assert_includes prompt.input,
      AFScoring::PromptBuilder::STRUCTURAL_OPENNESS_GUARDRAIL_V0_2
    assert_equal 1,
      prompt.input.scan("# Structural Openness Structural-Scale / Play-Coverage Guardrail v0.1").length
    assert_equal 1,
      prompt.input.scan("# Structural Openness Container-vs-Progression Counter-Guardrail v0.2").length
  end

  def test_default_adventure_structure_prompt_receives_structural_openness_v0_2_once
    prompt = builder.build(
      group_name: "adventure_structure",
      adventure: @adventure,
      source_extraction: @extraction
    )

    assert_includes prompt.input,
      AFScoring::PromptBuilder::STRUCTURAL_OPENNESS_GUARDRAIL_V0_2
    assert_equal 1,
      prompt.input.scan("# Structural Openness Container-vs-Progression Counter-Guardrail v0.2").length
  end

  def test_structural_openness_v0_2_encodes_container_route_and_temporal_distinctions_without_benchmarks
    suffix = AFScoring::PromptBuilder::STRUCTURAL_OPENNESS_GUARDRAIL_V0_2.delete_prefix(
      AFScoring::PromptBuilder::STRUCTURAL_OPENNESS_GUARDRAIL_V0_1
    )

    assert_match(/do not satisfy that test\s+merely because the publication determines which broad chapter, realm, deck/, suffix)
    assert_match(/structural weight comes from how much substantive authored\s+progression it prescribes after that transition/, suffix)
    assert_match(/Preserve score 3 when fixed structure does more than select the next container/, suffix)
    assert_match(/who determines the substantive progression within and between them/, suffix)
    assert_includes suffix, "Expected-play weighting is not successful-path filtering."
    assert_match(/false, punitive, looping, dangerous, or ultimately\s+nonprogressing route counts/, suffix)
    assert_match(/immediate dead ends, single-room trap branches, fake doors,\s+trivial side passages/, suffix)
    assert_match(/A clock, timed event schedule, common entrance, common endpoint, or mandatory\s+final transition/, suffix)
    assert_match(/Temporal\s+framing around player-directed play is not itself a progression sequence/, suffix)
    assert_match(/Preserve score 4 when a meaningful macrosequence or campaign spine genuinely\s+organizes substantial portions/, suffix)
    assert_match(/a common frame alone neither defeats nor establishes 5/, suffix)

    refute_match(
      /ADV-\d{4}|Lake Monster|A Friend in Need|No Honour Among Thieves|Call of the Wild|Lost Mine of Phandelver|Tomb of Horrors|House of Lament|Expedition to the Barrier Peaks|The Wild Beyond the Witchlight|Storm King's Thunder|Witchlight Carnival|Dungeon Level/,
      suffix
    )
  end

  def test_single_lethality_failure_severity_dimension_receives_failure_conversion_guardrail_once
    prompt = builder.build(
      group_name: "challenge_character",
      dimensions: ["Lethality / Failure Severity"],
      adventure: @adventure,
      source_extraction: @extraction
    )

    assert_includes prompt.input,
      AFScoring::PromptBuilder::LETHALITY_FAILURE_SEVERITY_GUARDRAIL_V0_1
    assert_equal 1,
      prompt.input.scan("# Lethality / Failure Severity Failure-Conversion Guardrail v0.1").length
  end

  def test_default_challenge_character_prompt_receives_lethality_failure_conversion_guardrail_once
    prompt = builder.build(
      group_name: "challenge_character",
      adventure: @adventure,
      source_extraction: @extraction
    )

    assert_includes prompt.input,
      AFScoring::PromptBuilder::LETHALITY_FAILURE_SEVERITY_GUARDRAIL_V0_1
    assert_equal 1,
      prompt.input.scan("# Lethality / Failure Severity Failure-Conversion Guardrail v0.1").length
  end

  def test_lethality_failure_conversion_guardrail_is_isolated_from_sibling_focused_dimensions
    tactical_prompt = builder.build(
      group_name: "challenge_character",
      dimensions: ["Tactical Complexity"],
      adventure: @adventure,
      source_extraction: @extraction
    )
    rsmd_prompt = builder.build(
      group_name: "challenge_character",
      dimensions: ["Rules / System-Mastery Demand"],
      adventure: @adventure,
      source_extraction: @extraction
    )

    refute_includes tactical_prompt.input,
      "# Lethality / Failure Severity Failure-Conversion Guardrail v0.1"
    refute_includes rsmd_prompt.input,
      "# Lethality / Failure Severity Failure-Conversion Guardrail v0.1"
  end

  def test_lethality_failure_conversion_guardrail_encodes_authored_failure_accounting_without_benchmark_leakage
    guardrail = AFScoring::PromptBuilder::LETHALITY_FAILURE_SEVERITY_GUARDRAIL_V0_1

    assert_match(
      /Do not infer recurring severe consequences merely from recurring encounters in\s+which PCs could theoretically die/,
      guardrail
    )
    assert_match(
      /warning, mitigation, retreat, capture,\s+unconsciousness, rescue, resurrection, recovery, alternate progression,\s+fail-forward procedures/,
      guardrail
    )
    assert_match(
      /Count recurrence of qualifying severe failure conversions, not recurrence of\s+combat, hazards, difficult encounters/,
      guardrail
    )
    assert_match(/raw\s+incident count as a substitute for that chain/, guardrail)
    assert_match(
      /Do not demote a genuine 4 merely\s+because some warning, allies, or escape options exist/,
      guardrail
    )
    assert_match(
      /failure -> resulting state -> recovery\/irreversibility chain/,
      guardrail
    )

    refute_match(
      /ADV-\d{4}|Witchlight Carnival|Call of the Wild|The Wild Beyond the Witchlight|Lost Mine of Phandelver|Expedition to the Barrier Peaks|Storm King's Thunder|No Honour Among Thieves|House of Lament|Tomb of Horrors/,
      guardrail
    )
  end

  private

  def builder
    AFScoring::PromptBuilder.new(afao: @afao, assessment_spec: @assessment_spec)
  end
end
