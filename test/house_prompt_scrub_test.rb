# frozen_string_literal: true
require_relative "test_helper"

class HousePromptScrubTest < Minitest::Test
  AdventureFixture = Struct.new(
    :id, :title, :source_book, :publisher, :start_page, :end_page,
    keyword_init: true
  )
  ExtractionFixture = Struct.new(:text, :scope, :source_file, keyword_init: true)
  FakeAssessmentSpec = Struct.new(:prompt_text)

  def test_rendered_house_sessions_prompt_scrubs_benchmark_when_leading_article_is_omitted
    Dir.mktmpdir do |dir|
      path = File.join(dir, "afao.md")
      afao_text = TestSupport.minimal_afao(
        target_id: "ADV-9999",
        target_title: "Other Benchmark"
      ).sub(
        "**Definition:** duration.\n",
        <<~MD
          **Definition:** duration.

          #### Blind Validation and Disagreement Adjudication

          The blind pass therefore pressure-tested the practically important
          1 versus 2 distinction: Lake Monster 1 -> Salvage Operation 2 ->
          House of Lament 3 was reproduced independently.

          General duration guidance remains available after target scrubbing.
        MD
      )
      File.write(path, afao_text)

      afao = AFScoring::AFAO.new(path)
      builder = AFScoring::PromptBuilder.new(
        afao: afao,
        assessment_spec: FakeAssessmentSpec.new("fixture assessment rules")
      )

      adventure = AdventureFixture.new(
        id: "ADV-0287",
        title: "The House of Lament",
        source_book: "Fixture Book",
        publisher: "Fixture Publisher",
        start_page: 202,
        end_page: 221
      )

      extraction = ExtractionFixture.new(
        text: "<!-- PAGE: 202 -->\nfixture source",
        scope: "canonical_page_slice",
        source_file: "/tmp/fixture.md"
      )

      prompt = builder.build(
        group_name: "sessions_levels",
        dimensions: ["# of Sessions"],
        adventure: adventure,
        source_extraction: extraction
      )

      normalized = prompt.input.downcase.gsub(/\s+/, " ")

      refute_match(/house of lament\s+3\b/, normalized)
      assert_includes prompt.input, "Adventure ID: ADV-0287"
      assert_includes prompt.input, "Adventure Title: The House of Lament"
      assert_includes prompt.input,
        "General duration guidance remains available after target scrubbing."
    end
  end
end
