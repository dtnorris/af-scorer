# frozen_string_literal: true

require_relative "test_helper"

class NosTwoStageIdentityRedactionTest < Minitest::Test
  AdventureFixture = Struct.new(
    :id, :title, :source_book, :publisher,
    keyword_init: true
  )

  def test_recursive_redaction_removes_catalog_identity_and_leading_article_alias
    adventure = adventure_fixture
    structure = {
      "major_play_bodies" => [
        {
          "label" => "The House of Lament investigation",
          "substantive_play" => "House of Lament appears in Van Richten's Guide to Ravenloft.",
          "evidence" => [
            {
              "locator" => "ADV-0287 p. 202",
              "note" => "Wizards of the Coast source text."
            }
          ]
        }
      ],
      "coverage_summary" => "Unrelated structural summary remains intact."
    }

    redacted = AFScoring::NosTwoStage.anonymize_structure(
      structure,
      adventure: adventure
    )
    serialized = JSON.generate(redacted)

    refute_includes serialized, "ADV-0287"
    refute_includes serialized, "The House of Lament"
    refute_includes serialized, "House of Lament"
    refute_includes serialized, "Van Richten's Guide to Ravenloft"
    refute_includes serialized, "Wizards of the Coast"
    assert_includes serialized, "[TARGET]"
    assert_includes serialized, "Unrelated structural summary remains intact."
    refute AFScoring::NosTwoStage.contains_target_identity?(redacted, adventure: adventure)

    assert_equal "The House of Lament investigation",
      structure.dig("major_play_bodies", 0, "label"),
      "redaction must not mutate the archived Stage 1 structure"
  end

  def test_stage2_prompt_applies_redaction_before_rendering_structure
    adventure = adventure_fixture
    builder = AFScoring::NosTwoStagePromptBuilder.new(afao: build_afao)
    structure = {
      "source_boundary_uncertainty" => false,
      "benchmark_contamination_detected" => false,
      "major_play_bodies" => [
        {
          "label" => "House of Lament investigation",
          "ordinary_presence" => "ordinary",
          "substantive_play" => "ADV-0287 has a source-grounded investigation body.",
          "evidence" => [
            { "locator" => "p. 202", "note" => "Van Richten's Guide to Ravenloft evidence." }
          ]
        }
      ],
      "repeated_play_cycles" => [],
      "optional_or_mutually_exclusive_material" => [],
      "explicit_bypass_or_compression_evidence" => [],
      "explicit_table_time_evidence" => [],
      "pacing_and_progression_constraints" => [],
      "coverage_summary" => "The House of Lament structure is summarized here.",
      "source_grounding_notes" => "Wizards of the Coast identity should not survive."
    }

    prompt = builder.stage2(adventure: adventure, structure: structure)

    refute_includes prompt.input, "ADV-0287"
    refute_includes prompt.input, "The House of Lament"
    refute_includes prompt.input, "House of Lament"
    refute_includes prompt.input, "Van Richten's Guide to Ravenloft"
    refute_includes prompt.input, "Wizards of the Coast"
    assert_includes prompt.input, "[TARGET]"
  end

  private

  def adventure_fixture
    AdventureFixture.new(
      id: "ADV-0287",
      title: "The House of Lament",
      source_book: "Van Richten's Guide to Ravenloft",
      publisher: "Wizards of the Coast"
    )
  end

  def build_afao
    dir = Dir.mktmpdir
    path = File.join(dir, "afao.md")
    File.write(
      path,
      TestSupport.minimal_afao(
        target_id: "ADV-0287",
        target_title: "House of Lament"
      )
    )
    AFScoring::AFAO.new(path)
  end
end
