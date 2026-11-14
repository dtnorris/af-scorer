# frozen_string_literal: true

module AFScoring
  module NosTwoStage
    SOURCE_HEADING_PATTERN = /^((?:#){1,6})\s+(.+?)\s*$/
    SOURCE_PAGE_MARKER_PATTERN =
      /^<!--\s*(?:Printed\s+Page|PDF\s+Page|PAGE:)\s*\d+\s*-->\s*$/i

    module_function

    def canonical_heading_extraction(extraction, adventure:)
      unless extraction.scope == "canonical_page_slice"
        raise SourceBoundaryError,
              "NoS two-stage pilot requires canonical_page_slice source scope; got #{extraction.scope.inspect}"
      end

      headings = []
      page_markers = []
      cursor = 0

      extraction.text.each_line do |line|
        page_markers << { offset: cursor, line: line } if line.match?(SOURCE_PAGE_MARKER_PATTERN)

        if (match = line.match(SOURCE_HEADING_PATTERN))
          headings << {
            offset: cursor,
            level: match[1].length,
            title: normalize_source_heading(match[2])
          }
        end

        cursor += line.bytesize
      end

      target = normalize_source_heading(adventure.title)
      matches = headings.select { |heading| heading[:title] == target }

      if matches.empty?
        # Some canonical adventures span chapter-level content without repeating
        # the adventure title inside the catalog's verified page slice. In that
        # case the page slice is already the authoritative boundary; title-heading
        # trimming is only a refinement when an exact heading is present.
        return SourceDocument::Extraction.new(
          text: extraction.text,
          source_file: extraction.source_file,
          scope: extraction.scope,
          start_page: extraction.start_page,
          end_page: extraction.end_page,
          warnings: extraction.warnings.dup <<
            "NOS_TWO_STAGE_HEADING_BOUNDARY_NOT_FOUND_USING_CANONICAL_PAGE_SLICE"
        )
      end
      if matches.length > 1
        raise SourceBoundaryError,
              "NoS two-stage source boundary found multiple adventure-title headings for #{adventure.title.inspect}"
      end

      start_heading = matches.first
      finish_heading = headings.find do |heading|
        heading[:offset] > start_heading[:offset] &&
          heading[:level] <= start_heading[:level]
      end
      finish_offset = finish_heading ? finish_heading[:offset] : extraction.text.bytesize

      body = extraction.text.byteslice(start_heading[:offset]...finish_offset)

      # Preserve the page marker immediately preceding the title heading so the
      # first retained claims still have a valid evidence locator.
      preceding_marker = page_markers
        .select { |marker| marker[:offset] < start_heading[:offset] }
        .last
      body = "#{preceding_marker[:line].rstrip}\n\n#{body.lstrip}" if preceding_marker

      SourceDocument::Extraction.new(
        text: body,
        source_file: extraction.source_file,
        scope: "canonical_heading_slice",
        start_page: extraction.start_page,
        end_page: extraction.end_page,
        warnings: extraction.warnings.dup << "NOS_TWO_STAGE_HEADING_BOUNDARY_TRIMMED"
      )
    end

    def normalize_source_heading(value)
      value.to_s
        .gsub(/[*_`]/, "")
        .gsub(/\s+/, " ")
        .strip
        .downcase
    end
    private_class_method :normalize_source_heading
  end

  module NosTwoStageSourceBoundary
    private

    def prepare_adventure(adventure_id)
      prepared = super
      prepared.extraction = NosTwoStage.canonical_heading_extraction(
        prepared.extraction,
        adventure: prepared.adventure
      )
      prepared
    end
  end

  NosTwoStageRunner.prepend(NosTwoStageSourceBoundary)
end
