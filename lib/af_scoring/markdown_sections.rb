# frozen_string_literal: true

module AFScoring
  class MarkdownSections
    Section = Struct.new(:level, :heading, :body, :start_line, keyword_init: true)

    def initialize(text)
      @text = text
    end

    def sections(level: nil)
      lines = @text.lines
      found = []
      lines.each_with_index do |line, index|
        next unless (match = line.match(/^(#+)\s+(.+?)\s*$/))
        current_level = match[1].length
        next if level && current_level != level
        end_index = find_end(lines, index, current_level)
        found << Section.new(
          level: current_level,
          heading: match[2].strip,
          body: lines[index...end_index].join,
          start_line: index + 1
        )
      end
      found
    end

    def find_heading(heading, level: nil)
      sections(level: level).find { |s| normalize(s.heading) == normalize(heading) }
    end

    def find_heading_matching(pattern, level: nil)
      sections(level: level).find { |s| s.heading.match?(pattern) }
    end

    private

    def find_end(lines, start_index, current_level)
      ((start_index + 1)...lines.length).each do |i|
        match = lines[i].match(/^(#+)\s+/)
        return i if match && match[1].length <= current_level
      end
      lines.length
    end

    def normalize(value)
      value.to_s.downcase.gsub(/\s+/, " ").strip
    end
  end
end
