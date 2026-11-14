# frozen_string_literal: true

module AFScoring
  module TacticalComplexityMorphologyEquivalenceGuardrail
    TEXT = <<~TEXT.freeze
      # Tactical Complexity 4 ↔ 5 Direct Decision-Load Guardrail v0.4

      Apply this clarification only after the ordinary AFAO analysis has independently
      established score 4. It is inert for the 1 ↔ 2, 2 ↔ 3, and 3 ↔ 4 boundaries and
      supplies no evidence for reaching score 4. Do not use it to raise a lower-ladder
      candidate.

      # Direct 4 ↔ 5 Adjudication Rule

      Do not infer Tactical Complexity from structural exceptionalism. A score-5 candidate
      does not need multiple objectives, unpredictable state, majority table-time coverage,
      continuous peak density, or adventure-wide prevalence. Those are not AFAO criteria.
      Compare 4 and 5 directly by the density, coupling, substantive weight, and repeated
      tactical reprioritization of the live decision problem.

      Accordingly, do not deny score 5 merely because most, ordinary, or characteristic
      play is simpler; because a distributed qualifying sequence is not itself dominant;
      because the overall objective is single, clear, or stable; because relevant state
      changes are predictable; because simpler play intervenes; because qualifying play
      occurs in one keyed encounter or location; or because multiple simultaneous
      objectives are absent. None of those is an independent ceiling when live tactical
      factors remain coupled and changing state repeatedly alters what players should do
      next.

      # Preserve the Two Equivalent Score-5 Routes

      Score 5 can arise through either of the AFAO's alternative upper-end morphologies:

      - Route A — multiple substantively major encounters or encounter sequences that
        sustain dense coupled tactical pressure and repeated tactical reprioritization.
      - Route B — one dominant sustained mandatory encounter sequence that sustains dense
        coupled tactical pressure and repeated tactical reprioritization.

      Either route is sufficient. Do not import Route-B continuity, dominance, or coverage
      requirements into Route A, and do not require Route A merely because Route B is
      absent. Simpler play before, between, or after qualifying material does not by itself
      cap the score.

      # Short Anti-Inflation Counter-Test

      Stay at score 4 when the relevant factors are mostly stable or separable; when the
      strongest dense pressure is rare, optional, or insufficiently weighted in expected
      play; or when the apparent complexity mainly changes what happens between scenes or
      encounters rather than the live encounter-time decision problem. Encounter count,
      difficulty, spectacle, lethality, rules density, or the mere presence of several
      tactical considerations does not establish score 5.

      At adjacent-anchor falsification, identify the live factors, determine whether
      changes on one axis repeatedly alter priorities on others, and judge their
      substantive weight under Route A or Route B. If either route is supported, do not
      reject score 5 using any structural proxy forbidden above.
    TEXT

    FOCUSED_TASK_MARKER = "\n\n# Focused Assessment Task\n"

    def build(group_name:, adventure:, source_extraction:, dimensions: nil, levels_context: nil)
      prompt = super
      selected_dimensions = dimensions || DimensionGroups.fetch(group_name)
      return prompt unless selected_dimensions.include?("Tactical Complexity")

      unless prompt.input.include?(FOCUSED_TASK_MARKER)
        raise SpecificationError, "Unable to inject Tactical Complexity v0.4 guardrail: focused task marker not found"
      end

      prompt.input = prompt.input.sub(
        FOCUSED_TASK_MARKER,
        "\n\n#{TEXT}\n# Focused Assessment Task\n"
      )
      prompt
    end
  end

  PromptBuilder.prepend(TacticalComplexityMorphologyEquivalenceGuardrail)
end
