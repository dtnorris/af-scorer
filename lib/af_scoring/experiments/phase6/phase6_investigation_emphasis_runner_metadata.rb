# frozen_string_literal: true

module AFScoring
  module Phase6InvestigationEmphasisRunnerMetadata
    private

    def run_metadata_required?
      super || phase6_investigation_emphasis_profile_active?
    end

    def run_metadata(run_id:, adventure:, extraction:)
      metadata = super
      return metadata unless phase6_investigation_emphasis_profile_active?

      profile = "investigation_guardrail_#{Phase6InvestigationEmphasisGuardrail::PROFILE}"
      existing_profile = metadata["prompt_profile"]
      metadata["prompt_profile"] = if existing_profile.nil? || existing_profile == "experimental_group"
                                     profile
                                   else
                                     "#{existing_profile}+#{profile}"
                                   end
      metadata["experimental"] = true
      metadata["investigation_guardrail_profile"] = Phase6InvestigationEmphasisGuardrail::PROFILE
      metadata["investigation_guardrail_sha256"] =
        Digest::SHA256.hexdigest(Phase6InvestigationEmphasisGuardrail::TEXT)
      metadata
    end

    def phase6_investigation_emphasis_profile_active?
      ENV[Phase6InvestigationEmphasisGuardrail::PROFILE_ENV] == Phase6InvestigationEmphasisGuardrail::PROFILE
    end
  end

  Runner.prepend(Phase6InvestigationEmphasisRunnerMetadata)
end
