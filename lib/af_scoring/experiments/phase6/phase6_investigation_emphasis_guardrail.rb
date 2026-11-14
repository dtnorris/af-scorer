# frozen_string_literal: true

module AFScoring
  module Phase6InvestigationEmphasisGuardrail
    PROFILE_ENV = "AF_INVESTIGATION_GUARDRAIL_PROFILE"
    PROFILE = "phase6-v0.4"

    TEXT = <<~TEXT.freeze
      # Investigation Emphasis Endpoint Boundary Guardrail v0.4

      This Phase-6 experimental clarification addresses only two demonstrated boundary
      errors in applying the frozen Investigation Emphasis rubric: Minimal ↔ Low (1 ↔ 2)
      and High ↔ Very High (4 ↔ 5). It does not alter the AFAO anchors or the existing
      v0.3 treatment of the 2 ↔ 3 or 3 ↔ 4 boundaries.

      # 1 ↔ 2 — Qualifying Unknown, Not Merely Progress-Relevant Information

      To establish score 2 rather than score 1, identify substantive player-facing inquiry
      into at least one unresolved qualifying fact, cause, identity, relationship, or
      explanation. The inquiry may be direct or straightforward; difficulty, ambiguity,
      multiple sources, and prolonged deduction are not required.

      Do not establish score 2 merely because players must find, interpret, or follow
      information that is necessary for progression. Route-finding, tracking a path,
      locating a destination, identifying where to go next, operating or bypassing a
      mechanism, using a key or sequence, decoding operational instructions, mapping,
      traversal clues, or environmental navigation remain principally non-investigative
      unless that activity also establishes a qualifying fact, cause, identity,
      relationship, or explanation.

      In particular, "the clue is necessary," "players must notice it," "progress depends
      on interpreting it," or "players must actively search for it" are not sufficient
      reasons to raise Minimal to Low. First state the unresolved qualifying question the
      players are investigating. If no such question can be identified, preserve score 1
      even when clues or information are materially important to completing the adventure.

      Preserve score 2 when localized but meaningful inquiry really does answer a
      qualifying unknown, even if the evidence is explicit, the inference is easy, or the
      answer is obtained quickly. This clarification must not create a general downward
      preference at the lower boundary.

      # 4 ↔ 5 — Independent Progression Must Be Independent of Investigation

      After score 4 has independently been satisfied under the existing rubric, test score
      5 by asking whether repeated investigation-driven discovery -> revised understanding
      -> next actionable objective, actor, location, or problem-state cycles themselves
      form a fundamental organizing structure of expected progression.

      Do not treat a downstream phase as an independent major progression spine merely
      because executing that phase uses combat, social interaction, exploration,
      traversal, infiltration, or another non-investigative mode. A downstream phase is
      independent for the 4 ↔ 5 test only when its major actor, location, objective, or
      problem state is materially determined by an authored progression structure that
      would still carry that major progression without the investigative discoveries that
      reveal, select, or materially reframe what becomes actionable next.

      Accordingly, combat against an actor identified through investigation, travel to a
      location revealed through investigation, social engagement with a person made
      actionable through investigation, or a terminal confrontation enabled by the
      investigative chain does not by itself break the investigative organizing spine.
      Different play modes may execute the consequences of an investigation while
      Investigation still fundamentally organizes the sequence of major progression.

      Preserve score 4 when another major authored objective spine genuinely determines
      substantial progression independently of investigative discovery—for example, when
      major objectives and destinations are already materially fixed and Investigation
      primarily supplies context, optional advantages, confirmation, or local information
      rather than determining what major problem, actor, location, or objective becomes
      actionable next.

      Score 5 is not established merely because clues recur, every phase contains some
      information, or investigation precedes other modes. The repeated discovery cycle must
      materially determine the adventure's changing major actionable state. Apply the
      ordinary adjacent-anchor falsification after this independence test.

      This clarification is benchmark-blind: it changes neither anchor definitions nor
      target scores, and it presumes neither a higher nor a lower Investigation Emphasis
      result.
    TEXT

    FOCUSED_TASK_MARKER = "\n\n# Focused Assessment Task\n"

    def build(group_name:, adventure:, source_extraction:, dimensions: nil, levels_context: nil)
      prompt = super
      selected_dimensions = dimensions || DimensionGroups.fetch(group_name)
      return prompt unless selected_dimensions.include?("Investigation Emphasis")

      profile = ENV[PROFILE_ENV]
      return prompt if profile.nil? || profile.empty?

      unless profile == PROFILE
        raise ConfigurationError,
              "Unsupported Investigation Emphasis guardrail profile #{profile.inspect}; expected #{PROFILE.inspect}"
      end

      unless prompt.input.include?(FOCUSED_TASK_MARKER)
        raise SpecificationError,
              "Unable to inject Investigation Emphasis Phase-6 v0.4 guardrail: focused task marker not found"
      end

      prompt.input = prompt.input.sub(
        FOCUSED_TASK_MARKER,
        "\n\n#{TEXT}\n# Focused Assessment Task\n"
      )
      prompt
    end
  end

  PromptBuilder.prepend(Phase6InvestigationEmphasisGuardrail)
end
