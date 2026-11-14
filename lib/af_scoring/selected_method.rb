# frozen_string_literal: true

require "digest"

module AFScoring
  # Bind public scoring definitions to reviewed bytes, including rules outside prompt sections.
  # Configured historical definitions retain their existing loaders and identities.
  class SelectedMethod
    PUBLIC_REVISION = "394a44c2c2052ce2eeb6d28cd7647ad8a50acfcf"
    PUBLIC_IDENTITY = "af-specification-md@#{PUBLIC_REVISION}"
    INVENTORY_SHA256 = "5ebb0fffcafa165a71bd3afef70e483217074d788d02ff9241ab3cedfd6bf0e6"
    PUBLIC_FILES = {
      "afao" => ["AdventureFinder_Analysis_Ontology_AFAO_v1.6.1.md", "dcfad224ab9517272504a508f935a804032d04a7c812ede10498921ce4585fa1"],
      "assessment_spec" => ["AdventureFinder_Analysis_Data_Assessment_Specification_v0.1.md", "bbd90a20daafb58c3daee3af758972f09f658b271086e95060ce01df44197ad0"]
    }.freeze

    # Select a public or configured historical method from Config; reject unknown identities.
    # Returns an instance; invalid selection raises ConfigurationError.
    def initialize(config)
      @config = config
      @identity = config.dig("method", "identity") || "configured"
      unless [PUBLIC_IDENTITY, "configured"].include?(@identity)
        raise ConfigurationError, "Unsupported method identity: #{@identity.inspect}"
      end
    end

    # Return whether this selection requires the pinned public definitions; never raises.
    def public?
      @identity == PUBLIC_IDENTITY
    end

    # Verify the selected public inventory and complete required files on every preparation.
    # Optional loaded texts bind the parsers' actual input bytes too. Returns nil;
    # missing/mismatched definitions raise SpecificationError before provider construction.
    def verify!(afao: nil, assessment_spec: nil)
      return unless public?

      root = @config.dig("paths", "specification_root")
      verify_digest!(File.join(root, "documents.json"), INVENTORY_SHA256)
      PUBLIC_FILES.each do |key, (basename, digest)|
        unless @config.dig("files", key) == basename
          raise SpecificationError, "Public method requires files.#{key}: #{basename}"
        end
        verify_digest!(File.join(root, basename), digest)
        loaded = key == "afao" ? afao : assessment_spec
        if loaded && Digest::SHA256.hexdigest(loaded.text) != digest
          raise SpecificationError, "Loaded #{key} bytes do not match selected public method"
        end
      end
      nil
    end

    # Return public source/content and effective loader/profile provenance, or nil for
    # historical configuration. Environment values count only with explicitly loaded modules.
    # This is content identity, not qualification; no files or providers are opened here.
    def binding
      return unless public?

      profile_modules = PromptBuilder.ancestors.select { |ancestor| ancestor.const_defined?(:PROFILE_ENV, false) }
      profiles = profile_modules.filter_map do |ancestor|
        name = ancestor.const_get(:PROFILE_ENV)
        value = ENV[name]
        [name, value] unless value.nil? || value.empty?
      end.to_h
      nos_factory = defined?(NosTwoStageRunnerFactory) && Runner.singleton_class.ancestors.include?(NosTwoStageRunnerFactory)
      retained_modules = profile_modules.map(&:name)
      retained_modules << NosTwoStageRunnerFactory.name if nos_factory
      if nos_factory && NosTwoStage.enabled?
        profiles[NosTwoStage::PROFILE_ENV] = NosTwoStage.selected_profile
      end
      {
        "identity" => @identity,
        "repository" => "dtnorris/af-specification-md",
        "revision" => PUBLIC_REVISION,
        "inventory_sha256" => INVENTORY_SHA256,
        "files" => PUBLIC_FILES.values.to_h,
        "loader" => retained_modules.empty? ? "canonical" : "retained",
        "retained_modules" => retained_modules,
        "retained_profiles" => profiles
      }
    end

    private

    # Check one required file against its trusted digest; return nil or raise
    # SpecificationError for absence/corruption. Filesystem access errors propagate.
    def verify_digest!(path, expected)
      raise SpecificationError, "Missing public method file: #{path}" unless File.file?(path)
      unless Digest::SHA256.file(path).hexdigest == expected
        raise SpecificationError, "Public method SHA-256 mismatch: #{path}"
      end
      nil
    end
  end
end
