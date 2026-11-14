# frozen_string_literal: true
require_relative "test_helper"
require "json"

class RequestProvenanceTest < Minitest::Test
  FakeResponse = Struct.new(:output_text) do
    def to_h
      { "output_text" => output_text }
    end
  end

  class FakeResponses
    attr_reader :last_args

    def create(**args)
      @last_args = args
      FakeResponse.new(JSON.generate(TestSupport.scored_group_payload("gm_demands")))
    end
  end

  FakeClient = Struct.new(:responses)

  def setup
    @prompt = AFScoring::PromptBuilder::Prompt.new(
      instructions: "system rules",
      input: "full source and focused task"
    )
    @schema = AFScoring::SchemaBuilder.for_group("gm_demands")
  end

  def test_ollama_artifact_is_the_same_payload_sent_to_transport
    captured = {}
    provider = AFScoring::Providers::OllamaProvider.new(
      model: "qwen-test",
      reasoning_effort: "high",
      base_url: "http://127.0.0.1:11434/",
      transport: lambda do |uri, payload|
        captured[:uri] = uri.to_s
        captured[:payload] = JSON.parse(JSON.generate(payload))
        {
          "choices" => [
            {
              "message" => {
                "role" => "assistant",
                "content" => JSON.generate(TestSupport.scored_group_payload("gm_demands")),
                "reasoning" => "preserved reasoning"
              }
            }
          ]
        }
      end
    )

    artifact = provider.request_artifact(group_name: "gm_demands", prompt: @prompt, schema: @schema)
    provider.score(group_name: "gm_demands", prompt: @prompt, schema: @schema)

    assert_equal "ollama", artifact["provider"]
    assert_equal "http_post", artifact.dig("transport", "kind")
    assert_equal captured[:uri], artifact.dig("transport", "endpoint")
    assert_equal captured[:payload], artifact["payload"]
    assert_equal "system rules", artifact.dig("payload", "messages", 0, "content")
    assert_equal "full source and focused task", artifact.dig("payload", "messages", 1, "content")
    assert_equal @schema, artifact.dig("payload", "response_format", "json_schema", "schema")
  end

  def test_openai_artifact_is_the_same_argument_hash_sent_to_sdk
    responses = FakeResponses.new
    provider = AFScoring::Providers::OpenAIProvider.new(
      model: "gpt-test",
      reasoning_effort: "high",
      client: FakeClient.new(responses)
    )

    artifact = provider.request_artifact(group_name: "gm_demands", prompt: @prompt, schema: @schema)
    provider.score(group_name: "gm_demands", prompt: @prompt, schema: @schema)

    assert_equal "openai", artifact["provider"]
    assert_equal "responses.create", artifact.dig("transport", "operation")
    assert_equal JSON.parse(JSON.generate(responses.last_args)), artifact["payload"]
  end

  def test_writer_records_request_hashes_and_exact_request
    request = {
      "provider" => "ollama",
      "transport" => {
        "kind" => "http_post",
        "endpoint" => "http://127.0.0.1:11434/v1/chat/completions"
      },
      "payload" => {
        "model" => "qwen-test",
        "messages" => [
          { "role" => "system", "content" => "rules" },
          { "role" => "user", "content" => "source" }
        ],
        "response_format" => { "type" => "json_schema", "schema" => @schema }
      }
    }

    Dir.mktmpdir do |dir|
      path = AFScoring::CsvWriter.new(dir).write_request(
        adventure_id: "ADV-0001",
        run_id: "run",
        group_name: "dimension_gm_preparation_burden",
        request: request,
        prompt_sha256: "a" * 64,
        schema_sha256: "b" * 64
      )

      payload = JSON.parse(File.read(path))
      assert_equal "provider_request", payload["record_type"]
      assert_equal true, payload["recorded_before_inference"]
      assert_equal "a" * 64, payload["prompt_sha256"]
      assert_equal "b" * 64, payload["schema_sha256"]
      assert_equal 64, payload["request_sha256"].length
      assert_equal request, payload["request"]
      assert_match %r{/raw/ADV-0001/run/dimension_gm_preparation_burden_request\.json\z}, path
    end
  end

  def test_base_fallback_keeps_custom_providers_provenance_capable
    provider = TestSupport::FakeProvider.new
    artifact = provider.request_artifact(group_name: "gm_demands", prompt: @prompt, schema: @schema)

    assert_equal "fake", artifact["provider"]
    assert_equal "provider_score", artifact.dig("transport", "kind")
    assert_equal "fake-model", artifact.dig("payload", "model")
    assert_equal "system rules", artifact.dig("payload", "instructions")
    assert_equal "full source and focused task", artifact.dig("payload", "input")
    assert_equal @schema, artifact.dig("payload", "schema")
  end
end
