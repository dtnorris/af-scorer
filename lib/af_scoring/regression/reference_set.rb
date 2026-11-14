# frozen_string_literal: true

module AFScoring
  module Regression
    class ReferenceSet
      attr_reader :ids, :workbook_headers

      def initialize(workbook_path:, sheet_name: "AFAO 1.0 ADV References")
        rows = XlsxReader.new(workbook_path).rows(sheet_name: sheet_name)
        raise RegressionReferenceError, "Regression reference workbook is empty" if rows.empty?
        @workbook_headers = rows.shift.map { |v| v.to_s.strip }
        id_index = @workbook_headers.index("Adventure ID")
        raise RegressionReferenceError, "Regression workbook does not contain Adventure ID" unless id_index
        @ids = rows.map { |row| row[id_index].to_s.strip }.grep(/\AADV-\d{4}\z/).uniq
      end

      # Return AFAO expectations only for a verified historical context, after scoring.
      # Explicit new-library selections return {}; absent/changed bindings raise
      # ConfigurationError. The workbook remains an enumerator, not identity evidence.
      def expected_for(adventure_id, afao:, eligibility: nil)
        unless eligibility.is_a?(TargetEligibility)
          raise ConfigurationError, "Regression expected values require resolved target eligibility"
        end
        eligibility.verify_regression!.verify!(adventure_id: adventure_id, afao: afao)
        return {} unless eligibility.historical?

        # The configured AFAO is the score authority. The historical reference
        # workbook supplies IDs for --regression-all enumeration, but must not
        # suppress calibration expectations added by later AFAO versions.
        afao.calibration_expectations.fetch(adventure_id, {})
      end

      def workbook_contains_score_columns?
        @workbook_headers.any? do |header|
          header.match?(/score|sessions|level start|level end|confidence|path sensitive/i)
        end
      end

      def provenance_note
        if workbook_contains_score_columns?
          "Reference workbook supplies score-like columns; v0.1 still uses explicit AFAO calibration tables as the score authority."
        else
          "Workbook supplies the referenced Adventure-ID set only; expected values are derived from explicit calibration tables in the configured AFAO after scoring."
        end
      end
    end
  end
end
