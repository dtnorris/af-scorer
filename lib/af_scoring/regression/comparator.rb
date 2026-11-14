# frozen_string_literal: true

module AFScoring
  module Regression
    Comparison = Struct.new(
      :metric, :expected, :proposed, :exact_match, :numeric_delta, :note,
      keyword_init: true
    )

    class Comparator
      def compare(package, expected)
        expected.map do |metric_name, expected_value|
          metric = package.metrics.find { |m| m.metric == metric_name }
          proposed = proposed_value(metric)
          exact = equivalent?(expected_value, proposed)
          delta = if expected_value.is_a?(Numeric) && proposed.is_a?(Numeric)
                    proposed - expected_value
                  end
          Comparison.new(
            metric: metric_name,
            expected: expected_value,
            proposed: proposed,
            exact_match: exact,
            numeric_delta: delta,
            note: metric.nil? ? "Metric missing from proposed package" : nil
          )
        end.sort_by(&:metric)
      end

      private

      def proposed_value(metric)
        return nil unless metric
        return "Uncertain" if metric.uncertain?
        return "Insufficient Evidence" if metric.insufficient_evidence?
        metric.value
      end

      def equivalent?(expected, proposed)
        if expected.to_s.match?(/uncertain/i)
          proposed.to_s.match?(/uncertain/i)
        else
          expected == proposed
        end
      end
    end
  end
end
