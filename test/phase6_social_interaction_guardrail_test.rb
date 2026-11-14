# frozen_string_literal: true

require_relative "test_helper"

class Phase6SocialInteractionGuardrailTest < Minitest::Test
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
    @previous_profile = ENV[AFScoring::Phase6SocialInteractionGuardrail::PROFILE_ENV]
    ENV.delete(AFScoring::Phase6SocialInteractionGuardrail::PROFILE_ENV)
    @afao = FakeAFAO.new("1.5")
    @assessment_spec = FakeAssessmentSpec.new("fixture assessment rules")
    @adventure = AdventureFixture.new(
      id: "ADV-0001",
      title: "Fixture Adventure",
      source_book: "Fixture Book",
      publisher: "Fixture Publisher",
      start_page: 1,
      end_page: 2
    )
    @extraction = ExtractionFixture.new(
      text: "<!-- PAGE: 1 -->\nfixture source",
      scope: "canonical_page_slice",
      source_file: "/tmp/fixture.md"
    )
  end

  def teardown
    env_name = AFScoring::Phase6SocialInteractionGuardrail::PROFILE_ENV
    if @previous_profile.nil?
      ENV.delete(env_name)
    else
      ENV[env_name] = @previous_profile
    end
  end

  def test_default_social_prompt_remains_on_frozen_v0_2
    prompt = social_prompt

    assert_includes prompt.input, AFScoring::PromptBuilder::SOCIAL_INTERACTION_EMPHASIS_GUARDRAIL_V0_2
    refute_includes prompt.input, AFScoring::Phase6SocialInteractionGuardrail::TEXT
    refute_includes prompt.input, "# Social Interaction Emphasis Cross-Mode Independence Guardrail v0.3"
  end

  def test_phase6_profile_appends_v0_3_after_frozen_v0_2
    with_profile("phase6-v0.3") do
      prompt = social_prompt

      assert_includes prompt.input, AFScoring::PromptBuilder::SOCIAL_INTERACTION_EMPHASIS_GUARDRAIL_V0_2
      assert_includes prompt.input, AFScoring::Phase6SocialInteractionGuardrail::TEXT
      assert_equal 1,
        prompt.input.scan("# Social Interaction Emphasis Cross-Mode Independence Guardrail v0.3").length
      assert_includes prompt.input, "A single scene may legitimately supply evidence for more than"
      assert_includes prompt.input, 'do not use "this is really Investigation"'
    end
  end

  def test_phase6_profile_is_not_injected_into_other_dimensions
    with_profile("phase6-v0.3") do
      prompt = builder.build(
        group_name: "play_mix",
        dimensions: ["Combat Emphasis"],
        adventure: @adventure,
        source_extraction: @extraction
      )

      refute_includes prompt.input, AFScoring::Phase6SocialInteractionGuardrail::TEXT
    end
  end

  def test_unknown_social_profile_fails_closed
    with_profile("unknown-profile") do
      error = assert_raises(AFScoring::ConfigurationError) { social_prompt }
      assert_includes error.message, "Unsupported Social Interaction guardrail profile"
    end
  end

  private

  def social_prompt
    builder.build(
      group_name: "play_mix",
      dimensions: ["Social Interaction Emphasis"],
      adventure: @adventure,
      source_extraction: @extraction
    )
  end

  def builder
    AFScoring::PromptBuilder.new(afao: @afao, assessment_spec: @assessment_spec)
  end

  def with_profile(value)
    env_name = AFScoring::Phase6SocialInteractionGuardrail::PROFILE_ENV
    previous = ENV[env_name]
    ENV[env_name] = value
    yield
  ensure
    if previous.nil?
      ENV.delete(env_name)
    else
      ENV[env_name] = previous
    end
  end
end
