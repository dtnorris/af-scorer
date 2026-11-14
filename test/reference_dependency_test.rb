# frozen_string_literal: true

require_relative "test_helper"
require "csv"

# Exercise reference loading through real CLI/Runner paths on a content-free library.
# Only provider construction is replaced; source, definitions and result checks run normally.
class ReferenceDependencyTest < Minitest::Test
  # Build isolated catalog/source/definition inputs; filesystem errors propagate.
  def setup
    @root = Dir.mktmpdir("reference-dependency")
    %w[config xlsx spec source].each { |name| FileUtils.mkdir_p(File.join(@root, name)) }
    TestSupport.build_xlsx(File.join(@root, "xlsx/catalog.xlsx"), sheet_name: "Adventure Catalog", rows: [
      ["Adventure ID", "Adventure Title", "Page Count", "Source Book", "Book Publisher", "Start Page", "End Page"],
      ["ADV-0001", "Mechanical Fixture", 2, "Mechanical Source", "Fixture", 1, 2]
    ])
    File.write(File.join(@root, "spec/afao.md"), TestSupport.minimal_afao(target_title: "Mechanical Fixture"))
    File.write(File.join(@root, "spec/assessment.md"), TestSupport.minimal_assessment_spec)
    File.write(File.join(@root, "source/source.md"), "<!-- PAGE: 1 -->\n1\n<!-- PAGE: 2 -->\n2\n<!-- PAGE: 3 -->\n3\n")
    File.write(File.join(@root, "source/registry.yml"), {
      "schema_version" => AFScoring::SourceResolver::REGISTRY_SCHEMA_VERSION,
      "sources" => { "Mechanical Source" => { "file" => "source.md" } }
    }.to_yaml)
    @data = {
      "paths" => { "xlsx_root" => "xlsx", "specification_root" => "spec", "source_root" => "source", "output_root" => "output" },
      "files" => { "catalog" => "catalog.xlsx", "afao" => "afao.md", "assessment_spec" => "assessment.md",
                   "source_registry" => "registry.yml", "regression_workbook" => "refs.xlsx" },
      "llm" => { "provider" => "ollama", "model" => "fixture-only" },
      "review" => { "low_confidence_threshold" => 60, "moderate_confidence_ceiling" => 74 }
    }
    @batch = File.join(@root, "batch.txt")
    File.write(@batch, "ADV-0001\n")
    @provider = TestSupport::FakeProvider.new
    @provider_constructions = 0
  end

  # Remove only this test's private fixture; filesystem errors propagate.
  def teardown
    FileUtils.remove_entry(@root)
  end

  # Ordinary modes must never resolve or instantiate references, even with broken inputs.
  # Runs real prepare/preflight, normalization, review and CSV checks; failures assert.
  def test_ordinary_runner_and_cli_do_not_touch_reference_inputs
    [:absent, :missing, :malformed].each do |state|
      select_reference(state)
      reference_calls = []
      trace = TracePoint.new(:call) do |event|
        if (event.defined_class == AFScoring::Config && event.method_id == :regression_workbook_path) ||
           (event.defined_class == AFScoring::Regression::ReferenceSet && event.method_id == :initialize)
          reference_calls << [event.defined_class, event.method_id]
        end
      end
      trace.enable do
        runner = build_runner
        prepared = runner.prepare_source("ADV-0001")
        direct = runner.preflight("ADV-0001")
        cached = runner.preflight("ADV-0001", prepared_source: prepared)
        assert_equal direct.targets.map(&:to_h), cached.targets.map(&:to_h)
        assert_empty @provider.calls
        refute File.exist?(File.join(@root, "output"))
        assert_package(runner.score("ADV-0001"), regression: false)

        with_provider_factory do
          prepared_path = File.join(@root, "prepared.json")
          assert_cli_success("--prepare-source", prepared_path, "ADV-0001")
          assert_cli_success("--preflight", "ADV-0001")
          assert_cli_success("--preflight", "--prepared-source", prepared_path, "ADV-0001")
          assert_equal 0, @provider_constructions
          assert_equal 8, @provider.calls.length
          assert_cli_success("ADV-0001")
          assert_cli_success("--batch", @batch)
          assert_equal 24, @provider.calls.length
        end
      end
      assert_empty reference_calls, state.to_s
      FileUtils.rm_rf(File.join(@root, "output"))
      @provider = TestSupport::FakeProvider.new
      @provider_constructions = 0
    end
  end

  # Selected invalid references must fail with their existing error classes before
  # provider construction or scoring, through direct, single, all and batch dispatch.
  def test_selected_invalid_references_fail_before_provider_construction
    {
      absent: [AFScoring::ConfigurationError, /Missing configured path component/],
      missing: [AFScoring::ConfigurationError, /Missing regression workbook/],
      malformed: [AFScoring::CatalogError, /Cannot read/],
      empty: [AFScoring::RegressionReferenceError, /workbook is empty/],
      wrong_sheet: [AFScoring::CatalogError, /Worksheet not found/],
      wrong_header: [AFScoring::RegressionReferenceError, /does not contain Adventure ID/]
    }.each do |state, (error_class, message)|
      select_reference(state)
      File.write(@batch, "ADV-0001\n")
      with_provider_factory do
        runner = build_runner(provider: nil)
        error = assert_raises(error_class) { runner.score("ADV-0001", regression: true) }
        assert_match message, error.message
        assert_raises(error_class) { runner.reference_set }
        [["--regression", "ADV-0001"], ["--regression-all"], ["--batch", @batch, "--with-regression"]].each do |arguments|
          status, _output, errors = run_cli(*arguments)
          assert_equal 1, status, "#{state}: #{arguments.inspect}"
          assert_match message, errors
        end
        File.write(@batch, "")
        status, _output, errors = run_cli("--batch", @batch, "--with-regression")
        assert_equal 1, status
        assert_match message, errors
      end
      assert_equal 0, @provider_constructions, state.to_s
      assert_empty @provider.calls
      refute File.exist?(File.join(@root, "output"))
    end
  end

  # Workbook enumeration stays public and cached; explicit comparisons still use
  # AFAO for targets outside the index, including a valid header-only workbook.
  def test_valid_regression_preserves_enumeration_and_later_afao_expectations
    [:valid, :header_only, :other_id].each do |state|
      select_reference(state)
      runner = build_runner
      TestSupport.bind_historical(runner.config)
      File.write(File.join(@root, "config/default.yml"), runner.config.data.to_yaml)
      expected_ids = { valid: ["ADV-0001"], header_only: [], other_id: ["ADV-9999"] }.fetch(state)
      assert_equal expected_ids, runner.reference_set.ids
      assert_same runner.reference_set, runner.reference_set
      before = @provider.calls.length
      expectation_calls = []
      trace = TracePoint.new(:call) do |event|
        if event.defined_class == AFScoring::AFAO && event.method_id == :calibration_expectations
          expectation_calls << @provider.calls.length - before
        end
      end
      trace.enable { assert_package(runner.score("ADV-0001", regression: true), regression: true) }
      assert_equal [8], expectation_calls, "AFAO expectations must be derived after every blind provider response"
      @provider.calls.drop(before).each do |call|
        refute_includes call.fetch(:prompt).input, "**ADV-0001"
        refute_includes call.fetch(:prompt).input, "**Mechanical Fixture**"
      end
      with_provider_factory do
        assert_cli_success("--regression", "ADV-0001")
        assert_cli_success("--batch", @batch, "--with-regression")
        if state == :valid || state == :header_only
          before = @provider.calls.length
          assert_cli_success("--regression-all")
          assert_equal before + (state == :valid ? 8 : 0), @provider.calls.length
        end
      end
    end
  end

  # Non-reference governing files and frozen source bindings must still fail closed.
  # Mutate only disposable inputs; real owner checks supply each refusal.
  def test_missing_governing_files_and_changed_prepared_bindings_still_fail
    select_reference(:absent)
    %w[xlsx/catalog.xlsx spec/afao.md spec/assessment.md].each do |relative|
      path = File.join(@root, relative)
      bytes = File.binread(path)
      File.unlink(path)
      assert_raises(AFScoring::ConfigurationError) { build_runner }
      File.binwrite(path, bytes)
    end
    runner = build_runner
    prepared = runner.prepare_source("ADV-0001")
    %w[xlsx/catalog.xlsx source/registry.yml source/source.md].each do |relative|
      path = File.join(@root, relative)
      bytes = File.binread(path)
      File.binwrite(path, bytes + "\n")
      assert_raises(AFScoring::SourceResolutionError) { runner.preflight("ADV-0001", prepared_source: prepared) }
      File.binwrite(path, bytes)
    end
    prepared["source_policy"]["allow_full_source_fallback"] = true
    assert_raises(AFScoring::SourceResolutionError) { runner.preflight("ADV-0001", prepared_source: prepared) }
    assert_empty @provider.calls
  end

  private

  # Replace only the provider factory for CLI scoring and count constructions.
  # Yields to the check and restores the real factory even if the check raises.
  def with_provider_factory
    factory = AFScoring::Providers::OllamaProvider.method(:new)
    provider = @provider
    count_construction = -> { @provider_constructions += 1 }
    AFScoring::Providers::OllamaProvider.define_singleton_method(:new) do |**_options|
      count_construction.call
      provider
    end
    yield
  ensure
    AFScoring::Providers::OllamaProvider.define_singleton_method(:new, factory)
  end

  # Write one chosen reference condition into the fixture and persist config.
  # Accepts a named test state; unknown states raise KeyError.
  def select_reference(state)
    @data["files"]["regression_workbook"] = "refs.xlsx"
    path = File.join(@root, "xlsx/refs.xlsx")
    FileUtils.rm_f(path)
    if state == :absent
      @data["files"].delete("regression_workbook")
    elsif state == :malformed
      File.write(path, "not a workbook")
    elsif state != :missing
      sheet, rows = {
        valid: ["AFAO 1.0 ADV References", [["Adventure ID"], ["ADV-0001"]]],
        header_only: ["AFAO 1.0 ADV References", [["Adventure ID"]]],
        other_id: ["AFAO 1.0 ADV References", [["Adventure ID"], ["ADV-9999"]]],
        empty: ["AFAO 1.0 ADV References", []],
        wrong_sheet: ["Wrong Sheet", [["Adventure ID"]]],
        wrong_header: ["AFAO 1.0 ADV References", [["Wrong Header"]]]
      }.fetch(state)
      TestSupport.build_xlsx(path, sheet_name: sheet, rows: rows)
    end
    File.write(File.join(@root, "config/default.yml"), @data.to_yaml)
  end

  # Return a real Runner with this fixture's Config and optional fake provider.
  # Governing-file/config errors propagate from the production constructor.
  def build_runner(provider: @provider)
    AFScoring::Runner.new(config: AFScoring::Config.new(project_root: @root), provider: provider, logger: ->(_message) {})
  end

  # Execute actual CLI dispatch with fixture roots; return status/stdout/stderr.
  # CLI handles its documented errors; unexpected exceptions propagate.
  def run_cli(*arguments)
    output = StringIO.new
    errors = StringIO.new
    status = AFScoring::CLI.new(arguments, project_root: @root, out: output, err: errors).run
    [status, output.string, errors.string]
  end

  # Require a successful CLI call for the given argv; assertion includes stderr.
  def assert_cli_success(*arguments)
    status, _output, errors = run_cli(*arguments)
    assert_equal 0, status, errors
  end

  # Validate persisted proposals/comparisons for a real Runner outcome; failures assert.
  def assert_package(outcome, regression:)
    assert_equal 20, outcome.package.metrics.length
    assert_equal "PROPOSED", outcome.package.status
    assert_equal "NO_AUTOMATIC_REVIEW_TRIGGER", outcome.package.review_disposition
    assert_equal 20, CSV.read(outcome.assessment_csv, headers: true).length
    if regression
      assert_equal 20, outcome.comparisons.length
      assert outcome.comparisons.all?(&:exact_match)
      assert File.file?(outcome.regression_csv)
    else
      assert_empty outcome.comparisons
      assert_nil outcome.regression_csv
    end
  end
end
