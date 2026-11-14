# frozen_string_literal: true

require "csv"
require "json"
require "fileutils"
require "digest"
require "time"

module AFScoring
  class CsvWriter
    ASSESSMENT_HEADERS = %w[
      run_id status review_disposition adventure_id adventure_title source_book book_publisher
      start_page end_page afao_version assessment_spec_version provider model source_file source_scope
      group metric_kind metric assessment_state value range_low range_high confidence path_sensitive
      path_variation_affects_anchor rationale adjacent_lower_reason adjacent_higher_reason evidence
      metric_review_flags package_review_flags
    ].freeze

    REGRESSION_HEADERS = %w[
      run_id adventure_id adventure_title metric expected proposed exact_match numeric_delta note
    ].freeze

    def initialize(output_root)
      @output_root = File.expand_path(output_root)
    end

    def write_package(package)
      dir = File.join(@output_root, "assessments")
      FileUtils.mkdir_p(dir)
      path = File.join(dir, "#{package.adventure.id}_#{package.run_id}.csv")
      CSV.open(path, "w", write_headers: true, headers: ASSESSMENT_HEADERS) do |csv|
        package.metrics.each do |metric|
          csv << assessment_row(package, metric)
        end
      end
      path
    end

    def write_raw(adventure_id:, run_id:, group_name:, raw:)
      dir = File.join(@output_root, "raw", adventure_id, run_id)
      FileUtils.mkdir_p(dir)
      path = File.join(dir, "#{group_name}.json")
      File.write(path, JSON.pretty_generate(raw))
      path
    end

    def write_request(adventure_id:, run_id:, group_name:, request:, prompt_sha256:, schema_sha256:)
      dir = File.join(@output_root, "raw", adventure_id, run_id)
      FileUtils.mkdir_p(dir)
      serialized_request = JSON.generate(request)
      payload = {
        "record_type" => "provider_request",
        "recorded_at" => Time.now.utc.iso8601,
        "recorded_before_inference" => true,
        "prompt_sha256" => prompt_sha256,
        "schema_sha256" => schema_sha256,
        "request_sha256" => Digest::SHA256.hexdigest(serialized_request),
        "request" => request
      }
      path = File.join(dir, "#{group_name}_request.json")
      File.write(path, JSON.pretty_generate(payload))
      path
    end

    def write_run_metadata(adventure_id:, run_id:, metadata:)
      dir = File.join(@output_root, "raw", adventure_id, run_id)
      FileUtils.mkdir_p(dir)
      path = File.join(dir, "run_metadata.json")
      File.write(path, JSON.pretty_generate(metadata))
      path
    end

    def write_regression(package, comparisons)
      dir = File.join(@output_root, "regression")
      FileUtils.mkdir_p(dir)
      path = File.join(dir, "#{package.adventure.id}_#{package.run_id}_regression.csv")
      CSV.open(path, "w", write_headers: true, headers: REGRESSION_HEADERS) do |csv|
        comparisons.each do |comparison|
          csv << [
            package.run_id,
            package.adventure.id,
            package.adventure.title,
            comparison.metric,
            comparison.expected,
            comparison.proposed,
            comparison.exact_match,
            comparison.numeric_delta,
            comparison.note
          ]
        end
      end
      path
    end

    private

    def assessment_row(package, metric)
      [
        package.run_id,
        package.status,
        package.review_disposition,
        package.adventure.id,
        package.adventure.title,
        package.adventure.source_book,
        package.adventure.publisher,
        package.adventure.start_page,
        package.adventure.end_page,
        package.afao_version,
        package.assessment_spec_version,
        package.provider,
        package.model,
        package.source_file,
        package.source_scope,
        metric.group,
        metric.kind,
        metric.metric,
        metric.assessment_state,
        metric.value,
        metric.range_low,
        metric.range_high,
        metric.confidence,
        metric.path_sensitive,
        metric.path_variation_affects_anchor,
        metric.rationale,
        metric.adjacent_lower_reason,
        metric.adjacent_higher_reason,
        JSON.generate(Array(metric.evidence).map { |e| { locator: e.locator, note: e.note } }),
        Array(metric.review_flags).join("|"),
        Array(package.package_review_flags).join("|")
      ]
    end
  end
end
