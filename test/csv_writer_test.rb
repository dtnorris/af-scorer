# frozen_string_literal: true
require_relative "test_helper"
require "csv"

class CsvWriterTest < Minitest::Test
  def test_writes_long_form_csv
    metric = AFScoring::MetricAssessment.new(
      metric: "Combat Emphasis", kind: "interpretive", assessment_state: "Scored", value: 3,
      confidence: 85, path_sensitive: false, path_variation_affects_anchor: false,
      rationale: "r", evidence: [AFScoring::Evidence.new(locator: "PAGE: 1", note: "n")],
      adjacent_lower_reason: "lower", adjacent_higher_reason: "higher",
      review_flags: [], group: "play_mix"
    )
    adv = AFScoring::Adventure.new(id: "ADV-0001", title: "Fixture", source_book: "Book", publisher: "Pub", start_page: 1, end_page: 2)
    package = AFScoring::AssessmentPackage.new(
      run_id: "run", status: "PROPOSED", review_disposition: "NO_AUTOMATIC_REVIEW_TRIGGER",
      adventure: adv, afao_version: "1.0", assessment_spec_version: "0.1", provider: "fake", model: "fake",
      source_file: "source.md", source_scope: "canonical_page_slice", metrics: [metric], package_review_flags: []
    )
    Dir.mktmpdir do |dir|
      path = AFScoring::CsvWriter.new(dir).write_package(package)
      rows = CSV.read(path, headers: true)
      assert_equal 1, rows.length
      assert_equal "PROPOSED", rows[0]["status"]
      assert_equal "Combat Emphasis", rows[0]["metric"]
      assert_includes rows[0]["evidence"], "PAGE: 1"
    end
  end

  def test_writes_experimental_run_metadata_sidecar
    Dir.mktmpdir do |dir|
      writer = AFScoring::CsvWriter.new(dir)
      path = writer.write_run_metadata(
        adventure_id: "ADV-0001",
        run_id: "run",
        metadata: {
          "prompt_profile" => "experimental_combat_guardrail_v0.7",
          "experimental" => true
        }
      )

      payload = JSON.parse(File.read(path))
      assert_equal "experimental_combat_guardrail_v0.7", payload["prompt_profile"]
      assert_equal true, payload["experimental"]
      assert_match %r{/raw/ADV-0001/run/run_metadata\.json\z}, path
    end
  end
end
