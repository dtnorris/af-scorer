# frozen_string_literal: true
require_relative "test_helper"

class LlmMaxTokensTest < Minitest::Test
  Prompt = Struct.new(:instructions, :input)

  def test_project_default_is_4096
    defaults = YAML.safe_load_file(File.expand_path("../config/default.yml", __dir__), aliases: true)
    assert_equal 4_096, defaults.dig("llm", "max_tokens")
  end

  def test_environment_can_override_configured_limit
    previous = ENV["AF_LLM_MAX_TOKENS"]
    ENV["AF_LLM_MAX_TOKENS"] = "8192"

    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "config"))
      File.write(
        File.join(dir, "config", "default.yml"),
        {
          "llm" => { "max_tokens" => 4_096 },
          "paths" => {}
        }.to_yaml
      )

      config = AFScoring::Config.new(project_root: dir)
      assert_equal "8192", config.dig("llm", "max_tokens")
    end
  ensure
    previous.nil? ? ENV.delete("AF_LLM_MAX_TOKENS") : ENV["AF_LLM_MAX_TOKENS"] = previous
  end

  def test_ollama_request_artifact_includes_default_limit
    provider = AFScoring::Providers::OllamaProvider.new(model: "fixture-model")
    artifact = provider.request_artifact(
      group_name: "fixture",
      prompt: Prompt.new("system", "user"),
      schema: { "type" => "object" }
    )

    assert_equal 4_096, provider.max_tokens
    assert_equal 4_096, artifact.dig("payload", "max_tokens")
  end

  def test_ollama_score_sends_configured_limit
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
      model: "fixture-model",
      max_tokens: "5096",
      transport: transport
    )
    provider.score(
      group_name: "fixture",
      prompt: Prompt.new("system", "user"),
      schema: { "type" => "object" }
    )

    assert_equal 5096, provider.max_tokens
    assert_equal 5096, seen_payload.fetch(:max_tokens)
  end

  def test_ollama_rejects_invalid_limits
    [0, -1, "not-a-number"].each do |value|
      assert_raises(AFScoring::ConfigurationError) do
        AFScoring::Providers::OllamaProvider.new(
          model: "fixture-model",
          max_tokens: value
        )
      end
    end
  end

  def test_runner_passes_configured_limit_to_ollama
    values = {
      "llm" => {
        "provider" => "ollama",
        "model" => "fixture-model",
        "reasoning_effort" => "high",
        "ollama_base_url" => "http://127.0.0.1:11434",
        "max_tokens" => 5096
      }
    }
    config = Object.new
    config.define_singleton_method(:dig) { |*keys| values.dig(*keys) }

    runner = AFScoring::Runner.allocate
    runner.instance_variable_set(:@config, config)
    provider = runner.send(:build_provider)

    assert_equal 5096, provider.max_tokens
  end
end
