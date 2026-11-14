# frozen_string_literal: true

module AFScoring
  module GptOssQualificationProfile
    NAME = "gpt-oss-20b-qualification-v0.1"

    MODEL = "gpt-oss:20b"
    REASONING_EFFORT = "low"
    MAX_TOKENS = 16_384
    TEMPERATURE = 1.0
    TOP_P = 1.0
    SEED = 42
  end

  # Frozen GPT-OSS inference condition selected by local discriminator testing.
  #
  # This provider changes only model/inference parameters. Prompt construction,
  # source extraction, AFAO rubrics, structured-output schemas, normalization,
  # validation, and regression behavior remain those of the ordinary scorer.
  #
  # Model and generation parameters are intentionally not tunable here.
  class GptOssQualificationOllamaProvider < Providers::OllamaProvider
    def initialize(base_url: nil, transport: nil)
      super(
        model: GptOssQualificationProfile::MODEL,
        reasoning_effort: GptOssQualificationProfile::REASONING_EFFORT,
        base_url: base_url,
        max_tokens: GptOssQualificationProfile::MAX_TOKENS,
        transport: transport
      )
    end

    private

    def request_payload(group_name:, prompt:, schema:)
      super.merge(
        temperature: GptOssQualificationProfile::TEMPERATURE,
        top_p: GptOssQualificationProfile::TOP_P,
        seed: GptOssQualificationProfile::SEED
      )
    end
  end
end
