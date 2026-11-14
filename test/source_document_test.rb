# frozen_string_literal: true

require_relative "test_helper"
require "digest"

class SourceDocumentTest < Minitest::Test
  # Assert the independently specified D02 UTF-8 literal survives final-range extraction.
  # Uses a disposable source; assertion failures identify byte or metadata regressions.
  def test_preserves_exact_utf8_bytes_through_the_final_page
    source = "<!-- Printed Page 1 -->\nα\n<!-- Printed Page 2 -->\nΩ\n"
    Dir.mktmpdir("source-document") do |dir|
      path = File.join(dir, "source.md")
      File.binwrite(path, source)

      extraction = AFScoring::SourceDocument.new(path).extract(start_page: 1, end_page: 2)

      assert_equal 54, extraction.text.bytesize
      assert_equal "b71d7a597ee169616c05015d7836d7252fc87d6ca1bb24df92009bc8c0bc979f",
                   Digest::SHA256.hexdigest(extraction.text)
      assert_equal source, extraction.text
      assert_equal Encoding::UTF_8, extraction.text.encoding
      assert_predicate extraction.text, :valid_encoding?
      assert_equal "canonical_page_slice", extraction.scope
      assert_equal [1, 2], [extraction.start_page, extraction.end_page]
      assert_empty extraction.warnings
    end
  end

  # Assert literal final-page/range bytes across marker conventions and signed offsets.
  # Inputs include UTF-8 before/inside the slice and exact whitespace endings; failures raise assertions.
  def test_preserves_final_slices_with_utf8_prefixes_offsets_and_whitespace
    conventions = [
      ["<!-- Printed Page 10 -->", "<!-- Printed Page 11 -->", 0],
      ["> > <!-- PDF Page 13 -->", "> > <!-- PDF Page 14 -->", +3],
      ["> <!-- PAGE: 7 -->", "> <!-- PAGE: 8 -->", -3]
    ]
    Dir.mktmpdir("source-document") do |dir|
      path = File.join(dir, "source.md")
      conventions.each do |first_marker, final_marker, offset|
        ["", "\n", " \t\n\n"].each do |ending|
          first_page = "#{first_marker}\nβ\n"
          final_page = "#{final_marker}\nΩ#{ending}"
          File.binwrite(path, "α\n#{first_page}#{final_page}")
          document = AFScoring::SourceDocument.new(path)
          [[11, final_page], [10, first_page + final_page]].each do |start_page, expected|
            extraction = document.extract(start_page: start_page, end_page: 11, page_marker_offset: offset)

            assert_equal expected, extraction.text
            assert_predicate extraction.text, :valid_encoding?
            assert_equal "canonical_page_slice", extraction.scope
            assert_equal [start_page, 11], [extraction.start_page, extraction.end_page]
            assert_empty extraction.warnings
          end
        end
      end
    end
  end

  # Assert independent ASCII EOF and UTF-8 non-final byte controls stay exact.
  # Disposable source/expected literals require no normalization; mismatches fail assertions.
  def test_preserves_ascii_final_and_utf8_nonfinal_controls
    cases = [
      ["<!-- PAGE: 1 -->\n1\n<!-- PAGE: 2 -->\n2 \t\n", 2, "<!-- PAGE: 2 -->\n2 \t\n"],
      ["α\n<!-- PAGE: 1 -->\nβ\n<!-- PAGE: 2 -->\nΩ\n", 1, "<!-- PAGE: 1 -->\nβ\n"]
    ]
    Dir.mktmpdir("source-document") do |dir|
      path = File.join(dir, "source.md")
      cases.each do |source, page, expected|
        File.binwrite(path, source)
        extraction = AFScoring::SourceDocument.new(path).extract(start_page: page, end_page: page)

        assert_equal expected, extraction.text
        assert_equal "canonical_page_slice", extraction.scope
        assert_empty extraction.warnings
      end
    end
  end

  # Assert boundary refusals and explicit fallback retain their actual scopes/warnings.
  # Invalid mechanical ranges must raise SourceBoundaryError; fallback returns the original bytes.
  def test_preserves_boundary_refusals_and_explicit_full_source_fallback
    cases = [
      ["<!-- PAGE: 1 -->\nα\n", nil, 1, "Canonical Start Page / End Page are unavailable"],
      ["α\n", 1, 1, "No supported page markers found"],
      ["<!-- PAGE: 1 -->\nα\n", 1, 2, "Required source page marker(s) not found: 2"],
      ["<!-- PAGE: 1 -->\nα\n<!-- PAGE: 3 -->\nβ\n<!-- PAGE: 2 -->\nΩ\n", 2, 3,
       "Page marker ordering is inconsistent for 2-3"]
    ]
    Dir.mktmpdir("source-document") do |dir|
      path = File.join(dir, "source.md")
      cases.each do |source, first, last, message|
        File.binwrite(path, source)
        document = AFScoring::SourceDocument.new(path)
        error = assert_raises(AFScoring::SourceBoundaryError) do
          document.extract(start_page: first, end_page: last)
        end
        assert_includes error.message, message

        extraction = document.extract(start_page: first, end_page: last, allow_full_source_fallback: true)
        assert_equal source, extraction.text
        assert_equal "full_source_fallback", extraction.scope
        assert_equal [nil, nil], [extraction.start_page, extraction.end_page]
        assert_equal ["SOURCE_BOUNDARY_UNVERIFIED", error.message], extraction.warnings
      end

      error = assert_raises(AFScoring::SourceBoundaryError) do
        AFScoring::SourceDocument.new(path).extract(start_page: 3, end_page: 2, allow_full_source_fallback: true)
      end
      assert_equal "Start page 3 exceeds end page 2", error.message
    end
  end

  # Assert inward clamping at EOF retains literal bytes, canonical endpoints and both warnings.
  # A zero gap must still raise SourceBoundaryError; valid gap-one input returns a clamped slice.
  def test_preserves_utf8_final_bytes_and_warnings_when_both_boundaries_are_clamped
    source = "<!-- PAGE: 2 -->\nα\n<!-- PAGE: 3 -->\nΩ \t\n"
    Dir.mktmpdir("source-document") do |dir|
      path = File.join(dir, "source.md")
      File.binwrite(path, source)
      document = AFScoring::SourceDocument.new(path)
      extraction = document.extract(start_page: 1, end_page: 4, allow_inward_boundary_clamp: true)

      assert_equal source, extraction.text
      assert_predicate extraction.text, :valid_encoding?
      assert_equal "canonical_page_slice_boundary_clamped", extraction.scope
      assert_equal [1, 4], [extraction.start_page, extraction.end_page]
      assert_equal [
        "SOURCE_BOUNDARY_START_MARKER_MISSING: requested source page 1; clamped inward to page 2",
        "SOURCE_BOUNDARY_END_MARKER_MISSING: requested source page 4; clamped inward to page 3"
      ], extraction.warnings
      error = assert_raises(AFScoring::SourceBoundaryError) do
        document.extract(start_page: 1, end_page: 4, allow_inward_boundary_clamp: true, max_inward_boundary_clamp_gap: 0)
      end
      assert_equal "Inward boundary clamp max gap must be at least 1", error.message
    end
  end

  def test_prefers_printed_page_markers_when_both_coordinate_systems_are_present
    Dir.mktmpdir("source-document") do |dir|
      path = File.join(dir, "source.md")
      File.write(path, <<~MD)
        <!-- PDF Page 157 -->
        <!-- Printed Page 156 -->
        chapter start
        <!-- PDF Page 158 -->
        <!-- Printed Page 157 -->
        chapter middle
        <!-- PDF Page 190 -->
        <!-- Printed Page 189 -->
        chapter conclusion
        <!-- PDF Page 191 -->
        <!-- Printed Page 190 -->
        appendix
      MD

      extraction = AFScoring::SourceDocument.new(path).extract(start_page: 156, end_page: 189)

      assert_equal "canonical_page_slice", extraction.scope
      assert_equal 156, extraction.start_page
      assert_equal 189, extraction.end_page
      assert_includes extraction.text, "chapter start"
      assert_includes extraction.text, "chapter conclusion"
      refute_includes extraction.text, "appendix"
    end
  end

  def test_falls_back_to_page_markers_when_printed_markers_are_absent
    Dir.mktmpdir("source-document") do |dir|
      path = File.join(dir, "source.md")
      File.write(path, <<~MD)
        <!-- PAGE: 10 -->
        first page
        <!-- PAGE: 11 -->
        second page
        <!-- PAGE: 12 -->
        outside range
      MD

      extraction = AFScoring::SourceDocument.new(path).extract(start_page: 10, end_page: 11)

      assert_includes extraction.text, "first page"
      assert_includes extraction.text, "second page"
      refute_includes extraction.text, "outside range"
    end
  end

  def test_falls_back_to_pdf_page_markers_when_printed_markers_are_absent
    Dir.mktmpdir("source-document") do |dir|
      path = File.join(dir, "source.md")
      File.write(path, <<~MD)
        <!-- PDF Page 20 -->
        first page
        <!-- PDF Page 21 -->
        second page
        <!-- PDF Page 22 -->
        outside range
      MD

      extraction = AFScoring::SourceDocument.new(path).extract(start_page: 20, end_page: 21)

      assert_includes extraction.text, "first page"
      assert_includes extraction.text, "second page"
      refute_includes extraction.text, "outside range"
    end
  end

  def test_applies_page_marker_offset_without_changing_canonical_pages
    Dir.mktmpdir("source-document") do |dir|
      path = File.join(dir, "source.md")
      File.write(path, <<~MD)
        <!-- PDF Page 60 -->
        canonical printed page 57
        <!-- PDF Page 61 -->
        canonical printed page 58
        <!-- PDF Page 66 -->
        canonical printed page 63 epilogue
        <!-- PDF Page 67 -->
        next adventure
      MD

      extraction = AFScoring::SourceDocument.new(path).extract(
        start_page: 57,
        end_page: 63,
        page_marker_offset: +3
      )

      assert_equal 57, extraction.start_page
      assert_equal 63, extraction.end_page
      assert_includes extraction.text, "canonical printed page 57"
      assert_includes extraction.text, "canonical printed page 63 epilogue"
      refute_includes extraction.text, "next adventure"
    end
  end

  def test_levels_context_before_selects_relevant_precanonical_pages_only
    Dir.mktmpdir("source-document") do |dir|
      path = File.join(dir, "source.md")
      File.write(path, <<~MD)
        <!-- PAGE: 1 -->
        unrelated introduction
        <!-- PAGE: 2 -->
        Character Advancement: characters start at 1st level.
        <!-- PAGE: 3 -->
        unrelated setting material
        <!-- PAGE: 4 -->
        Characters advance to 2nd level when they enter the next realm.
        <!-- PAGE: 5 -->
        canonical adventure begins here
        <!-- PAGE: 6 -->
        canonical adventure continues
      MD

      context = AFScoring::SourceDocument.new(path).levels_context_before(start_page: 5)

      assert_includes context, "characters start at 1st level"
      assert_includes context, "advance to 2nd level"
      refute_includes context, "unrelated introduction"
      refute_includes context, "canonical adventure begins here"
    end
  end

  def test_levels_context_before_honors_page_marker_offset_and_page_cap
    Dir.mktmpdir("source-document") do |dir|
      path = File.join(dir, "source.md")
      File.write(path, <<~MD)
        <!-- PDF Page 11 -->
        level guidance one
        <!-- PDF Page 12 -->
        level guidance two
        <!-- PDF Page 13 -->
        level guidance three
        <!-- PDF Page 14 -->
        canonical adventure
      MD

      context = AFScoring::SourceDocument.new(path).levels_context_before(
        start_page: 13,
        page_marker_offset: +1,
        max_pages: 2
      )

      refute_includes context, "level guidance one"
      assert_includes context, "level guidance two"
      assert_includes context, "level guidance three"
      refute_includes context, "canonical adventure"
    end
  end

  def test_recognizes_page_markers_inside_markdown_blockquotes
    Dir.mktmpdir("source-document") do |dir|
      path = File.join(dir, "source.md")
      File.write(path, <<~MD)
        <!-- PAGE: 104 -->
        first page
        > [!SIDEBAR]
        > <!-- PAGE: 105 -->
        > quoted page marker content
        <!-- PAGE: 106 -->
        outside range
      MD

      extraction = AFScoring::SourceDocument.new(path).extract(start_page: 104, end_page: 105)

      assert_equal "canonical_page_slice", extraction.scope
      assert_empty extraction.warnings
      assert_includes extraction.text, "first page"
      assert_includes extraction.text, "quoted page marker content"
      refute_includes extraction.text, "outside range"
    end
  end

  def test_clamps_missing_start_marker_inward_by_one_page
    Dir.mktmpdir("source-document") do |dir|
      path = File.join(dir, "source.md")
      File.write(path, <<~MD)
        <!-- PAGE: 17 -->
        previous adventure
        <!-- PAGE: 19 -->
        chapter starts on first available source page
        <!-- PAGE: 20 -->
        chapter continues
        <!-- PAGE: 21 -->
        outside range
      MD

      extraction = AFScoring::SourceDocument.new(path).extract(
        start_page: 18,
        end_page: 20,
        allow_inward_boundary_clamp: true
      )

      assert_equal "canonical_page_slice_boundary_clamped", extraction.scope
      assert_equal 18, extraction.start_page
      assert_equal 20, extraction.end_page
      assert_equal 1, extraction.warnings.length
      assert_match(/START_MARKER_MISSING.*18.*19/, extraction.warnings.first)
      refute_includes extraction.text, "previous adventure"
      assert_includes extraction.text, "chapter starts on first available source page"
      assert_includes extraction.text, "chapter continues"
      refute_includes extraction.text, "outside range"
    end
  end

  def test_clamps_missing_end_marker_inward_by_one_page
    Dir.mktmpdir("source-document") do |dir|
      path = File.join(dir, "source.md")
      File.write(path, <<~MD)
        <!-- PAGE: 124 -->
        adventure begins
        <!-- PAGE: 135 -->
        available conclusion
        content with omitted page marker remains before the next marker
        <!-- PAGE: 137 -->
        next adventure
      MD

      extraction = AFScoring::SourceDocument.new(path).extract(
        start_page: 124,
        end_page: 136,
        allow_inward_boundary_clamp: true
      )

      assert_equal "canonical_page_slice_boundary_clamped", extraction.scope
      assert_equal 124, extraction.start_page
      assert_equal 136, extraction.end_page
      assert_equal 1, extraction.warnings.length
      assert_match(/END_MARKER_MISSING.*136.*135/, extraction.warnings.first)
      assert_includes extraction.text, "adventure begins"
      assert_includes extraction.text, "available conclusion"
      assert_includes extraction.text, "content with omitted page marker"
      refute_includes extraction.text, "next adventure"
    end
  end

  def test_boundary_gap_larger_than_one_page_still_fails_closed
    Dir.mktmpdir("source-document") do |dir|
      path = File.join(dir, "source.md")
      File.write(path, <<~MD)
        <!-- PAGE: 10 -->
        previous material
        <!-- PAGE: 13 -->
        requested range eventually appears
      MD

      error = assert_raises(AFScoring::SourceBoundaryError) do
        AFScoring::SourceDocument.new(path).extract(
          start_page: 11,
          end_page: 13,
          allow_inward_boundary_clamp: true
        )
      end

      assert_match(/Required source page marker/, error.message)
    end
  end

  def test_explicit_max_gap_clamps_missing_end_marker_by_two_pages
    Dir.mktmpdir("source-document") do |dir|
      path = File.join(dir, "source.md")
      File.write(path, <<~MD)
        <!-- PAGE: 120 -->
        adventure begins
        <!-- PAGE: 129 -->
        final marked page
        unmarked conclusion from omitted pages remains here
        <!-- PAGE: 132 -->
        next adventure
      MD

      extraction = AFScoring::SourceDocument.new(path).extract(
        start_page: 120,
        end_page: 131,
        allow_inward_boundary_clamp: true,
        max_inward_boundary_clamp_gap: 2
      )

      assert_equal "canonical_page_slice_boundary_clamped", extraction.scope
      assert_match(/END_MARKER_MISSING.*131.*129/, extraction.warnings.first)
      assert_includes extraction.text, "unmarked conclusion from omitted pages"
      refute_includes extraction.text, "next adventure"
    end
  end

  def test_explicit_max_gap_prefers_nearest_available_marker
    Dir.mktmpdir("source-document") do |dir|
      path = File.join(dir, "source.md")
      File.write(path, <<~MD)
        <!-- PAGE: 120 -->
        adventure begins
        <!-- PAGE: 129 -->
        earlier page
        <!-- PAGE: 130 -->
        nearest available conclusion
        <!-- PAGE: 132 -->
        next adventure
      MD

      extraction = AFScoring::SourceDocument.new(path).extract(
        start_page: 120,
        end_page: 131,
        allow_inward_boundary_clamp: true,
        max_inward_boundary_clamp_gap: 2
      )

      assert_match(/END_MARKER_MISSING.*131.*130/, extraction.warnings.first)
      assert_includes extraction.text, "nearest available conclusion"
      refute_includes extraction.text, "next adventure"
    end
  end

end
