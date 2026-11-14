# frozen_string_literal: true
require_relative "test_helper"
require "stringio"

class ProgressTest < Minitest::Test
  def test_tty_spinner_rotates_request_dimension_labels_and_completes
    out = StringIO.new
    progress = AFScoring::Progress.new(io: out, tty: true, tick_interval: 0.002, label_interval: 0.006)
    session = progress.start(
      adventure_id: "ADV-0230",
      group_name: "challenge_character",
      dimensions: ["Tactical Complexity", "Lethality / Failure Severity", "Rules / System-Mastery Demand"],
      source_file: "/tmp/Ghosts_of_Saltmarsh_LLM_Edition.md",
      start_page: 87,
      end_page: 95,
      provider: "openai",
      model: "fixture-model"
    )

    session.waiting { sleep 0.025 }
    session.complete(3)

    output = out.string
    assert_includes output, "⠋"
    assert_includes output, "Tactical Complexity"
    assert_includes output, "Lethality / Failure Severity"
    assert_includes output, "Rules / System-Mastery Demand"
    assert_includes output, "challenge_character ✓"
    assert_includes output, "3 dimensions scored"
  end

  def test_non_tty_falls_back_to_line_based_output
    out = StringIO.new
    progress = AFScoring::Progress.new(io: out, tty: false)
    session = progress.start(
      adventure_id: "ADV-0230",
      group_name: "play_mix",
      dimensions: ["Combat Emphasis", "Exploration Emphasis"],
      source_file: "/tmp/source.md",
      start_page: 87,
      end_page: 95,
      provider: "openai",
      model: "fixture-model"
    )

    session.waiting { :ok }
    session.complete(2)

    output = out.string
    refute_includes output, "\e[2K"
    assert_includes output, "request dimensions: Combat Emphasis / Exploration Emphasis"
    assert_includes output, "2 dimensions scored"
  end

  def test_verbose_output_reports_operational_lifecycle
    out = StringIO.new
    progress = AFScoring::Progress.new(io: out, tty: false, verbose: true)
    session = progress.start(
      adventure_id: "ADV-0230",
      group_name: "play_mix",
      dimensions: ["Combat Emphasis", "Exploration Emphasis"],
      source_file: "/tmp/Ghosts_of_Saltmarsh_LLM_Edition.md",
      start_page: 87,
      end_page: 95,
      provider: "openai",
      model: "fixture-model"
    )

    session.waiting { :ok }
    session.normalizing
    session.complete(2)
    progress.validating(adventure_id: "ADV-0230", metric_count: 20)

    output = out.string
    assert_includes output, "source: Ghosts_of_Saltmarsh_LLM_Edition.md, pages 87–95"
    assert_includes output, "dimensions: Combat Emphasis, Exploration Emphasis"
    assert_includes output, "provider: openai"
    assert_includes output, "model: fixture-model"
    assert_includes output, "sending openai request"
    assert_includes output, "response received"
    assert_includes output, "normalizing structured response"
    assert_includes output, "validating 20 assessments"
  end
end
