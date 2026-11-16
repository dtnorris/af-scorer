# frozen_string_literal: true

require_relative "source_markdown_owner"

module AFScoring
  # Scorer boundary options and Levels-context policy over the raw MD reader.
  class SourceDocument
    Extraction = Struct.new(:text, :source_file, :scope, :start_page, :end_page, :warnings, keyword_init: true)
    MAX_BOUNDARY_MARKER_GAP = 1
    LEVEL_CONTEXT_PATTERN = /\b(?:level(?:s)?|advanc(?:e|es|ed|ement|ing)|milestone)\b/i
    LEVEL_CONTEXT_PRIORITY_PATTERN = /(?:character advancement|characters?\s+(?:start|begin)|start(?:ing)?\s+(?:at|level)|advanc(?:e|es|ed|ement|ing).*\blevel)/i
    MAX_LEVEL_CONTEXT_PAGES = 6

    # Load one raw source through MD; missing owner/file raises a scorer error.
    def initialize(path)
      owner = SourceMarkdownOwner.load!(error_class: ConfigurationError)
      @document = owner::SourceDocument.new(path)
    rescue StandardError => error
      raise SourceResolutionError, error.message if defined?(AFSourceMD::SourceResolutionError) && error.is_a?(AFSourceMD::SourceResolutionError)
      raise
    end

    # Extract requested pages with the scorer's existing fallback/clamp options;
    # return its Extraction or raise SourceBoundaryError for refused boundaries.
    def extract(start_page:, end_page:, page_marker_offset: 0,
                allow_full_source_fallback: false, allow_inward_boundary_clamp: false,
                max_inward_boundary_clamp_gap: MAX_BOUNDARY_MARKER_GAP)
      Extraction.new(**@document.extract(start_page:, end_page:, page_marker_offset:,
        allow_full_source_fallback:, allow_inward_boundary_clamp:,
        max_inward_boundary_clamp_gap:).to_h)
    rescue AFSourceMD::SourceBoundaryError => error
      raise SourceBoundaryError, error.message
    end

    # Choose prior pages containing Levels context under the existing scorer
    # heuristics; return raw joined text, using MD only for byte access/inventory.
    def levels_context_before(start_page:, page_marker_offset: 0, max_pages: MAX_LEVEL_CONTEXT_PAGES)
      return "" unless start_page

      markers = page_markers
      return "" if markers.empty?

      marker_start_page = start_page + page_marker_offset
      start_index = markers.index { |marker| marker[:page] == marker_start_page }
      return "" unless start_index && start_index.positive?

      relevant = markers.first(start_index).each_with_index.filter_map do |marker, index|
        next_marker = markers[index + 1]
        page_text = @document.byteslice(marker[:offset]...next_marker.fetch(:offset))
        next unless page_text.match?(LEVEL_CONTEXT_PATTERN)

        { index: index, text: page_text, priority: page_text.match?(LEVEL_CONTEXT_PRIORITY_PATTERN) }
      end

      priority = relevant.select { |page| page[:priority] }.last(max_pages)
      remaining = max_pages - priority.length
      generic = remaining.positive? ? relevant.reject { |page| page[:priority] }.last(remaining) : []

      (priority + generic)
        .sort_by { |page| page[:index] }
        .map { |page| page[:text] }
        .join("\n")
    end

    # Return MD's marker inventory without changing precedence or byte offsets.
    def page_markers
      @document.page_markers
    end
  end
end
