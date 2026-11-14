# frozen_string_literal: true
require_relative "test_helper"
require "stringio"

class CLITest < Minitest::Test
  def test_verbose_flag_is_parsed
    cli = AFScoring::CLI.new(["--verbose", "ADV-0230"], out: StringIO.new, err: StringIO.new)

    options = cli.send(:parse_options)

    assert_equal true, options[:verbose]
  end

  def test_experimental_group_flag_maps_to_config_override
    cli = AFScoring::CLI.new(
      ["--experimental-group", "play_mix", "ADV-0230"],
      out: StringIO.new, err: StringIO.new
    )
    options = cli.send(:parse_options)
    overrides = cli.send(:config_overrides, options)

    assert_equal "play_mix", overrides.dig("experimental", "group")
  end

  def test_dimension_flag_maps_to_scoring_scope_override
    cli = AFScoring::CLI.new(
      ["--dimension", "Combat Emphasis", "ADV-0230"],
      out: StringIO.new,
      err: StringIO.new
    )
    options = cli.send(:parse_options)
    overrides = cli.send(:config_overrides, options)

    assert_equal "Combat Emphasis", overrides.dig("scoring", "dimension")
  end

  def test_preflight_flags_are_parsed
    cli = AFScoring::CLI.new(
      ["--preflight", "--render-preflight", "/tmp/preflight.json", "--dimension", "Combat Emphasis", "ADV-0230"],
      out: StringIO.new,
      err: StringIO.new
    )

    options = cli.send(:parse_options)

    assert_equal true, options[:preflight]
    assert_equal "/tmp/preflight.json", options[:render_preflight]
    assert_equal "Combat Emphasis", options[:dimension]
  end

  def test_prepared_source_flags_are_parsed
    cli = AFScoring::CLI.new(
      ["--preflight", "--prepared-source", "/tmp/prepared.json", "ADV-0230"],
      out: StringIO.new,
      err: StringIO.new
    )

    options = cli.send(:parse_options)

    assert_equal true, options[:preflight]
    assert_equal "/tmp/prepared.json", options[:prepared_source]

    prepare_cli = AFScoring::CLI.new(
      ["--prepare-source", "/tmp/prepared.json", "ADV-0230"],
      out: StringIO.new,
      err: StringIO.new
    )
    prepare_options = prepare_cli.send(:parse_options)
    assert_equal "/tmp/prepared.json", prepare_options[:prepare_source]
  end

  def test_write_preflight_render_persists_exact_prompt_schema_and_metadata
    Dir.mktmpdir do |dir|
      prompt = AFScoring::PromptBuilder::Prompt.new(
        instructions: "system instructions",
        input: "focused input"
      )
      target = AFScoring::PreflightTarget.new(
        group_name: "play_mix",
        label: "Combat Emphasis",
        artifact_name: "play_mix",
        dimensions: ["Combat Emphasis"],
        prompt: prompt,
        schema: { "type" => "object" },
        prompt_sha256: "p" * 64,
        schema_sha256: "s" * 64
      )
      adventure = Struct.new(:id, :title).new("ADV-0001", "Fixture Adventure")
      outcome = AFScoring::PreflightOutcome.new(
        adventure: adventure,
        source_file: "/tmp/source.md",
        source_scope: "canonical_page_slice",
        source_warnings: [],
        output_root: "/tmp/output",
        targets: [target],
        run_metadata: { "prompt_profile" => "fixture-v1" }
      )
      path = File.join(dir, "nested", "preflight.json")
      cli = AFScoring::CLI.new([], out: StringIO.new, err: StringIO.new)

      written = cli.send(:write_preflight_render, outcome, path)
      payload = JSON.parse(File.read(written))

      assert_equal "ADV-0001", payload["adventure_id"]
      assert_equal "fixture-v1", payload.dig("run_metadata", "prompt_profile")
      assert_equal "system instructions", payload.dig("targets", 0, "prompt", "instructions")
      assert_equal "focused input", payload.dig("targets", 0, "prompt", "input")
      assert_equal({ "type" => "object" }, payload.dig("targets", 0, "schema"))
      assert_equal "p" * 64, payload.dig("targets", 0, "prompt_sha256")
      assert_equal "s" * 64, payload.dig("targets", 0, "schema_sha256")
    end
  end

  def test_print_outcome_surfaces_regression_disagreements
    out = StringIO.new
    cli = AFScoring::CLI.new([], out: out, err: StringIO.new)
    metrics = [
      Struct.new(:review_flags).new([]),
      Struct.new(:review_flags).new([])
    ]
    package = Struct.new(:status, :review_disposition, :metrics).new(
      "PROPOSED",
      "REVIEW_REQUIRED",
      metrics
    )
    comparison_class = Struct.new(
      :metric, :expected, :proposed, :exact_match, :numeric_delta,
      keyword_init: true
    )
    comparisons = [
      comparison_class.new(
        metric: "Combat Emphasis",
        expected: 5,
        proposed: 5,
        exact_match: true,
        numeric_delta: 0
      ),
      comparison_class.new(
        metric: "Tactical Complexity",
        expected: 5,
        proposed: 4,
        exact_match: false,
        numeric_delta: -1
      )
    ]
    outcome = AFScoring::RunOutcome.new(
      package: package,
      assessment_csv: "assessment.csv",
      regression_csv: "regression.csv",
      comparisons: comparisons,
      raw_paths: []
    )

    cli.send(:print_outcome, outcome)

    output = out.string
    assert_includes output, "Regression disagreements:"
    assert_includes output, "Tactical Complexity: expected 5, proposed 4 (delta -1)"
    refute_includes output, "Combat Emphasis: expected"
    assert_includes output, "Regression CSV: regression.csv"
  end
end
