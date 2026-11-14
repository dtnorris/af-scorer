# frozen_string_literal: true

module AFScoring
  class ScoringTarget
    attr_reader :group_name, :dimensions

    def self.for_group(group_name)
      new(group_name: group_name, dimensions: DimensionGroups.fetch(group_name))
    end

    def self.for_dimension(dimension)
      new(
        group_name: DimensionGroups.group_for_dimension(dimension),
        dimensions: [dimension]
      )
    end

    def initialize(group_name:, dimensions:)
      allowed = DimensionGroups.fetch(group_name)
      unknown = dimensions - allowed
      raise SpecificationError, "Dimensions not in #{group_name}: #{unknown.join(', ')}" unless unknown.empty?
      raise SpecificationError, "Scoring target must contain at least one dimension" if dimensions.empty?

      @group_name = group_name
      @dimensions = dimensions.dup.freeze
    end

    def metric_names
      return dimensions unless group_name == "sessions_levels"

      names = []
      names << "# of Sessions" if dimensions.include?("# of Sessions")
      names.concat(["Level Start", "Level End"]) if dimensions.include?("Levels")
      names
    end

    def full_group?
      dimensions == DimensionGroups.fetch(group_name)
    end

    def label
      full_group? ? group_name : dimensions.join(" + ")
    end

    def artifact_name
      return group_name if full_group?

      "dimension_#{slug(dimensions.join('_'))}"
    end

    private

    def slug(value)
      value
        .gsub("#", "number")
        .downcase
        .gsub(/[^a-z0-9]+/, "_")
        .gsub(/\A_+|_+\z/, "")
    end
  end
end
