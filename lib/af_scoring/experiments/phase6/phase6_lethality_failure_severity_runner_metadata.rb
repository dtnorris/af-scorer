# frozen_string_literal: true

module AFScoring
  module Phase6LethalityFailureSeverityRunnerMetadata
    private

    def run_metadata_required?
      super || phase6_lethality_failure_severity_profile_active?
    end

    def run_metadata(run_id:, adventure:, extraction:)
      metadata = super
      return metadata unless phase6_lethality_failure_severity_profile_active?

      profile = "lethality_guardrail_#{Phase6LethalityFailureSeverityGuardrail::PROFILE}"
      existing_profile = metadata["prompt_profile"]
      metadata["prompt_profile"] = if existing_profile.nil? || existing_profile == "experimental_group"
                                     profile
                                   else
                                     "#{existing_profile}+#{profile}"
                                   end
      metadata["experimental"] = true
      metadata["lethality_guardrail_profile"] = Phase6LethalityFailureSeverityGuardrail::PROFILE
      metadata["lethality_guardrail_sha256"] =
        Digest::SHA256.hexdigest(Phase6LethalityFailureSeverityGuardrail::TEXT)
      metadata
    end

    def phase6_lethality_failure_severity_profile_active?
      ENV[Phase6LethalityFailureSeverityGuardrail::PROFILE_ENV] ==
        Phase6LethalityFailureSeverityGuardrail::PROFILE
    end
  end

  Runner.prepend(Phase6LethalityFailureSeverityRunnerMetadata)
end
