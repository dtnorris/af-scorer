# frozen_string_literal: true

require_relative "test_helper"
require "json"

# Exercise public-method admission through real preparation, CLI dispatch and scoring.
# Only the external provider factory is replaced; all input/result validators remain real.
class PublicMethodTest < Minitest::Test
  # Build content-free inputs and copy only required public definitions into private scratch.
  # Missing public checkout/dependencies fail this integration test rather than imply coverage.
  def setup
    @root = Dir.mktmpdir("public-method")
    FileUtils.mkdir_p(File.join(@root, "config"))
    @method_root = File.join(@root, "method")
    FileUtils.mkdir_p(@method_root)
    public_root = ENV.fetch("AF_TEST_SPEC_ROOT") { File.expand_path("../../af-specification-md", __dir__) }
    ["documents.json", *AFScoring::SelectedMethod::PUBLIC_FILES.values.map(&:first)].each do |basename|
      FileUtils.cp(File.join(public_root, basename), @method_root)
    end
    TestSupport.build_xlsx(File.join(@root, "catalog.xlsx"), sheet_name: "Adventure Catalog", rows: [
      ["Adventure ID", "Adventure Title", "Page Count", "Source Book", "Book Publisher", "Start Page", "End Page"],
      ["ADV-0001", "Mechanical Fixture", 2, "Mechanical Source", "Fixture", 1, 2]
    ])
    File.write(File.join(@root, "source.md"), "<!-- PAGE: 1 -->\n1\n<!-- PAGE: 2 -->\n2\n<!-- PAGE: 3 -->\n3\n")
    File.write(File.join(@root, "registry.yml"), {
      "schema_version" => AFScoring::SourceResolver::REGISTRY_SCHEMA_VERSION,
      "sources" => { "Mechanical Source" => { "file" => "source.md" } }
    }.to_yaml)
    @data = YAML.safe_load_file(File.expand_path("../config/default.yml", __dir__))
    @data["paths"] = { "xlsx_root" => @root, "specification_root" => @method_root, "source_root" => @root, "output_root" => File.join(@root, "output") }
    @data["files"].merge!("catalog" => "catalog.xlsx", "source_registry" => "registry.yml", "regression_workbook" => "absent.xlsx")
    @data["llm"].merge!("provider" => "ollama", "model" => "fixture-only")
    write_config
    @provider = TestSupport::FakeProvider.new
  end

  # Remove only the test's disposable tree; filesystem errors propagate.
  def teardown
    FileUtils.remove_entry(@root)
  end

  # Prepare, replay, render and score without private definitions or incidental references.
  # Explicit regression still refuses missing references before provider construction.
  def test_public_runner_and_cli_use_complete_method_without_private_fallback
    with_observed_files do |reads|
      runner = build_runner
      prepared = runner.prepare_source("ADV-0001")
      direct = runner.preflight("ADV-0001")
      replay = runner.preflight("ADV-0001", prepared_source: prepared)
      assert_equal direct.targets, replay.targets
      assert_equal 8, direct.targets.length
      assert_equal AFScoring::DimensionGroups::ALL, direct.targets.flat_map(&:dimensions)
      assert_equal AFScoring::SelectedMethod::PUBLIC_IDENTITY, direct.run_metadata.dig("method", "identity")
      assert_empty direct.run_metadata.dig("method", "retained_profiles")
      assert_equal 20, runner.score("ADV-0001").package.metrics.length
      assert_raises(AFScoring::ConfigurationError) { runner.score("ADV-0001", regression: true) }
      assert_cli(0, "--prepare-source", File.join(@root, "prepared.json"), "ADV-0001")
      assert_cli(0, "--preflight", "--prepared-source", File.join(@root, "prepared.json"), "--render-preflight", File.join(@root, "preflight.json"), "ADV-0001")
      assert_cli(1, "--regression", "ADV-0001")
      TestSupport.build_xlsx(File.join(@root, "absent.xlsx"), sheet_name: "AFAO 1.0 ADV References", rows: [["Adventure ID"], ["ADV-0001"]])
      @data["target_bindings"] = { "contract_version" => AFScoring::TargetEligibility::CONTRACT_VERSION, "targets" => [] }
      write_config
      File.write(File.join(@root, "batch.txt"), "ADV-0001\n")
      with_provider_factory(->(**_options) { @provider }) do
        assert_cli(0, "ADV-0001")
        assert_cli(0, "--batch", File.join(@root, "batch.txt"))
        assert_cli(0, "--regression", "ADV-0001")
        assert_cli(0, "--regression-all")
        assert_cli(0, "--batch", File.join(@root, "batch.txt"), "--with-regression")
      end
      assert reads.any? { |path| path == File.join(@method_root, "documents.json") }
    end
  end

  # Corrupt each required input after construction, refuse all preparation modes and score,
  # then restore and repeat success. No provider is constructed or executed on refusal.
  def test_consumer_refuses_missing_sections_anchors_versions_and_changed_bytes
    inventory = JSON.parse(File.read(File.join(@method_root, "documents.json")))
    mutations = [["documents.json", :missing]]
    AFScoring::SelectedMethod::PUBLIC_FILES.each_value do |basename, _digest|
      entry = inventory.fetch("files").find { |file| file["path"] == basename }
      mutations.concat([[basename, :missing], [basename, :version], [basename, :byte]])
      if entry["score_anchors"]
        assert_equal 85, entry.fetch("score_anchors").length
        assert_equal 19, entry.fetch("dimensions").length
        mutations << [basename, entry.fetch("score_anchors").first]
        mutations << [basename, entry.fetch("dimensions").first]
      else
        assert_equal 10, entry.fetch("prompt_sections").length
        entry.fetch("prompt_sections").each { |section| mutations << [basename, section] }
      end
    end
    with_observed_files do
      mutations.each do |basename, mutation|
        path = File.join(@method_root, basename)
        original = File.binread(path)
        runner = build_runner
        prepared = runner.prepare_source("ADV-0001")
        begin
          if mutation == :missing
            File.unlink(path)
          else
            altered = case mutation
                      when :version then original.sub(/## Version [^\r\n]+/, "## Version 999")
                      when :byte then original + "\n"
                      else original.byteslice(0...mutation.fetch("start")) + original.byteslice(mutation.fetch("end")..)
                      end
            refute_equal original, altered
            File.binwrite(path, altered)
          end
          assert_raises(AFScoring::SpecificationError) { build_runner }
          assert_raises(AFScoring::SpecificationError) { runner.prepare_source("ADV-0001") }
          assert_raises(AFScoring::SpecificationError) { runner.preflight("ADV-0001", prepared_source: prepared) }
          assert_raises(AFScoring::SpecificationError) { runner.score("ADV-0001") }
          with_provider_factory(->(**_options) { flunk "provider constructed before refusal" }) do
            assert_cli(1, "--preflight", "ADV-0001")
            assert_cli(1, "ADV-0001")
          end
        ensure
          File.binwrite(path, original)
        end
        assert_equal 8, build_runner.preflight("ADV-0001").targets.length
      end
    end
    assert_empty @provider.calls
  end

  # Never infer another version/path or silently relabel historical configuration as public.
  # Explicit configured selection preserves permissive historical loaders and metadata.
  def test_selection_and_historical_compatibility_are_explicit
    @data["method"]["identity"] = "af-specification-md@latest"
    write_config
    assert_raises(AFScoring::ConfigurationError) { build_runner }
    @data["method"]["identity"] = AFScoring::SelectedMethod::PUBLIC_IDENTITY
    @data["files"]["afao"] = "historical.md"
    File.write(File.join(@method_root, "historical.md"), TestSupport.minimal_afao)
    write_config
    assert_raises(AFScoring::SpecificationError) { build_runner }
    @data["method"]["identity"] = "configured"
    write_config
    outcome = build_runner.preflight("ADV-0001")
    refute outcome.run_metadata.key?("method")
    assert_includes outcome.targets.first.prompt.input, "Frozen AFAO 1.0"
  end

  # Record an explicitly loaded retained profile separately from the public document identity.
  # Restore the process selection after checking real preflight metadata; input errors propagate.
  def test_loaded_retained_profile_has_separate_identity
    name = AFScoring::Phase6SocialInteractionGuardrail::PROFILE_ENV
    original = ENV[name]
    ENV[name] = AFScoring::Phase6SocialInteractionGuardrail::PROFILE
    @data["scoring"] = { "dimension" => "Social Interaction Emphasis" }
    write_config
    outcome = build_runner.preflight("ADV-0001")
    assert_equal "retained", outcome.run_metadata.dig("method", "loader")
    assert_includes outcome.run_metadata.dig("method", "retained_modules"), "AFScoring::Phase6SocialInteractionGuardrail"
    assert_equal ENV[name], outcome.run_metadata.dig("method", "retained_profiles", name)
    assert_equal AFScoring::SelectedMethod::PUBLIC_IDENTITY, outcome.run_metadata.dig("method", "identity")
    assert_includes outcome.targets.first.prompt.input, AFScoring::Phase6SocialInteractionGuardrail::TEXT
  ensure
    ENV[name] = original
  end

  private

  # Persist the selected fixture config; filesystem errors propagate.
  def write_config
    File.write(File.join(@root, "config/default.yml"), @data.to_yaml)
  end

  # Return a real Runner with external provider transport replaced; input errors propagate.
  def build_runner
    AFScoring::Runner.new(config: AFScoring::Config.new(project_root: @root), provider: @provider, logger: ->(_message) {})
  end

  # Execute CLI dispatch and assert its documented exit status; include errors on failure.
  def assert_cli(expected, *arguments)
    errors = StringIO.new
    actual = AFScoring::CLI.new(arguments, project_root: @root, out: StringIO.new, err: errors).run
    assert_equal expected, actual, errors.string
  end

  # Replace only the external provider factory, yielding and restoring it on any exception.
  # The callable receives constructor options; its result/errors pass to the real Runner.
  def with_provider_factory(factory)
    original = AFScoring::Providers::OllamaProvider.method(:new)
    AFScoring::Providers::OllamaProvider.define_singleton_method(:new) { |**options| factory.call(**options) }
    yield
  ensure
    AFScoring::Providers::OllamaProvider.define_singleton_method(:new, original)
  end

  # Observe common File reads/checks and deny the real private method tree during this block.
  # All other filesystem calls retain their real behavior; restore methods even on failure.
  def with_observed_files
    private_root = File.expand_path("../../md-specification-files", __dir__)
    reads = []
    originals = %i[read binread open file? exist?].to_h { |name| [name, File.method(name)] }
    originals.each do |name, original|
      File.define_singleton_method(name) do |path, *arguments, **keywords, &block|
        if path.is_a?(String)
          expanded = File.expand_path(path)
          reads << expanded
          raise "Private method access: #{expanded}" if expanded == private_root || expanded.start_with?(private_root + "/")
        end
        original.call(path, *arguments, **keywords, &block)
      end
    end
    yield reads
  ensure
    originals.each { |name, original| File.define_singleton_method(name, original) }
  end
end
