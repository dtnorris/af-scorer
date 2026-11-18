# frozen_string_literal: true
require_relative "test_helper"

class ConfigTest < Minitest::Test
  def test_config_overrides_defaults
    Dir.mktmpdir do |dir|
      write_default_config(dir)

      custom = File.join(dir, "custom.yml")
      File.write(
        custom,
        {
          "llm" => { "model" => "custom-model" },
          "paths" => { "output_root" => "tmp-output" }
        }.to_yaml
      )

      config = AFScoring::Config.new(project_root: dir, config_path: custom)

      assert_equal "custom-model", config.dig("llm", "model")
      assert_equal "fixture-provider", config.dig("llm", "provider")
      assert_equal File.join(dir, "tmp-output"), config.dig("paths", "output_root")
      assert_equal "fixture-catalog.xlsx", config.dig("files", "catalog")
      assert_equal "fixture-afao.md", config.dig("files", "afao")
      assert_equal File.join(dir, "source", "source_registry.yml"), config.source_registry_path
    end
  end

  def test_source_registry_can_be_overridden_by_environment
    previous = ENV["AF_SOURCE_REGISTRY"]
    ENV["AF_SOURCE_REGISTRY"] = "/tmp/custom-source-registry.yml"

    Dir.mktmpdir do |dir|
      write_default_config(dir)
      config = AFScoring::Config.new(project_root: dir)
      assert_equal "/tmp/custom-source-registry.yml", config.source_registry_path
    end
  ensure
    previous.nil? ? ENV.delete("AF_SOURCE_REGISTRY") : ENV["AF_SOURCE_REGISTRY"] = previous
  end

  def test_catalog_defaults_to_catalog_head_from_project_state
    Dir.mktmpdir do |dir|
      write_project_state_config(dir)
      xlsx_root = File.join(dir, "xlsx")
      catalog = write_catalog(xlsx_root, "5.7.2", "head")
      write_project_state(xlsx_root, catalog_head: ["5.7.2", catalog])

      config = AFScoring::Config.new(project_root: dir)

      assert_equal catalog, config.catalog_path
    end
  end

  def test_explicit_catalog_environment_override_wins_without_project_state
    previous = ENV["AF_CATALOG_WORKBOOK"]
    Dir.mktmpdir do |dir|
      write_project_state_config(dir)
      explicit = File.join(dir, "explicit.xlsx")
      File.write(explicit, "explicit")
      ENV["AF_CATALOG_WORKBOOK"] = explicit

      config = AFScoring::Config.new(project_root: dir)

      assert_equal explicit, config.catalog_path
    end
  ensure
    previous.nil? ? ENV.delete("AF_CATALOG_WORKBOOK") : ENV["AF_CATALOG_WORKBOOK"] = previous
  end

  def test_project_state_catalog_integrity_is_fail_closed
    Dir.mktmpdir do |dir|
      write_project_state_config(dir)
      xlsx_root = File.join(dir, "xlsx")
      catalog = write_catalog(xlsx_root, "5.7.2", "head")
      write_project_state(xlsx_root, catalog_head: ["5.7.2", catalog])
      File.write(catalog, "tampered")

      error = assert_raises(AFScoring::ConfigurationError) do
        AFScoring::Config.new(project_root: dir).catalog_path
      end
      assert_includes error.message, "byte-size mismatch"
    end
  end

  # Role lookup follows the selected manifest and validates even an unused role.
  def test_catalog_resolves_next_to_manifest_and_rejects_changed_nonselected_role
    Dir.mktmpdir do |dir|
      write_project_state_config(dir)
      selected = File.join(dir, "selected")
      head = write_catalog(selected, "2.0", "head")
      baseline = write_catalog(selected, "1.0", "base")
      manifest = File.join(selected, "PROJECT_STATE.yml")
      write_project_state(selected, catalog_head: ["2.0", head])
      state = YAML.safe_load_file(manifest)
      state["matcher_authorized_baseline"] = project_state_entry("1.0", baseline)
      File.write(manifest, state.to_yaml)
      config = AFScoring::Config.new(project_root: dir, overrides: {"files" => {"project_state" => manifest}})

      assert_equal head, config.catalog_path
      File.binwrite(baseline, "edit")
      error = assert_raises(AFScoring::ConfigurationError) { config.catalog_path }
      assert_match(/matcher_authorized_baseline catalog SHA-256 mismatch/, error.message)

      File.binwrite(baseline, "base")
      assert_equal head, config.catalog_path
      newer = write_catalog(selected, "3.0", "newer")
      state["production_dependency_floor"] = project_state_entry("3.0", newer)
      File.write(manifest, state.to_yaml)
      error = assert_raises(AFScoring::ConfigurationError) { config.catalog_path }
      assert_match(/production_dependency_floor .* cannot be newer than catalog_head/, error.message)
    end
  end

  def test_ollama_base_url_can_be_overridden_by_environment
    previous = ENV["AF_OLLAMA_BASE_URL"]
    ENV["AF_OLLAMA_BASE_URL"] = "http://localhost:9999"

    Dir.mktmpdir do |dir|
      write_default_config(dir)
      config = AFScoring::Config.new(project_root: dir)
      assert_equal "http://localhost:9999", config.dig("llm", "ollama_base_url")
    end
  ensure
    previous.nil? ? ENV.delete("AF_OLLAMA_BASE_URL") : ENV["AF_OLLAMA_BASE_URL"] = previous
  end

  private

  def write_project_state_config(dir)
    config_dir = File.join(dir, "config")
    FileUtils.mkdir_p(config_dir)
    File.write(
      File.join(config_dir, "default.yml"),
      {
        "paths" => {"xlsx_root" => File.join(dir, "xlsx")},
        "files" => {"project_state" => "PROJECT_STATE.yml", "catalog_role" => "catalog_head"}
      }.to_yaml
    )
  end

  def write_catalog(root, version, content)
    FileUtils.mkdir_p(root)
    path = File.join(root, "5e_Adventure_Master_Catalog_#{version}.xlsx")
    File.binwrite(path, content)
    path
  end

  def write_project_state(root, catalog_head:)
    version, path = catalog_head
    payload = {
      "schema_version" => "adventurefinder-project-state/v0.2",
      "catalog_head" => project_state_entry(version, path),
      "matcher_authorized_baseline" => project_state_entry(version, path),
      "production_dependency_floor" => project_state_entry(version, path)
    }
    File.write(File.join(root, "PROJECT_STATE.yml"), payload.to_yaml)
  end

  def project_state_entry(version, path)
    {
      "version" => version,
      "filename" => File.basename(path),
      "sha256" => Digest::SHA256.file(path).hexdigest,
      "bytes" => File.size(path)
    }
  end

  def write_default_config(dir)
    config_dir = File.join(dir, "config")
    FileUtils.mkdir_p(config_dir)
    File.write(
      File.join(config_dir, "default.yml"),
      {
        "llm" => {
          "provider" => "fixture-provider",
          "model" => "default-model",
          "ollama_base_url" => "http://127.0.0.1:11434"
        },
        "paths" => {
          "source_root" => "source",
          "output_root" => "default-output"
        },
        "files" => {
          "catalog" => "fixture-catalog.xlsx",
          "afao" => "fixture-afao.md",
          "source_registry" => "source_registry.yml"
        }
      }.to_yaml
    )
  end
end
