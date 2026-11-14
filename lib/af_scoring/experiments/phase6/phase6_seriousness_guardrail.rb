# frozen_string_literal: true

module AFScoring
  module Phase6SeriousnessGuardrail
    PROFILE_ENV = "AF_SERIOUSNESS_GUARDRAIL_PROFILE"
    PROFILE = "phase6-v0.3"

    TEXT = <<~TEXT.freeze
      # Seriousness Direct Register-Comparison Decision Guardrail v0.3

      This Phase-6 experimental clarification changes only the decision method used to
      apply the frozen Seriousness anchors. It does not alter the AFAO definition or
      anchors, does not replace the production v0.1/v0.2 guardrails, and does not direct
      the scorer toward lower Seriousness values.

      Apply this clarification to the 2 ↔ 3, 3 ↔ 4, and 4 ↔ 5 boundaries. Preserve the
      existing production treatment of the 1 ↔ 2 boundary.

      # Build the Two Player-Facing Registers Independently

      Before choosing among scores 2 through 5, separately inventory the substantive
      player-facing evidence for:

      1. the playful, comic, whimsical, lighthearted, caper-like, celebratory, or
         otherwise lighter register; and
      2. the earnest, dramatic, grave, solemn, tragic, tense, or otherwise serious
         register.

      Weight each register by how much it substantively shapes expected
      substantially-as-published table experience: recurrence, duration, interaction,
      framing, and presence across meaningful phases of play.

      Do not initially ask which register is more important to the plot. Do not initially
      ask which register contains the central objective, villain, danger, deadline, or
      consequences. First establish the experiential weight of each register on its own
      player-facing evidence.

      # Objective Gravity Is Not Tonal Weight

      Danger, urgency, lethality, difficult encounters, villainy, betrayal, catastrophic
      stakes, deadlines, severe consequences, political fallout, survival pressure, and
      plot importance can coexist with an earnest register, but none is standalone
      evidence that the earnest register outweighs a lighter register.

      Likewise, an important mystery, rescue, conspiracy, threat, artifact, faction
      conflict, or campaign objective does not become additional tonal weight merely
      because it organizes the plot.

      Credit those circumstances to Seriousness only through the way the published
      adventure actually presents and sustains them as player-facing earnest or dramatic
      experience.

      # Symmetric Treatment of the Lighter Register

      Do not discount substantive lighter material merely because it is less important
      to the objective, does not resolve the central plot, occurs inside a dangerous
      situation, shares scenes with earnest material, or functions partly as contrast.

      "Flavor," "color," "comic relief," "contrast," "façade," "setup," "opening phase,"
      or "NPC quirk" are conclusions about tonal weight, not automatic exclusions. Before
      using one of those labels to reduce lighter evidence, explain why the cited
      player-facing material is actually brief, incidental, rare, peripheral, or
      insufficiently experience-shaping under the frozen anchor.

      Conversely, do not inflate the lighter register merely because the setting is
      whimsical, fantastical, eccentric, colorful, surreal, nonviolent, or populated by
      humorous names and images. The material must substantively shape player-facing
      play.

      # Boundary Decision Sequence

      After both registers have been independently established, compare them directly.

      For 2 ↔ 3:
      - Score 2 when the lighter register clearly predominates across expected play
        while earnest material is meaningful but remains secondary.
      - Score 3 when both registers are substantively present without a clear tonal
        hierarchy strong enough for either to remain merely secondary.
      - Narrative centrality of the earnest objective does not by itself make the
        earnest register comparably substantial.

      For 3 ↔ 4:
      - Score 3 when both registers remain substantively important enough that no clear
        earnest-over-lighter hierarchy governs expected play.
      - Score 4 when the earnest/dramatic register clearly predominates across most of
        expected play while meaningful lighter material remains present.
      - Do not establish that predominance by listing higher stakes, greater danger, a
        stricter deadline, worse consequences, or a more plot-central earnest objective.
        Identify how the earnest register itself occupies and shapes more of the
        player-facing experience.

      For 4 ↔ 5:
      - Score 4 when earnest/dramatic play clearly predominates but substantive lighter
        material still meaningfully lightens a nontrivial portion of expected play.
      - Score 5 only when the earnest/dramatic register is sustained across nearly all
        expected substantive play and lighter material is genuinely rare, peripheral,
        incidental, or too slight to materially alter the experience.
      - "Less plot-central than the serious material" is not equivalent to "rare or
        peripheral." Assess the actual recurrence, duration, interactivity, and
        experience-shaping role of the lighter material.

      # Adjacent-Anchor Falsification

      For the chosen boundary:

      1. cite the strongest substantive evidence for each player-facing register;
      2. state the expected-play weight of each without using objective stakes or plot
         importance as a substitute;
      3. identify the actual experiential hierarchy, if any; and
      4. explain why the adjacent score's register relationship is not better supported.

      A valid reason may refer to recurrence, duration, interactive centrality,
      phase-coverage, or sustained framing of a register. A reason that reduces to
      "the serious events matter more to the plot," "the stakes are high," "failure is
      dangerous," or "the lighter material is just contrast" is insufficient unless the
      corresponding player-facing register evidence independently supports that tonal
      hierarchy.

      # Anti-Overcorrection

      This clarification is not a numeric correction and must not be applied as
      "subtract one." Preserve score 4 when direct register comparison really shows a
      clear earnest hierarchy. Preserve score 5 when lighter material is truly rare or
      peripheral. Preserve score 3 when the registers are genuinely mixed, and score 2
      when the lighter register genuinely predominates.

      The decision must follow the player-facing tonal evidence in either direction.
    TEXT

    FOCUSED_TASK_MARKER = "\n\n# Focused Assessment Task\n"

    def build(group_name:, adventure:, source_extraction:, dimensions: nil, levels_context: nil)
      prompt = super
      selected_dimensions = dimensions || DimensionGroups.fetch(group_name)
      return prompt unless selected_dimensions.include?("Seriousness")

      profile = ENV[PROFILE_ENV]
      return prompt if profile.nil? || profile.empty?

      unless profile == PROFILE
        raise ConfigurationError,
              "Unsupported Seriousness guardrail profile #{profile.inspect}; expected #{PROFILE.inspect}"
      end

      unless prompt.input.include?(FOCUSED_TASK_MARKER)
        raise SpecificationError,
              "Unable to inject Seriousness Phase-6 v0.3 guardrail: focused task marker not found"
      end

      prompt.input = prompt.input.sub(
        FOCUSED_TASK_MARKER,
        "\n\n#{PromptBuilder::SERIOUSNESS_GUARDRAIL_V0_2}\n\n#{TEXT}\n# Focused Assessment Task\n"
      )
      prompt
    end
  end

  PromptBuilder.prepend(Phase6SeriousnessGuardrail)
end
