# frozen_string_literal: true

module AFScoring
  module Phase6SocialInteractionRunnerMetadata
    private

    def run_metadata_required?
      super || phase6_social_interaction_profile_active?
    end

    def run_metadata(run_id:, adventure:, extraction:)
      metadata = super
      return metadata unless phase6_social_interaction_profile_active?

      social_profile = "social_interaction_guardrail_#{Phase6SocialInteractionGuardrail::PROFILE}"
      metadata["prompt_profile"] = if combat_scoring?
                                     "combat_guardrail_v0.7.1+#{social_profile}"
                                   else
                                     social_profile
                                   end
      metadata["experimental"] = true
      metadata["social_interaction_guardrail_profile"] = Phase6SocialInteractionGuardrail::PROFILE
      metadata["social_interaction_guardrail_sha256"] =
        Digest::SHA256.hexdigest(Phase6SocialInteractionGuardrail::TEXT)
      metadata
    end

    def phase6_social_interaction_profile_active?
      ENV[Phase6SocialInteractionGuardrail::PROFILE_ENV] == Phase6SocialInteractionGuardrail::PROFILE
    end
  end

  Runner.prepend(Phase6SocialInteractionRunnerMetadata)
end
