# frozen_string_literal: true

require_relative "test_helper"
require "json"

class NosTwoStageRunnerTest < Minitest::Test
  class TwoStageFakeProvider < AFScoring::Providers::Base
    attr_reader :model, :calls

    def initialize(contaminated: false)
      @model = AFScoring::NosTwoStage::MODEL
      @contaminated = contaminated
      @calls = []
    end

    def score(group_name:, prompt:, schema:)
      @calls << { group_name: group_name, prompt: prompt, schema: schema }

      parsed = case group_name
               when AFScoring::NosTwoStage::STAGE1_GROUP
                 stage1_payload
               when AFScoring::NosTwoStage::STAGE2_GROUP
                 stage2_payload
               else
                 raise "unexpected fake-provider group #{group_name.inspect}"
               end

      AFScoring::Providers::ProviderResult.new(
        parsed: parsed,
        raw: { "fixture" => true, "group" => group_name }
      )
    end

    private

    def stage1_payload
      {
        "source_boundary_uncertainty" => false,
        "benchmark_contamination_detected" => @contaminated,
        "major_play_bodies" => [
          {
            "label" => "opening and investigation",
            "ordinary_presence" => "ordinary",
            "substantive_play" => "The source requires an opening followed by substantive investigation.",
            "evidence" => [{ "locator" => "PAGE: 1", "note" => "Opening and investigation are present." }]
          },
          {
            "label" => "resolution",
            "ordinary_presence" => "ordinary",
            "substantive_play" => "The source includes a substantive resolution body.",
            "evidence" => [{ "locator" => "PAGE: 2", "note" => "Resolution is present." }]
          }
        ],
        "repeated_play_cycles" => [],
        "optional_or_mutually_exclusive_material" => [],
        "explicit_bypass_or_compression_evidence" => [],
        "explicit_table_time_evidence" => [],
        "pacing_and_progression_constraints" => [],
        "coverage_summary" => "Two ordinary macro bodies are source-supported.",
        "source_grounding_notes" => "Fixture extraction uses source evidence only."
      }
    end

    def stage2_payload
      {
        "group" => "sessions_levels",
        "sessions" => {
          "assessment_state" => "Scored",
          "normalized_sessions" => 2,
          "practical_range_low" => 1,
          "practical_range_high" => 3,
          "confidence" => 85,
          "path_sensitive" => false,
          "rationale" => "The anonymized extracted structure reconciles to two normalized sessions.",
          "evidence" => [
            { "locator" => "PAGE: 1", "note" => "Opening and investigation body." },
            { "locator" => "PAGE: 2", "note" => "Resolution body." }
          ],
          "rubric_ambiguity" => false,
          "evidence_sufficient" => true
        },
        "group_observations" => {
          "source_boundary_uncertainty" => false,
          "possible_spec_contradiction" => false,
          "notes" => "Reconciled from anonymized Stage 1 structure only."
        }
      }
    end
  end

  def test_opt_in_factory_runs_two_stage_lifecycle_and_withholds_identity_from_stage2
    with_profile do
      Dir.mktmpdir do |dir|
        config = build_config(dir)
        provider = TwoStageFakeProvider.new
        runner = AFScoring::Runner.new(
          config: config,
          provider: provider,
          logger: ->(_message) {}
        )

        assert_instance_of AFScoring::NosTwoStageRunner, runner

        outcome = runner.score("ADV-0001")

        assert_equal 2, provider.calls.length
        assert_equal AFScoring::NosTwoStage::STAGE1_GROUP, provider.calls[0][:group_name]
        assert_equal AFScoring::NosTwoStage::STAGE2_GROUP, provider.calls[1][:group_name]

        stage1_input = provider.calls[0][:prompt].input
        stage2_input = provider.calls[1][:prompt].input
        refute_includes stage1_input, "ADV-0001"
        assert_includes stage1_input, "### Fixture Adventure"
        refute_includes stage1_input, "OUTSIDE-PRELUDE"
        refute_includes stage2_input, "ADV-0001"
        refute_includes stage2_input, "Fixture Adventure"
        refute_includes stage2_input, "RAW-SOURCE-SECRET"
        assert_includes stage2_input, "opening and investigation"

        assert_equal 1, outcome.package.metrics.length
        metric = outcome.package.metrics.first
        assert_equal "# of Sessions", metric.metric
        assert_equal 2, metric.value
        assert_nil outcome.regression_csv
        assert_empty outcome.comparisons

        metadata_path = outcome.raw_paths.find { |path| File.basename(path) == "run_metadata.json" }
        refute_nil metadata_path
        metadata = JSON.parse(File.read(metadata_path))
        assert_equal "nos_two_stage_nemotron-v0.1", metadata["prompt_profile"]
        assert_equal false, metadata["stage1_catalog_identity_supplied"]
        assert_equal false, metadata["stage2_catalog_identity_supplied"]
        assert_equal false, metadata["stage2_raw_source_supplied"]
        assert_equal false, metadata["paid_api_authorized"]
      end
    end
  end

  def test_stage1_benchmark_contamination_stops_before_stage2_call
    with_profile do
      Dir.mktmpdir do |dir|
        config = build_config(dir)
        provider = TwoStageFakeProvider.new(contaminated: true)
        runner = AFScoring::Runner.new(
          config: config,
          provider: provider,
          logger: ->(_message) {}
        )

        error = assert_raises(AFScoring::ValidationError) do
          runner.score("ADV-0001")
        end

        assert_includes error.failures.join(" "), "benchmark contamination"
        assert_equal 1, provider.calls.length
        assert_equal AFScoring::NosTwoStage::STAGE1_GROUP, provider.calls.first[:group_name]
      end
    end
  end

  def test_preflight_renders_exact_stage1_without_provider_calls
    with_profile do
      Dir.mktmpdir do |dir|
        config = build_config(dir)
        provider = TwoStageFakeProvider.new
        runner = AFScoring::Runner.new(
          config: config,
          provider: provider,
          logger: ->(_message) {}
        )

        outcome = runner.preflight("ADV-0001")

        assert_empty provider.calls
        assert_equal 1, outcome.targets.length
        target = outcome.targets.first
        assert_equal AFScoring::NosTwoStage::STAGE1_GROUP, target.group_name
        refute_includes target.prompt.input, "ADV-0001"
        assert_includes target.prompt.input, "### Fixture Adventure"
        refute_includes target.prompt.input, "OUTSIDE-PRELUDE"
        assert_includes target.prompt.input, "RAW-SOURCE-SECRET"
        assert_equal "stage1_exact_stage2_dynamic", outcome.run_metadata["preflight_scope"]
        assert_equal 0, outcome.run_metadata["provider_inference_calls"]
      end
    end
  end

  def test_profile_rejects_paid_provider_or_wrong_model_before_inference
    with_profile do
      Dir.mktmpdir do |dir|
        openai_config = build_config(
          dir,
          llm_overrides: { "provider" => "openai", "model" => AFScoring::NosTwoStage::MODEL }
        )
        assert_raises(AFScoring::ConfigurationError) do
          AFScoring::Runner.new(config: openai_config, logger: ->(_message) {})
        end
      end

      Dir.mktmpdir do |dir|
        wrong_model_config = build_config(
          dir,
          llm_overrides: { "provider" => "ollama", "model" => "other-local-model" }
        )
        assert_raises(AFScoring::ConfigurationError) do
          AFScoring::Runner.new(config: wrong_model_config, logger: ->(_message) {})
        end
      end
    end
  end

  private

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

  def build_config(dir, llm_overrides: nil)
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

    llm = {
      "provider" => "ollama",
      "model" => AFScoring::NosTwoStage::MODEL,
      "reasoning_effort" => "high",
      "ollama_base_url" => "http://127.0.0.1:11434"
    }.merge(llm_overrides || {})

    AFScoring::Config.new(
      project_root: File.expand_path("..", __dir__),
      config_path: custom,
      overrides: {
        "scoring" => { "dimension" => "# of Sessions" },
        "llm" => llm
      }
    )
  end
end
