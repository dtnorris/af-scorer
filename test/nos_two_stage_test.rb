# frozen_string_literal: true

require_relative "test_helper"
require "json"

class NosTwoStageTest < Minitest::Test
  AdventureFixture = Struct.new(:id, :title, keyword_init: true)
  ExtractionFixture = Struct.new(:text, keyword_init: true)

  def test_stage1_schema_cannot_return_a_final_duration_assessment
    serialized = JSON.generate(AFScoring::NosTwoStage.stage1_schema)

    refute_includes serialized, "normalized_sessions"
    refute_includes serialized, "practical_range_low"
    refute_includes serialized, "practical_range_high"
    refute_includes serialized, "confidence"
    refute_includes serialized, "path_sensitive"

    required = AFScoring::NosTwoStage.stage1_schema.fetch("required")
    assert_includes required, "major_play_bodies"
    assert_includes required, "repeated_play_cycles"
    assert_includes required, "explicit_bypass_or_compression_evidence"
    assert_includes required, "explicit_table_time_evidence"
  end

  def test_stage1_prompt_contains_source_but_no_catalog_identity
    builder = build_prompt_builder
    extraction = ExtractionFixture.new(
      text: "<!-- PAGE: 202 -->\nA parlor investigation leads to repeated source-grounded events."
    )

    prompt = builder.stage1(source_extraction: extraction)

    assert_includes prompt.input, "<!-- PAGE: 202 -->"
    assert_includes prompt.input, "parlor investigation"
    refute_includes prompt.input, "ADV-0287"
    refute_includes prompt.input, "The House of Lament"
    assert_includes prompt.instructions, "Do not estimate a number of sessions"
  end

  def test_stage2_prompt_withholds_identity_raw_source_and_target_benchmark
    builder = build_prompt_builder
    adventure = AdventureFixture.new(
      id: "ADV-0287",
      title: "The House of Lament"
    )
    structure = {
      "source_boundary_uncertainty" => false,
      "benchmark_contamination_detected" => false,
      "major_play_bodies" => [
        {
          "label" => "investigation body",
          "ordinary_presence" => "ordinary",
          "substantive_play" => "Explore and interact with the location.",
          "evidence" => [{ "locator" => "p. 202", "note" => "Source-grounded exploration." }]
        }
      ],
      "repeated_play_cycles" => [],
      "optional_or_mutually_exclusive_material" => [],
      "explicit_bypass_or_compression_evidence" => [],
      "explicit_table_time_evidence" => [],
      "pacing_and_progression_constraints" => [],
      "coverage_summary" => "One ordinary macro body plus later source-supported progression.",
      "source_grounding_notes" => "No external duration priors used."
    }

    prompt = builder.stage2(adventure: adventure, structure: structure)
    normalized = prompt.input.downcase.gsub(/\s+/, " ")

    refute_includes prompt.input, "ADV-0287"
    refute_includes prompt.input, "The House of Lament"
    refute_match(/house of lament\s+3\b/, normalized)
    refute_includes prompt.input, "RAW-SOURCE-SECRET"
    assert_includes prompt.input, "investigation body"
    assert_includes prompt.input, "Source-Grounded Duration Structure"
    assert_includes prompt.instructions, "The adventure identity is intentionally withheld"
  end

  def test_stage2_schema_is_the_standard_focused_sessions_schema
    schema = AFScoring::NosTwoStage.stage2_schema

    assert_equal ["sessions_levels"], schema.dig("properties", "group", "enum")
    assert schema.fetch("properties").key?("sessions")
    refute schema.fetch("properties").key?("level_start")
    refute schema.fetch("properties").key?("level_end")
  end

  def test_unknown_profile_is_rejected
    previous = ENV[AFScoring::NosTwoStage::PROFILE_ENV]
    ENV[AFScoring::NosTwoStage::PROFILE_ENV] = "unknown"

    error = assert_raises(AFScoring::ConfigurationError) do
      AFScoring::NosTwoStage.validate_profile!
    end
    assert_includes error.message, AFScoring::NosTwoStage::PROFILE
  ensure
    if previous.nil?
      ENV.delete(AFScoring::NosTwoStage::PROFILE_ENV)
    else
      ENV[AFScoring::NosTwoStage::PROFILE_ENV] = previous
    end
  end

  private

  def build_prompt_builder
    path = File.join(Dir.mktmpdir, "afao.md")
    afao_text = TestSupport.minimal_afao(
      target_id: "ADV-0287",
      target_title: "House of Lament"
    ).sub(
      "**Definition:** duration.\n",
      <<~MD
        **Definition:** duration.

        #### Blind Validation and Disagreement Adjudication

        Lake Monster 1 -> Salvage Operation 2 -> House of Lament 3 was reproduced independently.
      MD
    )
    File.write(path, afao_text)

    AFScoring::NosTwoStagePromptBuilder.new(
      afao: AFScoring::AFAO.new(path)
    )
  end
end
