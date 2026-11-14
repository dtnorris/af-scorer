# frozen_string_literal: true

require_relative "test_helper"

class GmbsBlindValidationScrubTest < Minitest::Test
  def test_gmbs_scorer_rubric_excludes_blind_validation_adjudication_history
    Dir.mktmpdir do |dir|
      path = File.join(dir, "afao.md")
      afao_text = TestSupport.minimal_afao(
        target_id: "ADV-0002",
        target_title: "Other Benchmark"
      )
      afao_text << <<~MD

        #### Blind Validation and Adjudication Record

        Historical validation says Blood Night scored 1 and House of Lament scored 5.
      MD
      File.write(path, afao_text)

      rubric = AFScoring::AFAO.new(path).rubric_for_dimension(
        "GM Beginner Suitability",
        target_id: "ADV-9999",
        target_title: "Blind Future Adventure"
      )

      assert_includes rubric, "fixture definition for GM Beginner Suitability"
      refute_includes rubric, "#### Blind Validation and Adjudication Record"
      refute_includes rubric, "Historical validation says Blood Night scored 1"
      refute_includes rubric, "Blood Night"
      refute_includes rubric, "House of Lament"
    end
  end
end
