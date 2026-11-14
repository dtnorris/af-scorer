# frozen_string_literal: true

module AFScoring
  module Phase6PuzzleProblemSolvingEmphasisGuardrail
    PROFILE_ENV = "AF_PUZZLE_GUARDRAIL_PROFILE"
    PROFILE = "phase6-v0.2"

    TEXT = <<~TEXT.freeze
      # Puzzle / Problem-Solving Emphasis Low-Anchor Admission Guardrail v0.2

      This Phase-6 experimental clarification applies only to the Minimal ↔ Low
      (1 ↔ 2) boundary. It does not alter the frozen AFAO anchors, the existing
      production v0.1 exclusion audit, or any 2 ↔ 3, 3 ↔ 4, or 4 ↔ 5 decision.

      # Admission Test — Meaningful How-Problem, Not Independent Puzzle Mode

      After applying the existing v0.1 exclusion audit, identify the strongest
      remaining authored noncombat problem, mechanism, constraint, resource tradeoff,
      or supported obstacle. Ask whether players still have a substantive
      player-facing question of **how to overcome it** through reasoning,
      experimentation, combining information or resources, or selecting/devising a
      supported creative approach.

      If such a substantive how-problem remains, score 2 must remain available even
      when that qualifying play is:
      - localized rather than recurring;
      - optional or path-sensitive rather than mandatory;
      - short rather than sustained;
      - clearly secondary to another play mode;
      - intertwined with exploration, social interaction, investigation, or another
        dimension;
      - partly signposted rather than opaque;
      - resolved with one or more checks as part of the broader authored problem; or
      - not independently responsible for major canonical progression.

      None of those properties is a standalone reason to assign score 1. They bear on
      extent, recurrence, or higher-anchor weight; they do not erase otherwise
      meaningful Low-level problem-solving.

      Do not require a formal riddle, logic puzzle, complex mechanism, long solution
      sequence, multiple independent steps, multiple valid solutions, high difficulty,
      or a mode-pure "puzzle encounter" before score 2 becomes available.

      # Preserve Minimal — A How-Problem Must Actually Remain

      This clarification is not a general upward instruction. Preserve score 1 when
      the strongest candidate reduces to:
      - a check that directly resolves the obstacle with no substantive player-facing
        how-question;
      - merely finding or noticing a hidden feature;
      - using a known key, item, mechanism, password, or explicitly supplied procedure
        exactly as instructed;
      - an obvious trigger or prescribed action that leaves no meaningful reasoning,
        experimentation, resource combination, or supported creative choice;
      - ordinary route selection, searching, or environmental interaction;
      - generic player cleverness or GM-permitted improvisation unsupported by an
        authored problem or constraint; or
      - combat tactics rather than a substantive noncombat how-problem.

      Duration remains evidence. Material that is both rapidly resolved and too slight
      to constitute meaningful player-facing problem-solving can remain score 1.
      "Short," "localized," or "rapidly resolved" must not, however, become automatic
      vetoes when the authored problem itself still requires meaningful how-reasoning.

      # 1 ↔ 2 Adjacent-Anchor Falsification

      For the strongest candidate unit, perform the decision in this order:

      1. Remove any direct prescribed resolution that simply tells players what to do.
      2. State the player-facing how-question, if one remains.
      3. Identify what players must reason through, experiment with, combine, allocate,
         choose among, or creatively devise within the authored constraint.
      4. If that remaining work is meaningful but limited or secondary, score 2
         remains available; do not demand recurrence or independent structural weight.
      5. If no substantive how-question remains, preserve score 1.

      Do not decide 1 ↔ 2 by asking whether Puzzle / Problem-Solving is a recurring,
      independently important, or dominant mode. Those are higher-ladder questions.

      This clarification is benchmark-blind and presumes neither a higher nor a lower
      result. It changes only the admission calibration at the frozen 1 ↔ 2 boundary.
    TEXT

    FOCUSED_TASK_MARKER = "\n\n# Focused Assessment Task\n"

    def build(group_name:, adventure:, source_extraction:, dimensions: nil, levels_context: nil)
      prompt = super
      selected_dimensions = dimensions || DimensionGroups.fetch(group_name)
      return prompt unless selected_dimensions.include?("Puzzle / Problem-Solving Emphasis")

      profile = ENV[PROFILE_ENV]
      return prompt if profile.nil? || profile.empty?

      unless profile == PROFILE
        raise ConfigurationError,
              "Unsupported Puzzle / Problem-Solving Emphasis guardrail profile #{profile.inspect}; expected #{PROFILE.inspect}"
      end

      unless prompt.input.include?(FOCUSED_TASK_MARKER)
        raise SpecificationError,
              "Unable to inject Puzzle / Problem-Solving Phase-6 v0.2 guardrail: focused task marker not found"
      end

      prompt.input = prompt.input.sub(
        FOCUSED_TASK_MARKER,
        "\n\n#{TEXT}\n# Focused Assessment Task\n"
      )
      prompt
    end
  end

  PromptBuilder.prepend(Phase6PuzzleProblemSolvingEmphasisGuardrail)
end
