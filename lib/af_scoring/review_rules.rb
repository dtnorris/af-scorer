# frozen_string_literal: true

module AFScoring
  class ReviewRules
    def initialize(low_confidence_threshold: 60, moderate_confidence_ceiling: 74)
      @low_confidence_threshold = Integer(low_confidence_threshold)
      @moderate_confidence_ceiling = Integer(moderate_confidence_ceiling)
    end

    def apply!(package, group_observations: [])
      package_flags = Array(package.source_warnings).map { |warning| source_warning_flag(warning) }.compact

      group_observations.each do |obs|
        package_flags << "REVIEW:SOURCE_BOUNDARY_UNCERTAINTY" if obs["source_boundary_uncertainty"]
        package_flags << "REVIEW:POSSIBLE_SPEC_CONTRADICTION" if obs["possible_spec_contradiction"]
      end

      package.metrics.each do |metric|
        flags = []
        flags << "REVIEW:INSUFFICIENT_EVIDENCE" if metric.insufficient_evidence?
        flags << "REVIEW:LEVEL_UNCERTAIN" if metric.uncertain?
        if metric.scored? && metric.confidence.is_a?(Integer)
          if metric.confidence < @low_confidence_threshold
            flags << "REVIEW:LOW_CONFIDENCE"
          elsif metric.confidence <= @moderate_confidence_ceiling
            flags << "INFO:MODERATE_CONFIDENCE"
          end
        end
        flags << "REVIEW:RUBRIC_AMBIGUITY" if metric.rubric_ambiguity
        flags << "REVIEW:EVIDENCE_INSUFFICIENT" if metric.evidence_sufficient == false
        if metric.path_sensitive == true
          flags << "INFO:PATH_SENSITIVE"
          flags << "REVIEW:PATH_VARIATION_PRESSURES_ANCHOR" if metric.path_variation_affects_anchor == true
        end
        metric.review_flags = flags.uniq
      end

      package.package_review_flags = package_flags.uniq
      any_review = package.package_review_flags.any? { |f| f.start_with?("REVIEW:") } ||
                   package.metrics.any? { |m| m.review_flags.any? { |f| f.start_with?("REVIEW:") } }
      package.review_disposition = any_review ? "REVIEW_REQUIRED" : "NO_AUTOMATIC_REVIEW_TRIGGER"
      package
    end

    private

    def source_warning_flag(warning)
      case warning
      when "SOURCE_BOUNDARY_UNVERIFIED" then "REVIEW:SOURCE_BOUNDARY_UNVERIFIED"
      when "SOURCE_RESOLVED_BY_FILENAME" then "INFO:SOURCE_RESOLVED_BY_FILENAME"
      else
        warning.start_with?("Required canonical page marker") ? "REVIEW:SOURCE_BOUNDARY_UNVERIFIED" : nil
      end
    end
  end
end
