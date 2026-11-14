# frozen_string_literal: true

require_relative "test_helper"

class NosPromptTest < Minitest::Test
  FakeAFAO = Struct.new(:version) do
    def rubric_for_group(group_name, target_id:, target_title:)
      "fixture rubric for #{group_name} / #{target_id} / #{target_title}"
    end

    def rubric_for_dimensions(dimensions, target_id:, target_title:)
      "fixture rubric for #{dimensions.join(', ')} / #{target_id} / #{target_title}"
    end
  end

  FakeAssessmentSpec = Struct.new(:prompt_text)
  AdventureFixture = Struct.new(
    :id, :title, :source_book, :publisher, :start_page, :end_page,
    keyword_init: true
  )
  ExtractionFixture = Struct.new(:text, :scope, :source_file, keyword_init: true)

  def setup
    @builder = AFScoring::PromptBuilder.new(
      afao: FakeAFAO.new("1.6"),
      assessment_spec: FakeAssessmentSpec.new("fixture production assessment rules")
    )
    @adventure = AdventureFixture.new(
      id: "ADV-9999",
      title: "Blind Fixture",
      source_book: "Fixture Book",
      publisher: "Fixture Publisher",
      start_page: 10,
      end_page: 20
    )
    @extraction = ExtractionFixture.new(
      text: "<!-- PAGE: 10 -->\nfixture canonical source",
      scope: "canonical_page_slice",
      source_file: "/tmp/blind-fixture.md"
    )
  end

  def test_nos_uses_dedicated_system_profile
    prompt = build_nos_prompt

    assert_equal AFScoring::PromptBuilder::NOS_SYSTEM_INSTRUCTIONS,
      prompt.instructions
    refute_equal AFScoring::PromptBuilder::SYSTEM_INSTRUCTIONS, prompt.instructions
    assert_includes prompt.instructions,
      "independent blind AdventureFinder # of Sessions assessment"
    assert_includes prompt.instructions,
      "Do not search for, infer, or use any prior AdventureFinder score"
  end

  def test_nos_excludes_general_production_prompt_stack_and_historical_guardrails
    prompt = build_nos_prompt

    refute_includes prompt.input, "# AdventureFinder Production Assessment Rules"
    refute_includes prompt.input, "fixture production assessment rules"
    refute_includes prompt.input, "# Number of Sessions Compact-Phase Aggregation Guardrail"
    refute_includes prompt.input, "# Anti-Compression Counter-Guardrail"
  end

  def test_nos_contains_source_frozen_rubric_and_blind_task_scaffolding
    prompt = build_nos_prompt

    assert_includes prompt.input, "# Published Source Material"
    assert_includes prompt.input, "<!-- PAGE: 10 -->"
    assert_includes prompt.input, "fixture canonical source"
    assert_includes prompt.input, "# Frozen AFAO 1.6 # of Sessions Rubric"
    assert_includes prompt.input,
      "fixture rubric for # of Sessions / ADV-9999 / Blind Fixture"
    assert_includes prompt.input, "# Blind Assessment Task"
    assert_includes prompt.input,
      "Return the best-supported # of Sessions assessment required by the response schema."
  end

  def test_levels_remains_on_existing_production_prompt
    prompt = @builder.build(
      group_name: "sessions_levels",
      dimensions: ["Levels"],
      adventure: @adventure,
      source_extraction: @extraction
    )

    assert_equal AFScoring::PromptBuilder::SYSTEM_INSTRUCTIONS, prompt.instructions
    assert_includes prompt.input, "# AdventureFinder Production Assessment Rules"
    assert_includes prompt.input, "fixture production assessment rules"
    refute_includes prompt.input, "# Blind Assessment Task"
  end

  private

  def build_nos_prompt
    @builder.build(
      group_name: "sessions_levels",
      dimensions: ["# of Sessions"],
      adventure: @adventure,
      source_extraction: @extraction
    )
  end
end
