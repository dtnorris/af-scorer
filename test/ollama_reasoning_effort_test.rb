# frozen_string_literal: true

require_relative "test_helper"

class OllamaReasoningEffortTest < Minitest::Test
  Prompt = Struct.new(:instructions, :input)

  SCHEMA = { "type" => "object" }.freeze

  def test_request_preserves_reasoning_effort_for_thinking_models
    provider = AFScoring::Providers::OllamaProvider.new(
      model: "fixture-thinking-model",
      reasoning_effort: "low"
    )

    artifact = provider.request_artifact(
      group_name: "fixture",
      prompt: Prompt.new("system", "user"),
      schema: SCHEMA
    )

    assert_equal "low", artifact.dig("payload", "reasoning_effort")
  end

  def test_request_omits_reasoning_effort_when_configured_none
    provider = AFScoring::Providers::OllamaProvider.new(
      model: "fixture-non-thinking-model",
      reasoning_effort: "none"
    )

    artifact = provider.request_artifact(
      group_name: "fixture",
      prompt: Prompt.new("system", "user"),
      schema: SCHEMA
    )

    refute artifact.fetch("payload").key?("reasoning_effort")
  end

  def test_score_omits_reasoning_effort_when_configured_none
    seen_payload = nil
    transport = lambda do |_uri, payload|
      seen_payload = payload
      {
        "choices" => [
          { "message" => { "content" => "{}" } }
        ]
      }
    end

    provider = AFScoring::Providers::OllamaProvider.new(
      model: "fixture-non-thinking-model",
      reasoning_effort: "none",
      transport: transport
    )

    provider.score(
      group_name: "fixture",
      prompt: Prompt.new("system", "user"),
      schema: SCHEMA
    )

    refute seen_payload.key?(:reasoning_effort)
  end
end
