# frozen_string_literal: true
require_relative "test_helper"

class RegressionTest < Minitest::Test
  def test_reference_workbook_indexes_ids_and_afao_supplies_expected_values_afterward
    Dir.mktmpdir do |dir|
      workbook = File.join(dir, "refs.xlsx")
      TestSupport.build_xlsx(workbook, sheet_name: "AFAO 1.0 ADV References", rows: [
        ["Adventure ID", "Adventure Title", "AFAO Reference Count"],
        ["ADV-0001", "Fixture Adventure", 20]
      ])
      afao_path = File.join(dir, "afao.md")
      File.write(afao_path, TestSupport.minimal_afao)
      afao, eligibility = TestSupport.historical_afao(afao_path)
      refs = AFScoring::Regression::ReferenceSet.new(workbook_path: workbook)
      refute refs.workbook_contains_score_columns?
      assert_equal ["ADV-0001"], refs.ids
      expected = refs.expected_for("ADV-0001", afao: afao, eligibility: eligibility)
      assert_equal 2, expected["# of Sessions"]
      assert_equal 3, expected["GM Beginner Suitability"]
    end
  end

  def test_afao_expectation_is_available_even_when_adventure_is_absent_from_reference_workbook
    Dir.mktmpdir do |dir|
      workbook = File.join(dir, "refs.xlsx")
      TestSupport.build_xlsx(workbook, sheet_name: "AFAO 1.0 ADV References", rows: [
        ["Adventure ID", "Adventure Title", "AFAO Reference Count"],
        ["ADV-9999", "Historical Reference Only", 1]
      ])
      afao_path = File.join(dir, "afao.md")
      File.write(afao_path, TestSupport.minimal_afao)
      afao, eligibility = TestSupport.historical_afao(afao_path)
      refs = AFScoring::Regression::ReferenceSet.new(workbook_path: workbook)

      refute_includes refs.ids, "ADV-0001"
      expected = refs.expected_for("ADV-0001", afao: afao, eligibility: eligibility)
      assert_equal 3, expected["Combat Emphasis"]
    end
  end

  def test_comparator_reports_numeric_delta
    metric = AFScoring::MetricAssessment.new(metric: "Combat Emphasis", assessment_state: "Scored", value: 4)
    package = AFScoring::AssessmentPackage.new(metrics: [metric])
    comparison = AFScoring::Regression::Comparator.new.compare(package, { "Combat Emphasis" => 3 }).first
    refute comparison.exact_match
    assert_equal 1, comparison.numeric_delta
  end
end
