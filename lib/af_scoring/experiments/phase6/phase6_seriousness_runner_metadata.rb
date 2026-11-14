# frozen_string_literal: true

module AFScoring
  module Phase6SeriousnessRunnerMetadata
    private

    def run_metadata_required?
      super || phase6_seriousness_profile_active?
    end

    def run_metadata(run_id:, adventure:, extraction:)
      metadata = super
      return metadata unless phase6_seriousness_profile_active?

      profile = "seriousness_guardrail_#{Phase6SeriousnessGuardrail::PROFILE}"
      existing_profile = metadata["prompt_profile"]
      metadata["prompt_profile"] = if existing_profile.nil? || existing_profile == "experimental_group"
                                     profile
                                   else
                                     "#{existing_profile}+#{profile}"
                                   end
      metadata["experimental"] = true
      metadata["seriousness_guardrail_profile"] = Phase6SeriousnessGuardrail::PROFILE
      metadata["seriousness_guardrail_sha256"] =
        Digest::SHA256.hexdigest(Phase6SeriousnessGuardrail::TEXT)
      metadata
    end

    def phase6_seriousness_profile_active?
      ENV[Phase6SeriousnessGuardrail::PROFILE_ENV] == Phase6SeriousnessGuardrail::PROFILE
    end
  end

  Runner.prepend(Phase6SeriousnessRunnerMetadata)
end
