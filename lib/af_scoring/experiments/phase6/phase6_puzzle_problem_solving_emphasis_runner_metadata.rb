# frozen_string_literal: true

module AFScoring
  module Phase6PuzzleProblemSolvingEmphasisRunnerMetadata
    private

    def run_metadata_required?
      super || phase6_puzzle_problem_solving_profile_active?
    end

    def run_metadata(run_id:, adventure:, extraction:)
      metadata = super
      return metadata unless phase6_puzzle_problem_solving_profile_active?

      profile = "puzzle_guardrail_#{Phase6PuzzleProblemSolvingEmphasisGuardrail::PROFILE}"
      existing_profile = metadata["prompt_profile"]
      metadata["prompt_profile"] = if existing_profile.nil? || existing_profile == "experimental_group"
                                     profile
                                   else
                                     "#{existing_profile}+#{profile}"
                                   end
      metadata["experimental"] = true
      metadata["puzzle_guardrail_profile"] = Phase6PuzzleProblemSolvingEmphasisGuardrail::PROFILE
      metadata["puzzle_guardrail_sha256"] =
        Digest::SHA256.hexdigest(Phase6PuzzleProblemSolvingEmphasisGuardrail::TEXT)
      metadata
    end

    def phase6_puzzle_problem_solving_profile_active?
      ENV[Phase6PuzzleProblemSolvingEmphasisGuardrail::PROFILE_ENV] ==
        Phase6PuzzleProblemSolvingEmphasisGuardrail::PROFILE
    end
  end

  Runner.prepend(Phase6PuzzleProblemSolvingEmphasisRunnerMetadata)
end
