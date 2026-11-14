# frozen_string_literal: true
require_relative "test_helper"
require "json"

class ProviderTest < Minitest::Test
  FakeResponse = Struct.new(:output_text) do
    def to_h
      { "output_text" => output_text }
    end
  end

  class FakeResponses
    attr_reader :last_args
    def create(**args)
      @last_args = args
      ProviderTest::FakeResponse.new(JSON.generate(TestSupport.scored_group_payload("gm_demands")))
    end
  end

  FakeClient = Struct.new(:responses)

  def test_openai_provider_uses_responses_and_structured_schema
    responses = FakeResponses.new
    provider = AFScoring::Providers::OpenAIProvider.new(
      model: "gpt-test",
      reasoning_effort: "high",
      client: FakeClient.new(responses)
    )
    prompt = AFScoring::PromptBuilder::Prompt.new(instructions: "rules", input: "source")
    result = provider.score(group_name: "gm_demands", prompt: prompt, schema: AFScoring::SchemaBuilder.for_group("gm_demands"))
    assert_equal "gm_demands", result.parsed["group"]
    assert_equal "gpt-test", responses.last_args[:model]
    assert_equal "json_schema", responses.last_args.dig(:text, :format, :type)
    assert_equal "high", responses.last_args.dig(:reasoning, :effort)
  end

  def test_ollama_provider_uses_openai_compatible_chat_completions_and_structured_schema
    captured = {}
    transport = lambda do |uri, payload|
      captured[:uri] = uri
      captured[:payload] = payload
      {
        "choices" => [
          {
            "message" => {
              "role" => "assistant",
              "content" => JSON.generate(TestSupport.scored_group_payload("gm_demands")),
              "reasoning" => "fixture reasoning"
            }
          }
        ]
      }
    end
    provider = AFScoring::Providers::OllamaProvider.new(
      model: "qwen-test",
      reasoning_effort: "high",
      base_url: "http://127.0.0.1:11434/",
      transport: transport
    )
    prompt = AFScoring::PromptBuilder::Prompt.new(instructions: "rules", input: "source")
    schema = AFScoring::SchemaBuilder.for_group("gm_demands")

    result = provider.score(group_name: "gm_demands", prompt: prompt, schema: schema)

    assert_equal "gm_demands", result.parsed["group"]
    assert_equal "ollama", provider.provider_name
    assert_equal "http://127.0.0.1:11434/v1/chat/completions", captured[:uri].to_s
    assert_equal "qwen-test", captured[:payload][:model]
    assert_equal "rules", captured[:payload].dig(:messages, 0, :content)
    assert_equal "source", captured[:payload].dig(:messages, 1, :content)
    assert_equal "high", captured[:payload][:reasoning_effort]
    assert_equal 0, captured[:payload][:temperature]
    assert_equal false, captured[:payload][:stream]
    assert_equal "json_schema", captured[:payload].dig(:response_format, :type)
    assert_equal schema, captured[:payload].dig(:response_format, :json_schema, :schema)
  end

  def test_ollama_provider_reports_completion_exhaustion_when_length_finish_has_no_content
    provider = AFScoring::Providers::OllamaProvider.new(
      model: "gpt-oss:20b",
      max_tokens: 16_384,
      transport: lambda do |_uri, _payload|
        {
          "choices" => [
            {
              "finish_reason" => "length",
              "message" => {
                "role" => "assistant",
                "content" => ""
              }
            }
          ]
        }
      end
    )
    prompt = AFScoring::PromptBuilder::Prompt.new(instructions: "rules", input: "source")

    error = assert_raises(AFScoring::ProviderError) do
      provider.score(
        group_name: "play_mix",
        prompt: prompt,
        schema: AFScoring::SchemaBuilder.for_group("play_mix")
      )
    end

    assert_match(/exhausted max_tokens=16384/, error.message)
    assert_match(/play_mix/, error.message)
    refute_match(/did not contain assistant content/, error.message)
  end

  def test_ollama_provider_rejects_missing_assistant_content
    provider = AFScoring::Providers::OllamaProvider.new(
      model: "qwen-test",
      transport: ->(_uri, _payload) { { "choices" => [] } }
    )
    prompt = AFScoring::PromptBuilder::Prompt.new(instructions: "rules", input: "source")

    error = assert_raises(AFScoring::ProviderError) do
      provider.score(
        group_name: "gm_demands",
        prompt: prompt,
        schema: AFScoring::SchemaBuilder.for_group("gm_demands")
      )
    end

    assert_match(/did not contain assistant content/, error.message)
  end
end
