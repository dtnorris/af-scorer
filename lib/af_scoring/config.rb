# frozen_string_literal: true

require "yaml"
require "pathname"
require "digest"

module AFScoring
  class Config
    PROJECT_STATE_SCHEMA = "adventurefinder-project-state/v0.2"
    PROJECT_STATE_ROLES = %w[catalog_head matcher_authorized_baseline production_dependency_floor].freeze

    ENV_MAP = {
      "AF_XLSX_ROOT" => %w[paths xlsx_root],
      "AF_SPEC_ROOT" => %w[paths specification_root],
      "AF_SOURCE_ROOT" => %w[paths source_root],
      "AF_SOURCE_REGISTRY" => %w[files source_registry],
      "AF_CATALOG_WORKBOOK" => %w[files catalog],
      "AF_PROJECT_STATE" => %w[files project_state],
      "AF_CATALOG_ROLE" => %w[files catalog_role],
      "AF_OUTPUT_DIR" => %w[paths output_root],
      "AF_OPENAI_MODEL" => %w[llm model],
      "AF_OPENAI_REASONING_EFFORT" => %w[llm reasoning_effort],
      "AF_LLM_PROVIDER" => %w[llm provider],
      "AF_LLM_MAX_TOKENS" => %w[llm max_tokens],
      "AF_OLLAMA_BASE_URL" => %w[llm ollama_base_url]
    }.freeze

    attr_reader :data, :project_root

    def initialize(project_root:, config_path: nil, overrides: {})
      @project_root = File.expand_path(project_root)
      default_path = File.join(@project_root, "config", "default.yml")
      raise ConfigurationError, "Missing default config: #{default_path}" unless File.file?(default_path)

      @data = load_yaml(default_path)
      deep_merge!(@data, load_yaml(config_path)) if config_path
      apply_environment!
      deep_merge!(@data, stringify_keys(overrides)) unless overrides.empty?
      normalize_paths!
    end

    def [](key)
      @data.fetch(key.to_s)
    end

    def dig(*keys)
      @data.dig(*keys.map(&:to_s))
    end

    def catalog_path
      explicit = dig("files", "catalog").to_s.strip
      return resolve_under(dig("paths", "xlsx_root"), explicit) unless explicit.empty?

      resolve_project_state_catalog(dig("files", "catalog_role") || "catalog_head")
    end

    def project_state_path
      resolve_under(dig("paths", "xlsx_root"), dig("files", "project_state"))
    end

    def regression_workbook_path
      resolve_under(dig("paths", "xlsx_root"), dig("files", "regression_workbook"))
    end

    def afao_path
      resolve_under(dig("paths", "specification_root"), dig("files", "afao"))
    end

    def assessment_spec_path
      resolve_under(dig("paths", "specification_root"), dig("files", "assessment_spec"))
    end

    def source_registry_path
      value = dig("files", "source_registry")
      resolve_under(dig("paths", "source_root"), value)
    end

    private

    # Resolve a named role from the manifest directory after verifying every
    # v0.2 binding. Invalid project state raises ConfigurationError.
    def resolve_project_state_catalog(role)
      role = role.to_s.strip
      unless PROJECT_STATE_ROLES.include?(role)
        raise ConfigurationError,
              "Unsupported catalog role #{role.inspect}; expected one of #{PROJECT_STATE_ROLES.join(', ')}"
      end

      manifest = project_state_path
      state = YAML.safe_load_file(manifest, aliases: false)
      unless state.is_a?(Hash) && state["schema_version"] == PROJECT_STATE_SCHEMA
        raise ConfigurationError, "Expected a #{PROJECT_STATE_SCHEMA} mapping in #{manifest}"
      end
      unknown = state.keys - ["schema_version", *PROJECT_STATE_ROLES]
      raise ConfigurationError, "Unknown project-state keys: #{unknown.join(', ')}" unless unknown.empty?

      paths = PROJECT_STATE_ROLES.to_h do |name|
        [name, validate_project_state_role(manifest, name, state[name])]
      end
      head = Gem::Version.new(state.fetch("catalog_head").fetch("version").to_s)
      (PROJECT_STATE_ROLES - ["catalog_head"]).each do |name|
        version = state.fetch(name).fetch("version").to_s
        if Gem::Version.new(version) > head
          raise ConfigurationError, "#{name} #{version} cannot be newer than catalog_head #{head}"
        end
      end
      paths.fetch(role)
    rescue Psych::Exception, SystemCallError => error
      raise ConfigurationError, "Invalid project state #{manifest}: #{error.message}"
    end

    # Verify an exact version, canonical basename, size and SHA-256 against
    # the manifest directory. Returns the path or raises ConfigurationError.
    def validate_project_state_role(manifest, role, entry)
      fields = %w[version filename sha256 bytes]
      unless entry.is_a?(Hash) && entry.keys.size == fields.size && fields.all? { |field| entry.key?(field) }
        raise ConfigurationError, "Invalid project-state fields for #{role}"
      end
      version = entry.fetch("version").to_s
      filename = entry.fetch("filename")
      expected_sha = entry.fetch("sha256")
      expected_bytes = entry.fetch("bytes")
      unless version.match?(/\A\d+(?:\.\d+)*\z/) &&
             filename == "5e_Adventure_Master_Catalog_#{version}.xlsx" &&
             expected_sha.is_a?(String) && expected_sha.match?(/\A[0-9a-f]{64}\z/) &&
             expected_bytes.is_a?(Integer) && expected_bytes.positive?
        raise ConfigurationError, "Invalid project-state entry for #{role}"
      end

      path = File.join(File.dirname(manifest), filename)
      raise ConfigurationError, "Missing #{role} catalog workbook: #{path}" unless File.file?(path)
      actual_bytes = File.size(path)
      unless actual_bytes == expected_bytes
        raise ConfigurationError,
              "#{role} catalog byte-size mismatch: expected #{expected_bytes}, got #{actual_bytes}: #{path}"
      end
      actual_sha = Digest::SHA256.file(path).hexdigest
      unless actual_sha == expected_sha
        raise ConfigurationError,
              "#{role} catalog SHA-256 mismatch: expected #{expected_sha}, got #{actual_sha}: #{path}"
      end
      path
    end

    def load_yaml(path)
      return {} unless path
      expanded = File.expand_path(path)
      raise ConfigurationError, "Missing config file: #{expanded}" unless File.file?(expanded)
      raw = YAML.safe_load_file(expanded, aliases: true) || {}
      stringify_keys(raw)
    rescue Psych::Exception => e
      raise ConfigurationError, "Invalid YAML in #{path}: #{e.message}"
    end

    def stringify_keys(value)
      case value
      when Hash
        value.each_with_object({}) { |(k, v), h| h[k.to_s] = stringify_keys(v) }
      when Array
        value.map { |v| stringify_keys(v) }
      else
        value
      end
    end

    def deep_merge!(base, other)
      other.each do |key, value|
        if base[key].is_a?(Hash) && value.is_a?(Hash)
          deep_merge!(base[key], value)
        else
          base[key] = value
        end
      end
      base
    end

    def apply_environment!
      ENV_MAP.each do |env_name, path|
        next if ENV[env_name].nil? || ENV[env_name].empty?
        cursor = @data
        path[0...-1].each { |key| cursor = (cursor[key] ||= {}) }
        cursor[path.last] = ENV[env_name]
      end
    end

    # Expand selected roots relative to the project. Explicit null roots in the
    # public template require operator input; raise ConfigurationError if unset.
    def normalize_paths!
      %w[xlsx_root specification_root source_root output_root].each do |key|
        value = dig("paths", key)
        if @data.fetch("paths", {}).key?(key) && value.nil?
          raise ConfigurationError, "Select paths.#{key} explicitly in --config or its AF_* environment override"
        end
        next if value.nil? || Pathname.new(value).absolute?
        @data["paths"][key] = File.expand_path(value, @project_root)
      end
    end

    def resolve_under(root, path)
      raise ConfigurationError, "Missing configured path component" if root.nil? || path.nil?
      return File.expand_path(path) if Pathname.new(path).absolute?
      File.expand_path(path, root)
    end
  end
end
