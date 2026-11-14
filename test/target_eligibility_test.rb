# frozen_string_literal: true

require_relative "test_helper"
require "csv"
require "json"

# Exercise library isolation through real catalog/source, CLI and proposal validators.
# Only external provider construction/execution is replaced, never owner validation.
class TargetEligibilityTest < Minitest::Test
  # Initialize two independent, content-free libraries with overlapping local IDs.
  # Filesystem/owner errors propagate; fixtures never use private adventure material.
  def setup
    @root = Dir.mktmpdir("target-eligibility")
    @configs = %w[1 2].map { |number| build_library(File.join(@root, number), number) }
    @provider_constructions = 0
  end

  # Delete only the private fixture created by setup; filesystem errors propagate.
  def teardown
    FileUtils.remove_entry(@root)
  end

  # Both directions and an unmatched ID retain ordinary validated proposals while no
  # local label selects a historical comparison or target-specific benchmark exclusion.
  def test_new_libraries_prepare_replay_and_score_without_inheriting_history
    @configs.each do |config|
      config.data["target_bindings"] = selection([])
      provider = TestSupport::FakeProvider.new
      runner = build_runner(config, provider)
      %w[ADV-0001 ADV-9999].each do |identifier|
        prepared = runner.prepare_source(identifier)
        direct = runner.preflight(identifier)
        replay = runner.preflight(identifier, prepared_source: prepared)
        assert_equal direct.targets.map(&:to_h), replay.targets.map(&:to_h)
        assert_equal "none", prepared.dig("target_eligibility", "calibration")
        direct.targets.each do |target|
          refute_match(/\*\*ADV-0001/, target.prompt.input)
          if target.dimensions.include?("Combat Emphasis")
            assert_includes target.prompt.input, "| **1 — Minimal** | minimal |"
            assert_includes target.prompt.input, "| **5 — Dominant** | dominant |"
          end
        end
        outcome = runner.score(identifier, regression: true)
        assert_equal 20, outcome.package.metrics.length
        assert_empty outcome.comparisons
        assert_nil outcome.regression_csv
        assert_includes outcome.package.package_review_flags, "REVIEW:NO_REGRESSION_EXPECTATIONS"
        assert_equal 20, CSV.read(outcome.assessment_csv, headers: true).length
        assert_cli_prepare(config, identifier)
      end
      bind(config, "ADV-0001", calibration: "none")
      assert_empty build_runner(config, provider).score("ADV-0001", regression: true).comparisons
      assert_equal 24, provider.calls.length
    end
  end

  # Historical expectations remain AFAO-owned after the blind proposal, including
  # targets absent from a header-only enumerator and direct/single/all/batch dispatch.
  def test_explicit_historical_bindings_preserve_regression_and_dispatch
    @configs.each do |config|
      bind(config, "ADV-0001", calibration: "historical")
      provider = TestSupport::FakeProvider.new
      runner = build_runner(config, provider)
      observed = []
      trace = TracePoint.new(:call) do |event|
        observed << provider.calls.length if event.defined_class == AFScoring::AFAO && event.method_id == :calibration_expectations
      end
      outcome = nil
      trace.enable { outcome = runner.score("ADV-0001", regression: true) }
      assert_equal [8], observed
      assert_equal 20, outcome.comparisons.length
      assert outcome.comparisons.all?(&:exact_match)
      afao = AFScoring::AFAO.new(config.afao_path)
      eligibility = decision(config, "ADV-0001", afao)
      assert_equal 20, runner.reference_set.expected_for("ADV-0001", afao: afao, eligibility: eligibility).length
      assert_raises(AFScoring::ConfigurationError) { runner.reference_set.expected_for("ADV-0001", afao: afao) }

      with_provider_factory(provider) do
        assert_cli(config, "--regression", "ADV-0001")
        batch = File.join(config.project_root, "batch.txt")
        File.write(batch, "ADV-0001\n")
        assert_cli(config, "--batch", batch, "--with-regression")
        assert_cli(config, "--regression-all") # Header-only enumeration is valid.
        TestSupport.build_xlsx(config.regression_workbook_path, sheet_name: "AFAO 1.0 ADV References", rows: [["Adventure ID"], ["ADV-0001"]])
        assert_cli(config, "--regression-all")
      end
      assert_equal 32, provider.calls.length
    end
  end

  # An ADV collision cannot transfer a historical declaration in either direction;
  # requested regression without selection refuses before constructing any provider.
  def test_wrong_missing_ambiguous_and_incompatible_bindings_refuse
    @configs.each_with_index do |config, index|
      other = @configs.fetch(1 - index)
      bind(config, "ADV-0001", calibration: "historical")
      provider = TestSupport::FakeProvider.new
      other.data["target_bindings"] = Marshal.load(Marshal.dump(config.data["target_bindings"]))
      assert_raises(AFScoring::ConfigurationError) do
        AFScoring::TargetEligibility.new(selection: nil, context: nil, afao: AFScoring::AFAO.new(config.afao_path))
      end
      assert_raises(AFScoring::ConfigurationError) { build_runner(other, provider).prepare_source("ADV-0001") }
      assert_raises(AFScoring::ConfigurationError) { build_runner(other, provider).score("ADV-0001", regression: true) }
      config.data["target_bindings"]["targets"] *= 2
      assert_raises(AFScoring::ConfigurationError) { build_runner(config, provider).preflight("ADV-0001") }
      config.data.delete("target_bindings")
      with_provider_factory(provider) do
        assert_raises(AFScoring::ConfigurationError) { build_runner(config).score("ADV-0001", regression: true) }
      end
      assert_equal 0, @provider_constructions
      assert_empty provider.calls
      config.data["target_bindings"] = { "contract_version" => "unknown", "targets" => [] }
      assert_raises(AFScoring::ConfigurationError) { build_runner(config, provider).preflight("ADV-0001") }
      config.data["target_bindings"] = selection([{ "context" => nil, "calibration" => "historical" }])
      assert_raises(AFScoring::ConfigurationError) { build_runner(config, provider).preflight("ADV-0001") }
      config.data["target_bindings"] = selection([])
      assert_equal 8, build_runner(config, provider).preflight("ADV-0001").targets.length
    end
  end

  # Live mutations and rewritten payload fields refuse with real owner checks; restore
  # every mutation and repeat success, including same-label changes outside the slice.
  def test_mutations_and_cross_library_payloads_refuse_and_restore
    config = @configs.first
    bind(config, "ADV-0001", calibration: "historical")
    runner = build_runner(config)
    prepared = runner.prepare_source("ADV-0001")
    [config.catalog_path, config.source_registry_path, File.join(config.project_root, "source.md"), config.afao_path].each do |path|
      bytes = File.binread(path)
      begin
        File.binwrite(path, bytes + "\n")
        assert_raises(AFScoring::Error) { runner.preflight("ADV-0001", prepared_source: prepared) }
        assert_raises(AFScoring::Error) { build_runner(config).score("ADV-0001", regression: true) }
      ensure
        File.binwrite(path, bytes)
      end
      assert_equal 8, runner.preflight("ADV-0001", prepared_source: prepared).targets.length
    end
    [
      ->(payload) { payload["extraction"]["text"] += "100\n" },
      ->(payload) { payload["levels_context"] += "100\n" },
      ->(payload) { payload["target_eligibility"]["calibration"] = "none" },
      ->(payload) { payload["target_eligibility"]["context"]["page_marker_offset"] = 1 },
      ->(payload) { payload["source_policy"]["allow_full_source_fallback"] = true },
      ->(payload) { payload["contract_version"] = "afsu-prepared-source/v0.1" }
    ].each do |mutation|
      changed = Marshal.load(Marshal.dump(prepared))
      mutation.call(changed)
      assert_raises(AFScoring::SourceResolutionError) { runner.preflight("ADV-0001", prepared_source: changed) }
      assert_equal 8, runner.preflight("ADV-0001", prepared_source: prepared).targets.length
    end
    assert_raises(AFScoring::SourceResolutionError) { build_runner(@configs.last).preflight("ADV-0001", prepared_source: prepared) }
    config.data["target_bindings"]["targets"].first["afao_sha256"] = "0" * 64
    assert_raises(AFScoring::ConfigurationError) { build_runner(config).preflight("ADV-0001") }
    bind(config, "ADV-0001", calibration: "historical")
    assert_equal 8, build_runner(config).preflight("ADV-0001").targets.length
  end

  # A config-local ID permission needs the complete source context before extraction.
  # Both libraries can explicitly bind their own exception; neither can reuse the other.
  def test_source_exception_requires_matching_source_content_in_both_directions
    @configs.each do |config|
      File.write(File.join(config.project_root, "source.md"), "<!-- PAGE: 2 -->\n#{File.basename(config.project_root)}\n<!-- PAGE: 3 -->\n3\n")
      config.data["source"] = { "allow_inward_boundary_clamp_adventure_ids" => ["ADV-0001"], "inward_boundary_clamp_max_gap_by_adventure" => { "ADV-0001" => 1 } }
      assert_raises(AFScoring::ConfigurationError) { build_runner(config).prepare_source("ADV-0001") }
      bind(config, "ADV-0001", calibration: "none")
      prepared = build_runner(config).prepare_source("ADV-0001")
      assert_equal "canonical_page_slice_boundary_clamped", prepared.dig("extraction", "scope")
      assert_equal 8, build_runner(config).preflight("ADV-0001", prepared_source: prepared).targets.length
    end
    @configs.each_with_index do |config, index|
      other = @configs.fetch(1 - index)
      own_selection = Marshal.load(Marshal.dump(config.data["target_bindings"]))
      config.data["target_bindings"] = other.data["target_bindings"]
      assert_raises(AFScoring::ConfigurationError) { build_runner(config).preflight("ADV-0001") }
      config.data["target_bindings"] = own_selection
      assert_equal 8, build_runner(config).preflight("ADV-0001").targets.length
    end
  end

  # Build one independent library using the owner's real workbook helper and numeric
  # source mechanics. Returns Config; no inference or catalog/source identity adjudication.
  def build_library(root, number)
    FileUtils.mkdir_p(File.join(root, "config"))
    title = "Mechanical #{number}"
    TestSupport.build_xlsx(File.join(root, "catalog.xlsx"), sheet_name: "Adventure Catalog", rows: [
      ["Adventure ID", "Adventure Title", "Page Count", "Source Book", "Book Publisher", "Start Page", "End Page"],
      ["ADV-0001", title, 2, "Mechanical Source #{number}", "Fixture", 1, 2],
      ["ADV-9999", "Mechanical Control #{number}", 2, "Mechanical Source #{number}", "Fixture", 1, 2]
    ])
    File.write(File.join(root, "source.md"), "<!-- PAGE: 1 -->\n#{number}\n<!-- PAGE: 2 -->\n#{number.to_i * 2}\n<!-- PAGE: 3 -->\n3\n")
    File.write(File.join(root, "registry.yml"), { "schema_version" => AFScoring::SourceResolver::REGISTRY_SCHEMA_VERSION, "sources" => { "Mechanical Source #{number}" => { "file" => "source.md" } } }.to_yaml)
    TestSupport.build_xlsx(File.join(root, "refs.xlsx"), sheet_name: "AFAO 1.0 ADV References", rows: [["Adventure ID"]])
    File.write(File.join(root, "afao.md"), TestSupport.minimal_afao(target_title: title))
    File.write(File.join(root, "assessment.md"), TestSupport.minimal_assessment_spec)
    File.write(File.join(root, "config/default.yml"), {
      "paths" => { "xlsx_root" => root, "source_root" => root, "specification_root" => root, "output_root" => File.join(root, "output") },
      "files" => { "catalog" => "catalog.xlsx", "source_registry" => "registry.yml", "regression_workbook" => "refs.xlsx", "afao" => "afao.md", "assessment_spec" => "assessment.md" },
      "llm" => { "provider" => "ollama", "model" => "fixture-only" },
      "review" => { "low_confidence_threshold" => 60, "moderate_confidence_ceiling" => 74 }
    }.to_yaml)
    AFScoring::Config.new(project_root: root)
  end

  # Independently assemble the documented context with actual owner resolution and
  # content digests. This declares fixture intent; it never replaces owner validators.
  def context(config, identifier)
    adventure = AFScoring::Catalog.new(config.catalog_path).fetch(identifier)
    resolution = AFScoring::SourceResolver.new(source_root: config.dig("paths", "source_root"), registry_path: config.source_registry_path).resolve(adventure)
    files = { "catalog" => config.catalog_path, "source_registry" => config.source_registry_path, "source_file" => resolution.path }
    files.transform_values { |path| { "path" => File.expand_path(path), "sha256" => Digest::SHA256.file(path).hexdigest } }.merge(
      "adventure" => adventure.to_h.transform_keys(&:to_s), "page_marker_offset" => resolution.page_marker_offset || 0,
      "source_policy" => { "source_root" => config.dig("paths", "source_root"), "source_registry_path" => config.source_registry_path,
        "allow_full_source_fallback" => !!config.dig("source", "allow_full_source_fallback"),
        "allow_inward_boundary_clamp" => Array(config.dig("source", "allow_inward_boundary_clamp_adventure_ids")).include?(identifier),
        "max_inward_boundary_clamp_gap" => config.dig("source", "inward_boundary_clamp_max_gap_by_adventure", identifier) || 1 }
    )
  end

  # Return the explicit versioned selection; unknown versions are exercised separately.
  def selection(entries)
    { "contract_version" => "afsu-target-eligibility/v0.1", "targets" => entries }
  end

  # Bind this mechanical fixture explicitly to historical or absent calibration.
  # Returns the selection; production never infers historical membership this way.
  def bind(config, identifier, calibration:)
    config.data["target_bindings"] = selection([{ "context" => context(config, identifier), "calibration" => calibration, "afao_sha256" => Digest::SHA256.file(config.afao_path).hexdigest }])
  end

  # Resolve a production eligibility decision from this test's explicit trusted fixture.
  # Returns TargetEligibility; real validation errors propagate.
  def decision(config, identifier, afao)
    AFScoring::TargetEligibility.new(selection: config.dig("target_bindings"), context: context(config, identifier), afao: afao)
  end

  # Return a real runner with an optional external fake provider and silent logging.
  def build_runner(config, provider = nil)
    AFScoring::Runner.new(config: config, provider: provider, logger: ->(_message) {})
  end

  # Exercise real CLI prepare/direct/replay against this selected config; assert success.
  def assert_cli_prepare(config, identifier)
    prepared_path = File.join(config.project_root, "prepared.json")
    assert_cli(config, "--prepare-source", prepared_path, identifier)
    assert_cli(config, "--preflight", identifier)
    assert_cli(config, "--preflight", "--prepared-source", prepared_path, identifier)
  end

  # Persist only this fixture's config and invoke real CLI dispatch; failures assert stderr.
  def assert_cli(config, *arguments)
    File.write(File.join(config.project_root, "config/default.yml"), config.data.to_yaml)
    errors = StringIO.new
    status = AFScoring::CLI.new(arguments, project_root: config.project_root, out: StringIO.new, err: errors).run
    assert_equal 0, status, errors.string
  end

  # Replace only external provider construction and restore it even on test failure.
  def with_provider_factory(provider)
    factory = AFScoring::Providers::OllamaProvider.method(:new)
    construction = -> { @provider_constructions += 1 }
    AFScoring::Providers::OllamaProvider.define_singleton_method(:new) do |**_options|
      construction.call
      provider
    end
    yield
  ensure
    AFScoring::Providers::OllamaProvider.define_singleton_method(:new, factory)
  end
end
