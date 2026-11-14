# frozen_string_literal: true

module AFScoring
  module DimensionGroups
    GROUPS = {
      "sessions_levels" => ["# of Sessions", "Levels"],
      "play_mix" => [
        "Combat Emphasis",
        "Exploration Emphasis",
        "Social Interaction Emphasis",
        "Investigation Emphasis",
        "Puzzle / Problem-Solving Emphasis"
      ],
      "challenge_character" => [
        "Tactical Complexity",
        "Lethality / Failure Severity",
        "Rules / System-Mastery Demand"
      ],
      "adventure_structure" => [
        "Structural Openness",
        "Consequential Player Agency"
      ],
      "experience_tone" => [
        "Seriousness",
        "Darkness / Horror Intensity",
        "Fantastic Weirdness"
      ],
      "gm_demands" => [
        "GM Preparation Burden",
        "GM Improvisation Demand"
      ],
      "beginner_suitability" => [
        "Player Beginner Suitability",
        "GM Beginner Suitability"
      ]
    }.freeze

    MATCHING = ["# of Sessions", "Levels"].freeze
    INTERPRETIVE = GROUPS.reject { |key, _| key == "sessions_levels" }.values.flatten.freeze
    ALL = [*MATCHING, *INTERPRETIVE].freeze

    def self.fetch(name)
      GROUPS.fetch(name) { raise SpecificationError, "Unknown scoring group: #{name}" }
    end

    def self.group_for_dimension(name)
      group = GROUPS.find { |_group_name, dimensions| dimensions.include?(name) }
      return group.first if group

      raise SpecificationError,
            "Unknown scoring dimension: #{name}. Expected one of: #{ALL.join(', ')}"
    end
  end
end
