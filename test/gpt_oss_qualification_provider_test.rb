# frozen_string_literal: true

require_relative "test_helper"

class GptOssQualificationProviderTest < Minitest::Test
  Prompt = Struct.new(:instructions, :input)

  def test_frozen_profile
    profile = AFScoring::GptOssQualificationProfile

    assert_equal "gpt-oss-20b-qualification-v0.1", profile::NAME
    assert_equal "gpt-oss:20b", profile::MODEL
    assert_equal "low", profile::REASONING_EFFORT
    assert_equal 16_384, profile::MAX_TOKENS
    assert_equal 1.0, profile::TEMPERATURE
    assert_equal 1.0, profile::TOP_P
    assert_equal 42, profile::SEED
  end

  def test_request_uses_frozen_gpt_oss_parameters
    provider = AFScoring::GptOssQualificationOllamaProvider.new
    prompt = Prompt.new("system instructions", "user input")
    schema = {
      "type" => "object",
      "properties" => {},
      "additionalProperties" => false
    }

    artifact = provider.request_artifact(
      group_name: "test",
      prompt: prompt,
      schema: schema
    )

    payload = artifact.fetch("payload")

    assert_equal "gpt-oss:20b", payload.fetch("model")
    assert_equal "low", payload.fetch("reasoning_effort")
    assert_equal 16_384, payload.fetch("max_tokens")
    assert_equal 1.0, payload.fetch("temperature")
    assert_equal 1.0, payload.fetch("top_p")
    assert_equal 42, payload.fetch("seed")
    assert_equal false, payload.fetch("stream")
  end

  def test_af_llm_provider_environment_selects_frozen_gpt_oss_provider
    previous_provider = ENV["AF_LLM_PROVIDER"]
    ENV["AF_LLM_PROVIDER"] = "gpt_oss_qualification"

    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "config"))
      File.write(
        File.join(dir, "config", "default.yml"),
        {
          "llm" => {
            "provider" => "ollama",
            "ollama_base_url" => "http://127.0.0.1:11434"
          },
          "paths" => {}
        }.to_yaml
      )

      config = AFScoring::Config.new(project_root: dir)
      runner = AFScoring::Runner.allocate
      runner.instance_variable_set(:@config, config)

      provider = runner.send(:build_provider)

      assert_equal "gpt_oss_qualification", config.dig("llm", "provider")
      assert_instance_of AFScoring::GptOssQualificationOllamaProvider, provider
      assert_equal AFScoring::GptOssQualificationProfile::MODEL, provider.model
      assert_equal AFScoring::GptOssQualificationProfile::MAX_TOKENS, provider.max_tokens
    end
  ensure
    previous_provider.nil? ? ENV.delete("AF_LLM_PROVIDER") : ENV["AF_LLM_PROVIDER"] = previous_provider
  end
end
