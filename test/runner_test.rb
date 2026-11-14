# frozen_string_literal: true
require_relative "test_helper"
require "csv"
require "json"
require "stringio"

class RunnerTest < Minitest::Test
  def test_experimental_group_restricts_scoring_groups_and_metric_expectations
    runner = AFScoring::Runner.allocate
    runner.instance_variable_set(
      :@config,
      { "experimental" => { "group" => "play_mix" } }
    )

    assert_equal ["play_mix"], runner.send(:scoring_groups)
    assert_equal(
      AFScoring::DimensionGroups.fetch("play_mix"),
      runner.send(:expected_metric_names)
    )
  end

  def test_selected_dimension_restricts_scoring_to_one_target_and_metric
    runner = AFScoring::Runner.allocate
    runner.instance_variable_set(
      :@config,
      { "scoring" => { "dimension" => "Combat Emphasis" } }
    )

    targets = runner.send(:scoring_targets)
    assert_equal 1, targets.length
    assert_equal "play_mix", targets.first.group_name
    assert_equal ["Combat Emphasis"], targets.first.dimensions
    assert_equal ["Combat Emphasis"], runner.send(:expected_metric_names)
  end

  def test_levels_dimension_expects_both_level_metrics
    runner = AFScoring::Runner.allocate
    runner.instance_variable_set(
      :@config,
      { "scoring" => { "dimension" => "Levels" } }
    )

    assert_equal ["Level Start", "Level End"], runner.send(:expected_metric_names)
  end

  def test_dimension_and_experimental_group_are_mutually_exclusive
    runner = AFScoring::Runner.allocate
    runner.instance_variable_set(
      :@config,
      {
        "scoring" => { "dimension" => "Combat Emphasis" },
        "experimental" => { "group" => "play_mix" }
      }
    )

    assert_raises(AFScoring::SpecificationError) { runner.send(:scoring_targets) }
  end

  def test_default_scoring_groups_and_metric_expectations_remain_complete
    runner = AFScoring::Runner.allocate
    runner.instance_variable_set(:@config, {})

    assert_equal AFScoring::DimensionGroups::GROUPS.keys, runner.send(:scoring_groups)
    assert_equal AFScoring::Validator::EXPECTED_METRICS, runner.send(:expected_metric_names)
  end

  def test_default_scoring_splits_sessions_and_levels_into_independent_targets
    runner = AFScoring::Runner.allocate
    runner.instance_variable_set(:@config, {})

    targets = runner.send(:scoring_targets)

    assert_equal 8, targets.length
    assert_equal "sessions_levels", targets[0].group_name
    assert_equal ["# of Sessions"], targets[0].dimensions
    assert_equal "sessions_levels", targets[1].group_name
    assert_equal ["Levels"], targets[1].dimensions
  end

  def test_unknown_experimental_group_is_rejected
    runner = AFScoring::Runner.allocate
    runner.instance_variable_set(
      :@config,
      { "experimental" => { "group" => "not_a_group" } }
    )

    assert_raises(AFScoring::SpecificationError) { runner.send(:scoring_groups) }
  end

  def test_build_provider_supports_ollama_without_changing_openai_default
    runner = AFScoring::Runner.allocate
    runner.instance_variable_set(
      :@config,
      {
        "llm" => {
          "provider" => "ollama",
          "model" => "qwen3.6:35b-a3b",
          "reasoning_effort" => "high",
          "ollama_base_url" => "http://127.0.0.1:11434"
        }
      }
    )

    provider = runner.send(:build_provider)

    assert_instance_of AFScoring::Providers::OllamaProvider, provider
    assert_equal "qwen3.6:35b-a3b", provider.model
    assert_equal "http://127.0.0.1:11434", provider.base_url
  end

  def test_preflight_uses_production_source_prompt_and_schema_path_without_constructing_provider
    Dir.mktmpdir do |dir|
      xlsx_root = File.join(dir, "xlsx")
      spec_root = File.join(dir, "spec")
      source_root = File.join(dir, "source")
      output_root = File.join(dir, "output", "nested")
      [xlsx_root, spec_root, source_root].each { |d| FileUtils.mkdir_p(d) }

      TestSupport.build_xlsx(File.join(xlsx_root, "5e_Adventure_Master_Catalog_2.1.xlsx"), sheet_name: "Adventure Catalog", rows: [
        ["Adventure ID", "Adventure Title", "Page Count", "Source Book", "Book Publisher", "Start Page", "End Page"],
        ["ADV-0001", "Fixture Adventure", 2, "Fixture Book", "Fixture Publisher", 2, 3]
      ])
      TestSupport.build_xlsx(File.join(xlsx_root, "AFAO_1.0_Referenced_ADVs v1.xlsx"), sheet_name: "AFAO 1.0 ADV References", rows: [
        ["Adventure ID", "Adventure Title", "AFAO Reference Count"],
        ["ADV-0001", "Fixture Adventure", 20]
      ])
      File.write(File.join(spec_root, "AdventureFinder_Analysis_Ontology_v1.0.md"), TestSupport.minimal_afao)
      File.write(File.join(spec_root, "AdventureFinder_Analysis_Data_Assessment_Specification_v0.1.md"), TestSupport.minimal_assessment_spec)
      File.write(
        File.join(source_root, "Fixture_Hoard.md"),
        "<!-- PAGE: 1 -->\nCharacter Advancement: characters start at 1st level.\n" \
          "<!-- PAGE: 2 -->\nstart\n<!-- PAGE: 3 -->\nfinish\n<!-- PAGE: 4 -->\noutside\n"
      )
      File.write(
        File.join(source_root, "source_registry.yml"),
        {
          "schema_version" => AFScoring::SourceResolver::REGISTRY_SCHEMA_VERSION,
          "sources" => {
            "Fixture Book" => {
              "segments" => [
                { "start_page" => 1, "end_page" => 3, "file" => "Fixture_Hoard.md" }
              ]
            }
          }
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

      config = AFScoring::Config.new(
        project_root: File.expand_path("..", __dir__),
        config_path: custom,
        overrides: { "scoring" => { "dimension" => "Combat Emphasis" } }
      )
      no_provider_runner = Class.new(AFScoring::Runner) do
        private

        def build_provider
          raise "preflight must not construct a provider"
        end
      end
      runner = no_provider_runner.new(config: config, logger: ->(_message) {})

      outcome = runner.preflight("ADV-0001")

      assert_equal "ADV-0001", outcome.adventure.id
      assert_equal "canonical_page_slice", outcome.source_scope
      assert_equal File.expand_path(output_root), outcome.output_root
      assert_equal 1, outcome.targets.length
      target = outcome.targets.first
      assert_equal "play_mix", target.group_name
      assert_equal ["Combat Emphasis"], target.dimensions
      assert_kind_of Hash, target.schema
      assert_equal 64, target.prompt_sha256.length
      assert_equal 64, target.schema_sha256.length
      assert_includes target.prompt.input, "Fixture Adventure"
      assert_includes target.prompt.input, "start"
      assert_includes target.prompt.input, "finish"
      refute_includes target.prompt.input, "<!-- PAGE: 4 -->\noutside"
      assert_equal "combat_guardrail_v0.7.1", outcome.run_metadata["prompt_profile"]
      assert_equal "preflight", outcome.run_metadata["run_id"]

      prepared_source = runner.prepare_source("ADV-0001")
      cached_outcome = runner.preflight("ADV-0001", prepared_source: prepared_source)
      cli = AFScoring::CLI.new([], out: StringIO.new, err: StringIO.new)
      uncached_path = File.join(dir, "combat-uncached.json")
      cached_path = File.join(dir, "combat-cached.json")
      cli.send(:write_preflight_render, outcome, uncached_path)
      cli.send(:write_preflight_render, cached_outcome, cached_path)
      assert_equal File.binread(uncached_path), File.binread(cached_path)
      assert_equal Digest::SHA256.file(uncached_path).hexdigest, Digest::SHA256.file(cached_path).hexdigest

      levels_config = AFScoring::Config.new(
        project_root: File.expand_path("..", __dir__),
        config_path: custom,
        overrides: { "scoring" => { "dimension" => "Levels" } }
      )
      levels_runner = no_provider_runner.new(config: levels_config, logger: ->(_message) {})
      levels_uncached = levels_runner.preflight("ADV-0001")
      levels_cached = levels_runner.preflight("ADV-0001", prepared_source: prepared_source)
      levels_uncached_path = File.join(dir, "levels-uncached.json")
      levels_cached_path = File.join(dir, "levels-cached.json")
      cli.send(:write_preflight_render, levels_uncached, levels_uncached_path)
      cli.send(:write_preflight_render, levels_cached, levels_cached_path)
      assert_equal File.binread(levels_uncached_path), File.binread(levels_cached_path)
      assert_equal Digest::SHA256.file(levels_uncached_path).hexdigest, Digest::SHA256.file(levels_cached_path).hexdigest
      assert_includes levels_cached.targets.first.prompt.input, "characters start at 1st level"

      mismatched = Marshal.load(Marshal.dump(prepared_source))
      mismatched["source_policy"]["allow_full_source_fallback"] =
        !mismatched["source_policy"]["allow_full_source_fallback"]
      assert_raises(AFScoring::SourceResolutionError) do
        runner.preflight("ADV-0001", prepared_source: mismatched)
      end

      refute File.exist?(output_root), "preflight should validate output ancestry without creating score output directories"
    end
  end

  def test_end_to_end_with_mock_provider_and_blind_regression
    Dir.mktmpdir do |dir|
      xlsx_root = File.join(dir, "xlsx")
      spec_root = File.join(dir, "spec")
      source_root = File.join(dir, "source")
      output_root = File.join(dir, "output")
      [xlsx_root, spec_root, source_root].each { |d| FileUtils.mkdir_p(d) }

      TestSupport.build_xlsx(File.join(xlsx_root, "5e_Adventure_Master_Catalog_2.1.xlsx"), sheet_name: "Adventure Catalog", rows: [
        ["Adventure ID", "Adventure Title", "Page Count", "Source Book", "Book Publisher", "Start Page", "End Page"],
        ["ADV-0001", "Fixture Adventure", 2, "Fixture Book", "Fixture Publisher", 1, 2]
      ])
      TestSupport.build_xlsx(File.join(xlsx_root, "AFAO_1.0_Referenced_ADVs v1.xlsx"), sheet_name: "AFAO 1.0 ADV References", rows: [
        ["Adventure ID", "Adventure Title", "AFAO Reference Count"],
        ["ADV-0001", "Fixture Adventure", 20]
      ])
      File.write(File.join(spec_root, "AdventureFinder_Analysis_Ontology_v1.0.md"), TestSupport.minimal_afao)
      File.write(File.join(spec_root, "AdventureFinder_Analysis_Data_Assessment_Specification_v0.1.md"), TestSupport.minimal_assessment_spec)
      File.write(File.join(source_root, "Fixture_Book.md"), "<!-- PAGE: 1 -->\nstart\n<!-- PAGE: 2 -->\nfinish\n<!-- PAGE: 3 -->\noutside\n")
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

      config = AFScoring::Config.new(project_root: File.expand_path("..", __dir__), config_path: custom)
      provider = TestSupport::FakeProvider.new
      logs = []
      progress = AFScoring::Progress.new(io: StringIO.new, tty: false)
      runner = AFScoring::Runner.new(config: config, provider: provider, logger: ->(m) { logs << m }, progress: progress)
      TestSupport.bind_historical(config)
      outcome = runner.score("ADV-0001", regression: true)

      assert_equal 8, provider.calls.length
      assert_equal AFScoring::PromptBuilder::NOS_SYSTEM_INSTRUCTIONS,
        provider.calls[0][:prompt].instructions
      assert_equal AFScoring::PromptBuilder::SYSTEM_INSTRUCTIONS,
        provider.calls[1][:prompt].instructions
      assert_equal 20, outcome.package.metrics.length
      assert_equal "PROPOSED", outcome.package.status
      assert_equal "NO_AUTOMATIC_REVIEW_TRIGGER", outcome.package.review_disposition
      assert_equal 20, outcome.comparisons.length
      assert outcome.comparisons.all?(&:exact_match)
      assert File.file?(outcome.assessment_csv)
      assert File.file?(outcome.regression_csv)
      assert_equal 20, CSV.read(outcome.assessment_csv, headers: true).length

      metadata_path = outcome.raw_paths.find { |path| File.basename(path) == "run_metadata.json" }
      refute_nil metadata_path
      metadata = JSON.parse(File.read(metadata_path))
      assert_equal "combat_guardrail_v0.7.1", metadata["prompt_profile"]
      assert_equal false, metadata["experimental"]
      assert_equal "de4d953e4ab8e1d46600946dfe67c9a1af677d35dd25b60d5a4cc8c6de952617",
        metadata["guardrail_sha256"]
    end
  end
end
