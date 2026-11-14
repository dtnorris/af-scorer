# frozen_string_literal: true

module AFScoring
  class SchemaBuilder
    def self.for_group(group_name, dimensions: nil)
      requested = requested_dimensions(group_name, dimensions)
      return sessions_levels_schema(requested) if group_name == "sessions_levels"

      interpretive_schema(group_name, requested)
    end

    def self.evidence_schema
      {
        "type" => "object",
        "additionalProperties" => false,
        "properties" => {
          "locator" => { "type" => "string" },
          "note" => { "type" => "string" }
        },
        "required" => %w[locator note]
      }
    end

    def self.sessions_levels_schema(dimensions = DimensionGroups.fetch("sessions_levels"))
      properties = {
        "group" => { "type" => "string", "enum" => ["sessions_levels"] },
        "group_observations" => observations_schema
      }
      required = %w[group]

      if dimensions.include?("# of Sessions")
        properties["sessions"] = sessions_schema
        required << "sessions"
      end
      if dimensions.include?("Levels")
        properties["level_start"] = level_schema
        properties["level_end"] = level_schema
        required.concat(%w[level_start level_end])
      end
      required << "group_observations"

      {
        "type" => "object",
        "additionalProperties" => false,
        "properties" => properties,
        "required" => required
      }
    end

    def self.sessions_schema
      required = %w[
        assessment_state normalized_sessions practical_range_low practical_range_high confidence
        path_sensitive rationale evidence rubric_ambiguity evidence_sufficient
      ]
      audit_properties = {
        "rationale" => { "type" => "string" },
        "evidence" => { "type" => "array", "items" => evidence_schema, "minItems" => 1 },
        "rubric_ambiguity" => { "type" => "boolean" }
      }

      scored = {
        "type" => "object",
        "additionalProperties" => false,
        "properties" => audit_properties.merge(
          "assessment_state" => { "type" => "string", "enum" => ["Scored"] },
          "normalized_sessions" => { "type" => "integer", "minimum" => 1 },
          "practical_range_low" => { "type" => "integer", "minimum" => 1 },
          "practical_range_high" => { "type" => "integer", "minimum" => 1 },
          "confidence" => { "type" => "integer", "minimum" => 0, "maximum" => 100 },
          "path_sensitive" => { "type" => "boolean" },
          "evidence_sufficient" => { "type" => "boolean", "enum" => [true] }
        ),
        "required" => required
      }

      insufficient = {
        "type" => "object",
        "additionalProperties" => false,
        "properties" => audit_properties.merge(
          "assessment_state" => { "type" => "string", "enum" => ["Insufficient Evidence"] },
          "normalized_sessions" => { "type" => "null" },
          "practical_range_low" => { "type" => "null" },
          "practical_range_high" => { "type" => "null" },
          "confidence" => { "type" => "null" },
          "path_sensitive" => { "type" => "null" },
          "evidence_sufficient" => { "type" => "boolean", "enum" => [false] }
        ),
        "required" => required
      }

      { "oneOf" => [scored, insufficient] }
    end

    def self.level_schema
      {
        "type" => "object",
        "additionalProperties" => false,
        "properties" => {
          "assessment_state" => {
            "type" => "string",
            "enum" => ["Scored", "Uncertain / Requires Source Verification"]
          },
          "value" => { "type" => ["integer", "null"], "minimum" => 1, "maximum" => 20 },
          "rationale" => { "type" => "string" },
          "evidence" => { "type" => "array", "items" => evidence_schema, "minItems" => 1 },
          "rubric_ambiguity" => { "type" => "boolean" },
          "evidence_sufficient" => { "type" => "boolean" }
        },
        "required" => %w[assessment_state value rationale evidence rubric_ambiguity evidence_sufficient]
      }
    end

    def self.interpretive_schema(group_name, dimensions = DimensionGroups.fetch(group_name))
      {
        "type" => "object",
        "additionalProperties" => false,
        "properties" => {
          "group" => { "type" => "string", "enum" => [group_name] },
          "dimensions" => {
            "type" => "array",
            "minItems" => dimensions.length,
            "maxItems" => dimensions.length,
            "items" => interpretive_dimension_schema(dimensions)
          },
          "group_observations" => observations_schema
        },
        "required" => %w[group dimensions group_observations]
      }
    end

    def self.interpretive_dimension_schema(dimensions)
      {
        "type" => "object",
        "additionalProperties" => false,
        "properties" => {
          "dimension" => { "type" => "string", "enum" => dimensions },
          "assessment_state" => { "type" => "string", "enum" => ["Scored", "Insufficient Evidence"] },
          "score" => { "type" => ["integer", "null"], "minimum" => 1, "maximum" => 5 },
          "confidence" => {
            "type" => ["integer", "null"],
            "minimum" => 0,
            "maximum" => 100,
            "description" => "For a scored assessment, confidence that the assigned rubric value is the " \
                             "best-supported value given the supplied published evidence and rubric; 0 means " \
                             "essentially no supportable confidence and does not alter the score."
          },
          "path_sensitive" => { "type" => ["boolean", "null"] },
          "path_variation_affects_anchor" => { "type" => ["boolean", "null"] },
          "adjacent_lower_reason" => { "type" => ["string", "null"] },
          "adjacent_higher_reason" => { "type" => ["string", "null"] },
          "rationale" => { "type" => "string" },
          "evidence" => { "type" => "array", "items" => evidence_schema, "minItems" => 1 },
          "rubric_ambiguity" => { "type" => "boolean" },
          "evidence_sufficient" => { "type" => "boolean" }
        },
        "required" => %w[
          dimension assessment_state score confidence path_sensitive path_variation_affects_anchor
          adjacent_lower_reason adjacent_higher_reason rationale evidence rubric_ambiguity evidence_sufficient
        ]
      }
    end

    def self.observations_schema
      {
        "type" => "object",
        "additionalProperties" => false,
        "properties" => {
          "source_boundary_uncertainty" => { "type" => "boolean" },
          "possible_spec_contradiction" => { "type" => "boolean" },
          "notes" => { "type" => "string" }
        },
        "required" => %w[source_boundary_uncertainty possible_spec_contradiction notes]
      }
    end

    def self.requested_dimensions(group_name, dimensions)
      allowed = DimensionGroups.fetch(group_name)
      requested = dimensions || allowed
      unknown = requested - allowed
      unless unknown.empty?
        raise SpecificationError, "Dimensions not in #{group_name}: #{unknown.join(', ')}"
      end
      raise SpecificationError, "Scoring schema must contain at least one dimension" if requested.empty?

      requested
    end
    private_class_method :requested_dimensions
  end
end
