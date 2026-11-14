# frozen_string_literal: true

module AFScoring
  class Error < StandardError; end
  class ConfigurationError < Error; end
  class CatalogError < Error; end
  class AdventureNotFound < CatalogError; end
  class SourceResolutionError < Error; end
  class AmbiguousSourceError < SourceResolutionError; end
  class SourceBoundaryError < Error; end
  class SpecificationError < Error; end
  class ProviderError < Error; end
  class NormalizationError < Error; end
  class ValidationError < Error
    attr_reader :failures

    def initialize(message = "Assessment validation failed", failures: [])
      @failures = failures
      super(message)
    end
  end
  class RegressionReferenceError < Error; end
end
