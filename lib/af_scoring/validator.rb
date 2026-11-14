# frozen_string_literal: true

module AFScoring
  class Validator
    EXPECTED_METRICS = ["# of Sessions", "Level Start", "Level End", *DimensionGroups::INTERPRETIVE].freeze

    def validate!(package, expected_metrics: EXPECTED_METRICS)
      failures = []
      metrics = package.metrics
      names = metrics.map(&:metric)
      missing = expected_metrics - names
      extra = names - expected_metrics
      duplicates = names.group_by(&:itself).select { |_k, v| v.length > 1 }.keys
      failures << "Missing required metrics: #{missing.join(', ')}" unless missing.empty?
      failures << "Unexpected metrics: #{extra.join(', ')}" unless extra.empty?
      failures << "Duplicate metrics: #{duplicates.join(', ')}" unless duplicates.empty?

      metrics.each { |metric| validate_metric(metric, failures) }
      validate_levels(metrics, failures)

      raise ValidationError.new(failures: failures), failures.join("; ") unless failures.empty?
      true
    end

    private

    def validate_metric(metric, failures)
      validate_audit_fields(metric, failures)
      case metric.kind
      when "sessions" then validate_sessions(metric, failures)
      when "level" then validate_level(metric, failures)
      when "interpretive" then validate_interpretive(metric, failures)
      else failures << "#{metric.metric}: unknown metric kind #{metric.kind.inspect}"
      end
    end

    def validate_audit_fields(metric, failures)
      failures << "#{metric.metric}: rationale is required" if blank?(metric.rationale)
      if metric.evidence.nil? || metric.evidence.empty?
        failures << "#{metric.metric}: at least one evidence item is required"
      else
        metric.evidence.each_with_index do |item, i|
          failures << "#{metric.metric}: evidence #{i + 1} locator is required" if blank?(item.locator)
          failures << "#{metric.metric}: evidence #{i + 1} note is required" if blank?(item.note)
        end
      end
    end

    def validate_sessions(metric, failures)
      unless ["Scored", "Insufficient Evidence"].include?(metric.assessment_state)
        failures << "# of Sessions: invalid assessment state #{metric.assessment_state.inspect}"
        return
      end
      if metric.assessment_state == "Scored"
        failures << "# of Sessions: value must be a positive integer" unless positive_integer?(metric.value)
        failures << "# of Sessions: practical range low must be a positive integer" unless positive_integer?(metric.range_low)
        failures << "# of Sessions: practical range high must be a positive integer" unless positive_integer?(metric.range_high)
        if positive_integer?(metric.range_low) && positive_integer?(metric.range_high)
          failures << "# of Sessions: practical range low exceeds high" if metric.range_low > metric.range_high
          if positive_integer?(metric.value) && !(metric.range_low..metric.range_high).cover?(metric.value)
            failures << "# of Sessions: value must fall within practical range"
          end
        end
        validate_confidence(metric, failures)
        failures << "# of Sessions: path_sensitive must be boolean" unless boolean?(metric.path_sensitive)
      else
        failures << "# of Sessions: Insufficient Evidence must not contain a numeric value" unless metric.value.nil?
        failures << "# of Sessions: Insufficient Evidence must not contain confidence" unless metric.confidence.nil?
      end
    end

    def validate_level(metric, failures)
      allowed = ["Scored", "Uncertain / Requires Source Verification"]
      unless allowed.include?(metric.assessment_state)
        failures << "#{metric.metric}: invalid assessment state #{metric.assessment_state.inspect}"
        return
      end
      if metric.assessment_state == "Scored"
        unless metric.value.is_a?(Integer) && metric.value.between?(1, 20)
          failures << "#{metric.metric}: scored value must be an integer from 1 through 20"
        end
      elsif !metric.value.nil?
        failures << "#{metric.metric}: uncertain state must not contain an integer value"
      end
    end

    def validate_interpretive(metric, failures)
      unless ["Scored", "Insufficient Evidence"].include?(metric.assessment_state)
        failures << "#{metric.metric}: invalid assessment state #{metric.assessment_state.inspect}"
        return
      end
      if metric.assessment_state == "Scored"
        unless metric.value.is_a?(Integer) && metric.value.between?(1, 5)
          failures << "#{metric.metric}: score must be an integer from 1 through 5"
        end
        validate_confidence(metric, failures)
        failures << "#{metric.metric}: path_sensitive must be boolean" unless boolean?(metric.path_sensitive)
        if metric.value.is_a?(Integer)
          failures << "#{metric.metric}: adjacent-lower falsification is required for scores above 1" if metric.value > 1 && blank?(metric.adjacent_lower_reason)
          failures << "#{metric.metric}: adjacent-higher falsification is required for scores below 5" if metric.value < 5 && blank?(metric.adjacent_higher_reason)
        end
      else
        failures << "#{metric.metric}: Insufficient Evidence must not contain a score" unless metric.value.nil?
        failures << "#{metric.metric}: Insufficient Evidence must not contain confidence" unless metric.confidence.nil?
      end
    end

    def validate_confidence(metric, failures)
      unless metric.confidence.is_a?(Integer) && metric.confidence.between?(0, 100)
        failures << "#{metric.metric}: confidence must be an integer from 0 through 100"
      end
    end

    def validate_levels(metrics, failures)
      start = metrics.find { |m| m.metric == "Level Start" }
      finish = metrics.find { |m| m.metric == "Level End" }
      return unless start&.assessment_state == "Scored" && finish&.assessment_state == "Scored"
      failures << "Level Start cannot exceed Level End" if start.value > finish.value
    end

    def blank?(value)
      value.nil? || value.to_s.strip.empty?
    end

    def positive_integer?(value)
      value.is_a?(Integer) && value.positive?
    end

    def boolean?(value)
      value == true || value == false
    end
  end
end
