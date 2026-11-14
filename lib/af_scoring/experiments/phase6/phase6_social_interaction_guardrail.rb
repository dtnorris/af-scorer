# frozen_string_literal: true

module AFScoring
  module Phase6SocialInteractionGuardrail
    PROFILE_ENV = "AF_SOCIAL_INTERACTION_GUARDRAIL_PROFILE"
    PROFILE = "phase6-v0.3"

    TEXT = <<~TEXT.freeze
      # Social Interaction Emphasis Cross-Mode Independence Guardrail v0.3

      This Phase-6 experimental clarification addresses one narrow failure mode: do not
      treat AdventureFinder dimensions as mutually exclusive buckets when identifying
      meaningful Social Interaction. Apply the frozen Social Interaction Emphasis anchors
      to the social work players actually perform, even when the same scene or exchange
      also advances Investigation, exploration, combat avoidance, or another dimension.

      # Social Actorship, Not Scene Exclusivity

      Count an interaction as Social Interaction when players substantively engage with
      an NPC or other authored social actor whose goals, attitudes, trust, cooperation,
      deception, opposition, willingness to disclose, relationship state, or decisions
      are meaningfully in play. The communication medium does not decide the dimension:
      face-to-face conversation, remote communication, supernatural communication, or
      another authored exchange can qualify when the social actorship test is satisfied.

      Do not exclude an otherwise qualifying social exchange merely because players are
      also learning clues, determining facts, investigating motives, or advancing another
      play mode through it. A single scene may legitimately supply evidence for more than
      one AdventureFinder dimension. Score each dimension independently.

      # Boundary Application

      For 2 ↔ 3, aggregate qualifying social interaction across ordinary expected play
      even when individual exchanges also serve investigative or other purposes. Preserve
      score 2 when qualifying interaction remains limited or clearly secondary; use score
      3 when it is substantial and recurring under the frozen anchor.

      For 3 ↔ 4, judge whether Social Interaction itself is one of the dominant modes and
      regularly drives progress. The existence of substantial combat, exploration,
      investigation, or other independently meaningful play is not a downward veto when
      Social Interaction independently satisfies the High anchor.

      For 4 ↔ 5, do not require Social Interaction to be exclusive or to eliminate other
      major play modes. Apply the existing v0.2 structural test: preserve 4 when another
      major progression structure genuinely carries substantial progression independently;
      use 5 only when social engagement itself functions as a fundamental organizer of
      expected progression under the frozen AFAO anchor.

      # Anti-Inflation Counter-Test

      Cross-mode overlap does not make all information exchange social. Passive
      exposition, records, environmental messages, non-agent visions, a scripted monologue
      with no substantive reciprocal social engagement, routine quest handoff, or an NPC
      merely being present does not independently establish meaningful Social Interaction.
      Likewise, recurrence or narrative importance alone does not establish scores 3–5.
      Identify the actual player-facing engagement with authored social actorship and then
      apply the ordinary recurrence, dominance, and organizing-structure thresholds.

      In adjacent-anchor falsification, do not use "this is really Investigation" or
      "substantial non-social play also exists" as a standalone reason to choose the lower
      Social Interaction anchor. First determine whether qualifying social actorship is
      present; then evaluate its structural weight on Social Interaction's own scale.

      This clarification does not change the AFAO anchors, create benchmark-specific
      rules, or presume that a higher Social Interaction Emphasis score is preferable.
    TEXT

    FOCUSED_TASK_MARKER = "\n\n# Focused Assessment Task\n"

    def build(group_name:, adventure:, source_extraction:, dimensions: nil, levels_context: nil)
      prompt = super
      selected_dimensions = dimensions || DimensionGroups.fetch(group_name)
      return prompt unless selected_dimensions.include?("Social Interaction Emphasis")

      profile = ENV[PROFILE_ENV]
      return prompt if profile.nil? || profile.empty?

      unless profile == PROFILE
        raise ConfigurationError,
              "Unsupported Social Interaction guardrail profile #{profile.inspect}; expected #{PROFILE.inspect}"
      end

      unless prompt.input.include?(FOCUSED_TASK_MARKER)
        raise SpecificationError,
              "Unable to inject Social Interaction Phase-6 v0.3 guardrail: focused task marker not found"
      end

      prompt.input = prompt.input.sub(
        FOCUSED_TASK_MARKER,
        "\n\n#{TEXT}\n# Focused Assessment Task\n"
      )
      prompt
    end
  end

  PromptBuilder.prepend(Phase6SocialInteractionGuardrail)
end
