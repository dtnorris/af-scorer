# frozen_string_literal: true
require_relative "test_helper"

class AfaoTest < Minitest::Test
  def test_extracts_calibration_expectations_and_scrubs_target
    Dir.mktmpdir do |dir|
      path = File.join(dir, "afao.md")
      File.write(path, TestSupport.minimal_afao)
      afao = AFScoring::AFAO.new(path)
      expected = afao.calibration_expectations.fetch("ADV-0001")
      assert_equal 2, expected["# of Sessions"]
      assert_equal 1, expected["Level Start"]
      assert_equal 2, expected["Level End"]
      assert_equal 3, expected["Combat Emphasis"]
      rubric = afao.rubric_for_group("play_mix", target_id: "ADV-0001", target_title: "Fixture Adventure")
      refute_includes rubric, "ADV-0001"
      refute_includes rubric, "Fixture Adventure"
      assert_includes rubric, "Combat Emphasis"

      focused = afao.rubric_for_dimension("Combat Emphasis", target_id: "ADV-0001", target_title: "Fixture Adventure")
      assert_includes focused, "Combat Emphasis"
      refute_includes focused, "Exploration Emphasis"
      refute_includes focused, "ADV-0001"
    end
  end

  def test_omits_entire_calibration_benchmarks_subsection_for_benchmark_target
    Dir.mktmpdir do |dir|
      path = File.join(dir, "afao.md")
      afao_text = TestSupport.minimal_afao.gsub(
        "| **3 — Mixed** | **ADV-0001 — Fixture Adventure** |",
        "| **3 — Mixed** | **ADV-0001 — Fixture Adventure**; **ADV-0002 — Other Benchmark**; **ADV-0003 — Third Benchmark** |"
      )
      File.write(path, afao_text)

      rubric = TestSupport.historical_afao(path).first.rubric_for_dimension(
        "Combat Emphasis",
        target_id: "ADV-0001",
        target_title: "Fixture Adventure"
      )

      refute_includes rubric, "ADV-0001"
      refute_includes rubric, "ADV-0002"
      refute_includes rubric, "ADV-0003"
      refute_includes rubric, "#### Calibration Benchmarks"
      assert_includes rubric, "| **1 — Minimal** | minimal |"
      assert_includes rubric, "| **5 — Dominant** | dominant |"
    end
  end

  def test_preserves_calibration_benchmarks_for_non_benchmark_target
    Dir.mktmpdir do |dir|
      path = File.join(dir, "afao.md")
      File.write(path, TestSupport.minimal_afao(target_id: "ADV-0002", target_title: "Other Benchmark"))

      rubric = TestSupport.historical_afao(path, target_id: "ADV-9999", target_title: "Non-Benchmark Adventure").first.rubric_for_dimension(
        "Combat Emphasis",
        target_id: "ADV-9999",
        target_title: "Non-Benchmark Adventure"
      )

      assert_includes rubric, "#### Calibration Benchmarks"
      assert_includes rubric, "**ADV-0002 — Other Benchmark**"
      assert_includes rubric, "| **3 — Mixed** | **ADV-0002 — Other Benchmark** |"
    end
  end

  def test_still_scrubs_only_target_entry_from_other_multi_adventure_table
    Dir.mktmpdir do |dir|
      path = File.join(dir, "afao.md")
      afao_text = TestSupport.minimal_afao.sub(
        "**Definition:** fixture definition for Combat Emphasis.\n",
        <<~MD
          **Definition:** fixture definition for Combat Emphasis.

          | Reference Set | Adventures |
          | --- | --- |
          | Comparison | **ADV-0001 — Fixture Adventure**; **ADV-0002 — Other Benchmark**; **ADV-0003 — Third Benchmark** |
        MD
      )
      File.write(path, afao_text)

      rubric = TestSupport.historical_afao(path).first.rubric_for_dimension(
        "Combat Emphasis",
        target_id: "ADV-0001",
        target_title: "Fixture Adventure"
      )

      refute_includes rubric, "ADV-0001"
      assert_includes rubric, "**ADV-0002 — Other Benchmark**"
      assert_includes rubric, "**ADV-0003 — Third Benchmark**"
    end
  end

  def test_scrubs_entire_target_specific_subsection_when_follow_on_paragraphs_do_not_repeat_target
    Dir.mktmpdir do |dir|
      path = File.join(dir, "afao.md")
      afao_text = TestSupport.minimal_afao.sub(
        "**Definition:** fixture definition for Combat Emphasis.\n",
        <<~MD
          **Definition:** fixture definition for Combat Emphasis.

          #### ADV-0001 — Fixture Adventure Blind Validation

          This paragraph explicitly belongs to the target-specific subsection.

          This follow-on paragraph omits the target identifier and title but still leaks the target-specific conclusion.

          ##### Reviewer Notes

          This nested follow-on paragraph also omits the target identifier and title.

          #### General Boundary Guidance

          This guidance applies to every future adventure.
        MD
      )
      File.write(path, afao_text)

      rubric = AFScoring::AFAO.new(path).rubric_for_dimension(
        "Combat Emphasis",
        target_id: "ADV-0001",
        target_title: "Fixture Adventure"
      )

      refute_includes rubric, "Blind Validation"
      refute_includes rubric, "This paragraph explicitly belongs to the target-specific subsection."
      refute_includes rubric, "This follow-on paragraph omits the target identifier and title"
      refute_includes rubric, "Reviewer Notes"
      refute_includes rubric, "This nested follow-on paragraph also omits the target identifier and title."
      assert_includes rubric, "General Boundary Guidance"
      assert_includes rubric, "This guidance applies to every future adventure."
    end
  end
  def test_scrubs_target_title_when_markdown_soft_wrap_splits_title
    Dir.mktmpdir do |dir|
      path = File.join(dir, "afao.md")
      afao_text = TestSupport.minimal_afao(target_id: "ADV-0002", target_title: "Other Benchmark").sub(
        "**Definition:** fixture definition for Fantastic Weirdness.\n",
        <<~MD
          **Definition:** fixture definition for Fantastic Weirdness.

          #### Application Guardrails

          A target-specific example can wrap naturally in Markdown prose.
          Sustained unfamiliar systems can reach 5 when they constitute the
          adventure's site and interaction logic, as in Expedition to the Barrier
          Peaks.

          This general guidance contains no target reference and must remain.
        MD
      )
      File.write(path, afao_text)

      rubric = AFScoring::AFAO.new(path).rubric_for_dimension(
        "Fantastic Weirdness",
        target_id: "ADV-0040",
        target_title: "Expedition to the Barrier Peaks"
      )

      normalized = rubric.downcase.gsub(/\s+/, " ")
      refute_includes normalized, "expedition to the barrier peaks"
      refute_includes rubric, "Sustained unfamiliar systems can reach 5"
      assert_includes rubric, "This general guidance contains no target reference and must remain."
    end
  end

  def test_scrubs_wrapped_target_title_inside_list_block
    Dir.mktmpdir do |dir|
      path = File.join(dir, "afao.md")
      afao_text = TestSupport.minimal_afao(target_id: "ADV-0002", target_title: "Other Benchmark").sub(
        "**Definition:** duration.\n",
        <<~MD
          **Definition:** duration.

          #### Blind Validation and Disagreement Adjudication

          - publisher "one-shot" labels for **No Honour Among Thieves** and **Call of the
            Wild** were treated as evidence rather than automatically scored as one
            normalized session;
          - mutually exclusive content was probability-weighted.

          General duration guidance remains available after target scrubbing.
        MD
      )
      File.write(path, afao_text)

      rubric = AFScoring::AFAO.new(path).rubric_for_dimension(
        "# of Sessions",
        target_id: "ADV-0053",
        target_title: "Call of the Wild"
      )

      normalized = rubric.downcase.gsub(/\s+/, " ")
      refute_includes normalized, "call of the wild"
      refute_includes rubric, "publisher \"one-shot\" labels"
      assert_includes rubric, "General duration guidance remains available after target scrubbing."
    end
  end

  def test_last_dimension_stops_before_following_second_level_sections
    Dir.mktmpdir do |dir|
      path = File.join(dir, "afao.md")
      afao_text = TestSupport.minimal_afao + <<~MD

        ## Working Status

        This status material is not part of GM Beginner Suitability.

        ## Revision History

        House of Lament moved 4→5 during calibration.
      MD
      File.write(path, afao_text)

      rubric = AFScoring::AFAO.new(path).rubric_for_dimension(
        "GM Beginner Suitability",
        target_id: "ADV-0287",
        target_title: "The House of Lament"
      )

      refute_includes rubric, "Working Status"
      refute_includes rubric, "Revision History"
      refute_includes rubric, "House of Lament moved 4→5"
      assert_includes rubric, "fixture definition for GM Beginner Suitability"
    end
  end

  def test_sessions_scorer_rubric_excludes_calibration_history_for_non_benchmark_target
    Dir.mktmpdir do |dir|
      path = File.join(dir, "afao.md")
      afao_text = TestSupport.minimal_afao(
        target_id: "ADV-0002",
        target_title: "Other Benchmark"
      ).sub(
        "| **2** | **ADV-0002 — Other Benchmark** | Very Short |\n",
        <<~MD
          | **2** | **ADV-0002 — Other Benchmark** | Very Short |

          #### Calibration and Blind Validation Record

          Historical calibration produced exact target values.

          #### Blind-Validation Agreement Interpretation

          Historical validation compared exact and practical agreement.

          #### General Duration Guidance

          This normative duration guidance must remain available to the scorer.
        MD
      )
      File.write(path, afao_text)

      rubric = AFScoring::AFAO.new(path).rubric_for_dimension(
        "# of Sessions",
        target_id: "ADV-9999",
        target_title: "Blind Future Adventure"
      )

      refute_includes rubric, "#### Calibration Benchmarks"
      refute_includes rubric, "ADV-0002"
      refute_includes rubric, "Calibration and Blind Validation Record"
      refute_includes rubric, "Historical calibration produced exact target values."
      refute_includes rubric, "Blind-Validation Agreement Interpretation"
      refute_includes rubric, "Historical validation compared exact and practical agreement."
      assert_includes rubric, "General Duration Guidance"
      assert_includes rubric, "This normative duration guidance must remain available to the scorer."
    end
  end

  def test_gmpb_scorer_rubric_excludes_score_5_benchmark_expansion_for_non_benchmark_target
    Dir.mktmpdir do |dir|
      path = File.join(dir, "afao.md")
      afao_text = TestSupport.minimal_afao(
        target_id: "ADV-0002",
        target_title: "Other Benchmark"
      ).sub(
        "**Definition:** fixture definition for GM Preparation Burden.\n",
        <<~MD
          **Definition:** fixture definition for GM Preparation Burden.

          #### AFAO 1.6 Score-5 Benchmark Expansion and Blind Replication

          **ADV-0032 — Dead in Thay = 5 — Very High**
          **ADV-0303 — Storm King's Thunder = 5 — Very High**

          Historical blind replication and calibration adjudication.

          #### General GM Preparation Guidance

          This normative preparation guidance must remain available to the scorer.
        MD
      )
      File.write(path, afao_text)

      rubric = AFScoring::AFAO.new(path).rubric_for_dimension(
        "GM Preparation Burden",
        target_id: "ADV-9999",
        target_title: "Blind Future Adventure"
      )

      refute_includes rubric, "AFAO 1.6 Score-5 Benchmark Expansion and Blind Replication"
      refute_includes rubric, "ADV-0032"
      refute_includes rubric, "ADV-0303"
      refute_includes rubric, "Historical blind replication and calibration adjudication."
      assert_includes rubric, "General GM Preparation Guidance"
      assert_includes rubric, "This normative preparation guidance must remain available to the scorer."
    end
  end

  def test_gmpb_scorer_rubric_excludes_calibration_benchmarks_for_non_benchmark_target
    Dir.mktmpdir do |dir|
      path = File.join(dir, "afao.md")
      File.write(
        path,
        TestSupport.minimal_afao(
          target_id: "ADV-0002",
          target_title: "Other Benchmark"
        )
      )

      afao = AFScoring::AFAO.new(path)

      assert_equal 3,
        afao.calibration_expectations.fetch("ADV-0002").fetch("GM Preparation Burden")

      rubric = afao.rubric_for_dimension(
        "GM Preparation Burden",
        target_id: "ADV-9999",
        target_title: "Blind Future Adventure"
      )

      refute_includes rubric, "#### Calibration Benchmarks"
      refute_includes rubric, "ADV-0002"
      refute_includes rubric, "Other Benchmark"
      assert_includes rubric, "| **1 — Minimal** | minimal |"
      assert_includes rubric, "| **5 — Dominant** | dominant |"
    end
  end

end
