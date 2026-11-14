# frozen_string_literal: true

require_relative "test_helper"

class NosTwoStageSourceBoundaryTest < Minitest::Test
  AdventureFixture = Struct.new(:title, keyword_init: true)

  def test_trims_leading_sibling_content_to_exact_adventure_heading
    extraction = AFScoring::SourceDocument::Extraction.new(
      text: <<~MD,
        <!-- PAGE: 28 -->

        #### Five-Tavern Center

        unrelated prelude

        ### Lake Monster

        quest opening

        #### Getting the Quest

        substantive quest material

        <!-- PAGE: 29 -->

        continued quest material

        ### Next Quest

        unrelated following material
      MD
      source_file: "/tmp/fixture.md",
      scope: "canonical_page_slice",
      start_page: 28,
      end_page: 29,
      warnings: []
    )

    result = AFScoring::NosTwoStage.canonical_heading_extraction(
      extraction,
      adventure: AdventureFixture.new(title: "Lake Monster")
    )

    assert_equal "canonical_heading_slice", result.scope
    assert_includes result.text, "<!-- PAGE: 28 -->"
    assert_includes result.text, "### Lake Monster"
    assert_includes result.text, "#### Getting the Quest"
    assert_includes result.text, "<!-- PAGE: 29 -->"
    assert_includes result.text, "continued quest material"
    refute_includes result.text, "Five-Tavern Center"
    refute_includes result.text, "unrelated prelude"
    refute_includes result.text, "Next Quest"
    assert_includes result.warnings, "NOS_TWO_STAGE_HEADING_BOUNDARY_TRIMMED"
  end

  def test_keeps_verified_canonical_page_slice_when_title_heading_is_absent
    extraction = AFScoring::SourceDocument::Extraction.new(
      text: "<!-- PAGE: 15 -->\n## Chapter 1: A Dangerous Journey\nbody\n",
      source_file: "/tmp/fixture.md",
      scope: "canonical_page_slice",
      start_page: 15,
      end_page: 79,
      warnings: []
    )

    result = AFScoring::NosTwoStage.canonical_heading_extraction(
      extraction,
      adventure: AdventureFixture.new(title: "Lost Mine of Phandelver")
    )

    assert_equal "canonical_page_slice", result.scope
    assert_equal extraction.text, result.text
    assert_equal 15, result.start_page
    assert_equal 79, result.end_page
    assert_includes result.warnings,
                    "NOS_TWO_STAGE_HEADING_BOUNDARY_NOT_FOUND_USING_CANONICAL_PAGE_SLICE"
  end

  def test_rejects_unverified_source_scope
    extraction = AFScoring::SourceDocument::Extraction.new(
      text: "### Lake Monster\nbody\n",
      source_file: "/tmp/fixture.md",
      scope: "full_source_fallback",
      start_page: nil,
      end_page: nil,
      warnings: ["SOURCE_BOUNDARY_UNVERIFIED"]
    )

    assert_raises(AFScoring::SourceBoundaryError) do
      AFScoring::NosTwoStage.canonical_heading_extraction(
        extraction,
        adventure: AdventureFixture.new(title: "Lake Monster")
      )
    end
  end
end
