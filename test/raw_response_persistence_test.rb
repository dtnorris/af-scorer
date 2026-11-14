# frozen_string_literal: true

require_relative "test_helper"
require "json"

class RawResponsePersistenceTest < Minitest::Test
  def test_ollama_provider_yields_raw_before_missing_assistant_content_error
    provider_raw = { "choices" => [], "fixture" => "missing assistant content" }
    provider = AFScoring::Providers::OllamaProvider.new(
      model: "qwen-test",
      transport: ->(_uri, _payload) { provider_raw }
    )
    prompt = AFScoring::PromptBuilder::Prompt.new(instructions: "rules", input: "source")
    yielded_raw = nil

    error = assert_raises(AFScoring::ProviderError) do
      provider.score(
        group_name: "gm_demands",
        prompt: prompt,
        schema: AFScoring::SchemaBuilder.for_group("gm_demands")
      ) { |raw| yielded_raw = raw }
    end

    assert_same provider_raw, yielded_raw
    assert_match(/did not contain assistant content/, error.message)
  end

  def test_ollama_provider_yields_raw_before_completion_exhaustion_error
    provider_raw = {
      "choices" => [
        {
          "finish_reason" => "length",
          "message" => {
            "role" => "assistant",
            "content" => ""
          }
        }
      ],
      "fixture" => "completion exhaustion"
    }
    provider = AFScoring::Providers::OllamaProvider.new(
      model: "gpt-oss:20b",
      max_tokens: 16_384,
      transport: ->(_uri, _payload) { provider_raw }
    )
    prompt = AFScoring::PromptBuilder::Prompt.new(instructions: "rules", input: "source")
    yielded_raw = nil

    error = assert_raises(AFScoring::ProviderError) do
      provider.score(
        group_name: "play_mix",
        prompt: prompt,
        schema: AFScoring::SchemaBuilder.for_group("play_mix")
      ) { |response| yielded_raw = response }
    end

    assert_same provider_raw, yielded_raw
    assert_match(/exhausted max_tokens=16384/, error.message)
  end

  def test_runner_persists_raw_before_malformed_content_error
    with_no_profile do
      Dir.mktmpdir do |dir|
        config = build_config(dir, dimension: "Combat Emphasis", model: "qwen-test")
        provider_raw = completion_with_content(
          "{\"group\": \"play_mix\", \"dimensions\": ["
        ).merge("fixture" => "malformed direct content")
        provider = AFScoring::Providers::OllamaProvider.new(
          model: "qwen-test",
          transport: ->(_uri, _payload) { provider_raw }
        )
        runner = AFScoring::Runner.new(
          config: config,
          provider: provider,
          logger: ->(_message) {}
        )

        error = assert_raises(AFScoring::ProviderError) do
          runner.score("ADV-0001")
        end

        assert_match(/non-JSON structured output for play_mix/, error.message)
        raw_files = Dir.glob(
          File.join(
            dir,
            "output",
            "raw",
            "ADV-0001",
            "*",
            "dimension_combat_emphasis.json"
          )
        )
        assert_equal 1, raw_files.length
        assert_equal provider_raw, JSON.parse(File.read(raw_files.first))
      end
    end
  end

  def test_two_stage_runner_persists_stage2_raw_before_malformed_content_error
    with_profile do
      Dir.mktmpdir do |dir|
        config = build_config(dir)
        stage1_raw = completion_with_content(JSON.generate(stage1_payload))
        stage2_raw = completion_with_content(
          "{\"group\": \"sessions_levels\", \"sessions\": {"
        ).merge("fixture" => "malformed Stage 2 content")
        responses = [stage1_raw, stage2_raw]
        provider = AFScoring::Providers::OllamaProvider.new(
          model: AFScoring::NosTwoStage::MODEL,
          transport: ->(_uri, _payload) { responses.shift || raise("unexpected provider call") }
        )
        runner = AFScoring::Runner.new(
          config: config,
          provider: provider,
          logger: ->(_message) {}
        )

        error = assert_raises(AFScoring::ProviderError) do
          runner.score("ADV-0001")
        end

        assert_match(/non-JSON structured output for nos_duration_reconciliation/, error.message)
        raw_files = Dir.glob(
          File.join(
            dir,
            "output",
            "raw",
            "ADV-0001",
            "*",
            "#{AFScoring::NosTwoStage::STAGE2_GROUP}.json"
          )
        )
        assert_equal 1, raw_files.length
        assert_equal stage2_raw, JSON.parse(File.read(raw_files.first))
      end
    end
  end

  private

  def completion_with_content(content)
    {
      "choices" => [
        {
          "message" => {
            "role" => "assistant",
            "content" => content
          }
        }
      ]
    }
  end

  def stage1_payload
    {
      "source_boundary_uncertainty" => false,
      "benchmark_contamination_detected" => false,
      "major_play_bodies" => [
        {
          "label" => "opening and resolution",
          "ordinary_presence" => "ordinary",
          "substantive_play" => "The source contains one bounded ordinary play body.",
          "evidence" => [
            { "locator" => "PAGE: 1", "note" => "Opening evidence." }
          ]
        }
      ],
      "repeated_play_cycles" => [],
      "optional_or_mutually_exclusive_material" => [],
      "explicit_bypass_or_compression_evidence" => [],
      "explicit_table_time_evidence" => [],
      "pacing_and_progression_constraints" => [],
      "coverage_summary" => "One bounded ordinary play body.",
      "source_grounding_notes" => "Fixture extraction uses source evidence only."
    }
  end

  def with_no_profile
    previous = ENV.delete(AFScoring::NosTwoStage::PROFILE_ENV)
    yield
  ensure
    ENV[AFScoring::NosTwoStage::PROFILE_ENV] = previous if previous
  end

  def with_profile
    previous = ENV[AFScoring::NosTwoStage::PROFILE_ENV]
    ENV[AFScoring::NosTwoStage::PROFILE_ENV] = AFScoring::NosTwoStage::PROFILE
    yield
  ensure
    if previous.nil?
      ENV.delete(AFScoring::NosTwoStage::PROFILE_ENV)
    else
      ENV[AFScoring::NosTwoStage::PROFILE_ENV] = previous
    end
  end

  def build_config(dir, dimension: "# of Sessions", model: AFScoring::NosTwoStage::MODEL)
    xlsx_root = File.join(dir, "xlsx")
    spec_root = File.join(dir, "spec")
    source_root = File.join(dir, "source")
    output_root = File.join(dir, "output")
    [xlsx_root, spec_root, source_root].each { |path| FileUtils.mkdir_p(path) }

    TestSupport.build_xlsx(
      File.join(xlsx_root, "5e_Adventure_Master_Catalog_2.1.xlsx"),
      sheet_name: "Adventure Catalog",
      rows: [
        ["Adventure ID", "Adventure Title", "Page Count", "Source Book", "Book Publisher", "Start Page", "End Page"],
        ["ADV-0001", "Fixture Adventure", 2, "Fixture Book", "Fixture Publisher", 1, 2]
      ]
    )
    TestSupport.build_xlsx(
      File.join(xlsx_root, "AFAO_1.0_Referenced_ADVs v1.xlsx"),
      sheet_name: "AFAO 1.0 ADV References",
      rows: [
        ["Adventure ID", "Adventure Title", "AFAO Reference Count"],
        ["ADV-0001", "Fixture Adventure", 20]
      ]
    )
    File.write(
      File.join(spec_root, "AdventureFinder_Analysis_Ontology_v1.0.md"),
      TestSupport.minimal_afao
    )
    File.write(
      File.join(spec_root, "AdventureFinder_Analysis_Data_Assessment_Specification_v0.1.md"),
      TestSupport.minimal_assessment_spec
    )
    File.write(
      File.join(source_root, "Fixture_Book.md"),
      "<!-- PAGE: 1 -->\nOUTSIDE-PRELUDE\n### Fixture Adventure\nRAW-SOURCE-SECRET opening\n<!-- PAGE: 2 -->\nresolution\n<!-- PAGE: 3 -->\noutside\n"
    )
    File.write(
      File.join(source_root, "source_registry.yml"),
      {
        "schema_version" => AFScoring::SourceResolver::REGISTRY_SCHEMA_VERSION,
        "sources" => { "Fixture Book" => { "file" => "Fixture_Book.md" } }
      }.to_yaml
    )

    custom = File.join(dir, "config.yml")
    File.write(custom, {
      "method" => { "identity" => "configured" },
      "paths" => {
        "xlsx_root" => xlsx_root,
        "specification_root" => spec_root,
        "source_root" => source_root,
        "output_root" => output_root
      },
      "files" => {
        "catalog" => "5e_Adventure_Master_Catalog_2.1.xlsx",
        "regression_workbook" => "AFAO_1.0_Referenced_ADVs v1.xlsx",
        "afao" => "AdventureFinder_Analysis_Ontology_v1.0.md",
        "assessment_spec" => "AdventureFinder_Analysis_Data_Assessment_Specification_v0.1.md",
        "source_registry" => "source_registry.yml"
      }
    }.to_yaml)

    AFScoring::Config.new(
      project_root: File.expand_path("..", __dir__),
      config_path: custom,
      overrides: {
        "scoring" => { "dimension" => dimension },
        "llm" => {
          "provider" => "ollama",
          "model" => model,
          "reasoning_effort" => "high",
          "ollama_base_url" => "http://127.0.0.1:11434"
        }
      }
    )
  end
end
