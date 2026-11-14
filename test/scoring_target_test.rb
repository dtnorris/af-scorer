# frozen_string_literal: true
require_relative "test_helper"

class ScoringTargetTest < Minitest::Test
  def test_interpretive_dimension_resolves_to_existing_group
    target = AFScoring::ScoringTarget.for_dimension("Combat Emphasis")

    assert_equal "play_mix", target.group_name
    assert_equal ["Combat Emphasis"], target.dimensions
    assert_equal ["Combat Emphasis"], target.metric_names
    assert_equal "Combat Emphasis", target.label
    assert_equal "dimension_combat_emphasis", target.artifact_name
    refute target.full_group?
  end

  def test_sessions_and_levels_preserve_their_special_metric_shapes
    sessions = AFScoring::ScoringTarget.for_dimension("# of Sessions")
    levels = AFScoring::ScoringTarget.for_dimension("Levels")

    assert_equal ["# of Sessions"], sessions.metric_names
    assert_equal ["Level Start", "Level End"], levels.metric_names
  end

  def test_group_target_preserves_existing_behavior
    target = AFScoring::ScoringTarget.for_group("play_mix")

    assert target.full_group?
    assert_equal AFScoring::DimensionGroups.fetch("play_mix"), target.dimensions
    assert_equal "play_mix", target.artifact_name
  end

  def test_unknown_dimension_is_rejected
    error = assert_raises(AFScoring::SpecificationError) do
      AFScoring::ScoringTarget.for_dimension("Not A Dimension")
    end

    assert_includes error.message, "Unknown scoring dimension"
  end
end
