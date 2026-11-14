# frozen_string_literal: true

module AFScoring
  module Phase6LethalityFailureSeverityGuardrail
    PROFILE_ENV = "AF_LETHALITY_GUARDRAIL_PROFILE"
    PROFILE = "phase6-v0.3"

    TEXT = <<~TEXT.freeze
      # Lethality / Failure Severity Failure-State Topology Guardrail v0.3

      This experimental clarification addresses a demonstrated application failure in
      the frozen Lethality / Failure Severity rubric: safety, guidance, continuation,
      and recovery mechanisms can only be weighted correctly after the scorer has
      established what state exists before failure, what threshold is crossed, and what
      state actually exists afterward.

      This clarification does not change the AFAO anchors and does not presume that a
      higher or lower Lethality / Failure Severity score is preferable.

      # Required Failure-State Transition Audit

      Before selecting an anchor, identify the material severe-failure morphologies that
      can arise in substantially-as-published expected play. For each morphology, reason
      through this sequence in order:

      pre-failure state → failure threshold → immediate post-failure state → mitigation / recovery → final state

      Do not choose the score first and fit this sequence to it afterward. Establish the
      state transition from the source, then compare the resulting failure profile to the
      frozen anchors.

      For every mechanism cited as reducing severity, classify its actual role as one of:

      1. success guidance — helps players know what to do but does not itself alter a
         realized failure state;
      2. exposure prevention — reduces the chance of reaching the failure threshold;
      3. pre-lock-in escape — permits avoidance or retreat before the severe state is
         imposed;
      4. consequence conversion — after the triggering failure occurs, changes the
         immediate outcome into a materially less severe state;
      5. post-failure recovery — materially reverses or repairs the severe state after it
         has occurred;
      6. continuation despite consequence — play can continue while the severe consequence
         remains materially real; or
      7. no conversion — the mechanism changes presentation, information, or secondary
         state details without reversing the severe consequence.

      A mechanism may support more than one role only when the source explicitly supports
      each role. Do not treat all beneficial or player-helping features as interchangeable
      "safety valves."

      # Verify the Post-Condition Literally

      Determine the post-failure state from what the source actually says happens.
      Do not infer recovery from the fact that play continues, an objective remains
      achievable, an ally provides help, or a rule modifies the scene.

      In particular:

      - success guidance is not consequence conversion;
      - warning or telegraphing is not recovery;
      - a saving throw or ordinary defensive mechanic is not authored post-failure
        recovery merely because it can prevent a consequence from occurring;
      - preservation is not revival;
      - continuation after capture, death, transformation, imprisonment, loss, or another
        severe consequence does not mean that consequence was reversed; and
      - if a rule says that no additional effect occurs, preserve the state that already
        existed before that rule was applied rather than inventing a favorable conversion.

      When the wording is ambiguous, do not assume the interpretation that most reduces
      lethality. Use the best-supported literal post-condition and record material
      uncertainty under the ordinary assessment rules.

      # Mandatory Escalation Counts as Expected Play

      Evaluate the whole canonical adventure as authored. If ordinary completion
      structurally transitions from a safer phase into a dangerous phase, the later state
      remains part of expected play even when earlier exploration or investigation is
      comparatively forgiving.

      Do not dismiss severe failure as merely localized because it is concentrated in an
      awakened state, escape sequence, mandatory dungeon phase, terminal act, or climax.
      Ask whether the dangerous phase is optional/path-dependent or whether the authored
      progression normally places characters into that state space. A mandatory phase can
      make severe failure readily credible without requiring equal lethality from the first
      scene to the last.

      # Weight Only After Topology Is Established

      After the transition audit, apply the frozen anchors using the actual combination of:

      - severity of the realized failure state;
      - how often or how structurally the threshold is encountered in expected play;
      - whether exposure is optional, avoidable, or mandatory;
      - what protections act before the threshold;
      - what conversions or recoveries act after the threshold; and
      - whether those mechanisms are reliable enough to change the substantially-as-
        published consequence profile.

      Genuine mitigation still matters. Preserve lower anchors when severe failure is
      exceptional, localized, strongly and reliably avoided, or actually converted or
      reversed by authored mechanisms. Do not raise a score merely because death, lasting
      loss, imprisonment, or another severe outcome is possible somewhere in the text.

      Conversely, do not lower a score merely because players receive clues, warnings,
      allies, objectives, escape routes, or ordinary defensive opportunities. Those
      features lower the failure profile only to the extent their verified place in the
      state transition actually prevents, converts, or reverses the relevant severe state.

      # Adjacent-Anchor Falsification Must Use the State Transition

      For every adjacent boundary under consideration, explicitly test whether the lower
      and higher interpretations imply a different failure-state topology or a different
      frequency / embeddedness of the same topology.

      The rationale supporting the chosen anchor must identify the decisive transition:
      the failure threshold, immediate post-failure state, and the actual final state after
      any claimed mitigation or recovery. If the lower anchor depends on a mechanism that
      only supplies guidance, reduces exposure, or permits continuation without reversing
      the severe state, say so and test whether that is sufficient under the frozen anchor
      rather than treating the mechanism as consequence conversion by default.

      The score-5 endpoint remains governed by the frozen rubric and production v0.1
      guardrail. This clarification supplies no independent reason to raise a score to 5.
    TEXT

    FOCUSED_TASK_MARKER = "\n\n# Focused Assessment Task\n"

    def build(group_name:, adventure:, source_extraction:, dimensions: nil, levels_context: nil)
      prompt = super
      selected_dimensions = dimensions || DimensionGroups.fetch(group_name)
      return prompt unless selected_dimensions.include?("Lethality / Failure Severity")

      profile = ENV[PROFILE_ENV]
      return prompt if profile.nil? || profile.empty?

      unless profile == PROFILE
        raise ConfigurationError,
              "Unsupported Lethality / Failure Severity guardrail profile #{profile.inspect}; expected #{PROFILE.inspect}"
      end

      unless prompt.input.include?(FOCUSED_TASK_MARKER)
        raise SpecificationError,
              "Unable to inject Lethality / Failure Severity Phase-6 v0.3 guardrail: focused task marker not found"
      end

      prompt.input = prompt.input.sub(
        FOCUSED_TASK_MARKER,
        "\n\n#{TEXT}\n# Focused Assessment Task\n"
      )
      prompt
    end
  end

  PromptBuilder.prepend(Phase6LethalityFailureSeverityGuardrail)
end
