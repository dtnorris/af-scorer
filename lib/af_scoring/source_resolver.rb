# frozen_string_literal: true

require_relative "source_markdown_owner"

module AFScoring
  # Preserve the scorer's lazy registry reader and public Resolution shape.
  class SourceResolver
    REGISTRY_SCHEMA_VERSION = "adventurefinder-source-registry/v0.1"
    Resolution = Struct.new(:path, :strategy, :warnings, :page_marker_offset, keyword_init: true)

    # Bind caller-selected roots to MD; mapping checks retain their lazy timing.
    # Raises the scorer's configuration/resolution errors on refusal.
    def initialize(source_root:, registry_path:)
      owner = SourceMarkdownOwner.load!(error_class: ConfigurationError)
      @resolver = translate_owner_errors { owner::SourceResolver.new(source_root:, registry_path:) }
    end

    # Resolve a scorer adventure using MD and return the historical caller type;
    # warnings, strategies, offsets and scorer error classes remain unchanged.
    def resolve(adventure)
      translate_owner_errors { Resolution.new(**@resolver.resolve(adventure).to_h) }
    end

    private

    # Execute a source operation; translate owner errors to existing scorer errors.
    # Unexpected exceptions retain their native type and diagnostic.
    def translate_owner_errors
      yield
    rescue AFSourceMD::AmbiguousSourceError => error
      raise AmbiguousSourceError, error.message
    rescue AFSourceMD::SourceResolutionError => error
      raise SourceResolutionError, error.message
    rescue AFSourceMD::ConfigurationError => error
      raise ConfigurationError, error.message
    end
  end
end
