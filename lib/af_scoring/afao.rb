# frozen_string_literal: true

module AFScoring
  class AFAO
    SCORER_EXCLUDED_SUBSECTIONS = {
      "Seriousness" => [
        "Calibration Benchmarks"
      ],
      "Exploration Emphasis" => [
        "Calibration Benchmarks"
      ],
      "# of Sessions" => [
        "Calibration Benchmarks",
        "Calibration and Blind Validation Record",
        "Blind-Validation Agreement Interpretation"
      ],
      "GM Preparation Burden" => [
        "Calibration Benchmarks",
        "AFAO 1.6 Score-5 Benchmark Expansion and Blind Replication"
      ],
      "GM Beginner Suitability" => [
        "Calibration Benchmarks",
        "Adjacent-Boundary Calibration",
        "Blind Validation and Adjudication Record"
      ]
    }.freeze

    attr_reader :path, :text, :version

    def initialize(path)
      @path = File.expand_path(path)
      raise SpecificationError, "AFAO file does not exist: #{@path}" unless File.file?(@path)
      @text = File.read(@path, encoding: "UTF-8")
      @version = detect_version
      @sections = parse_dimension_sections
      validate_required_sections!
    end

    # Return a parser view bound to a resolved target decision, preserving original text.
    # Invalid context raises ConfigurationError; no expectations enter inference inputs.
    def for_target(eligibility)
      unless eligibility.is_a?(TargetEligibility)
        raise ConfigurationError, "AFAO target view requires resolved target eligibility"
      end
      eligibility.verify!(adventure_id: eligibility.context.dig("adventure", "id"), afao: self)
      view = dup
      view.instance_variable_set(:@target_eligibility, eligibility)
      view
    end

    def rubric_for_group(group_name, target_id:, target_title:)
      rubric_for_dimensions(
        DimensionGroups.fetch(group_name),
        target_id: target_id,
        target_title: target_title
      )
    end

    def rubric_for_dimensions(dimension_names, target_id:, target_title:)
      dimension_names.map do |name|
        DimensionGroups.group_for_dimension(name)
        section = @sections.fetch(name)
        section = strip_non_scoring_subsections(
          section, dimension_name: name,
          additional_headings: @target_eligibility&.historical? ? [] : ["Calibration Benchmarks", "Calibration Reference Cases"]
        )
        scrub_target_reference(section, target_id: target_id, target_title: target_title)
      end.join("\n\n")
    end

    def rubric_for_dimension(dimension_name, target_id:, target_title:)
      rubric_for_dimensions([dimension_name], target_id: target_id, target_title: target_title)
    end

    # Machine-readable expectations are derived only from explicit calibration
    # tables in AFAO. They are never included in the target scorer's blind input.
    def calibration_expectations
      expectations = Hash.new { |h, k| h[k] = {} }
      extract_sessions_expectations(expectations)
      extract_level_expectations(expectations)
      DimensionGroups::INTERPRETIVE.each do |dimension|
        extract_interpretive_expectations(dimension, expectations)
      end
      expectations
    end

    private

    def detect_version
      match = @text.match(/^##\s+Version\s+([^\s]+)\s*$/i)
      raise SpecificationError, "Unable to detect AFAO version in #{@path}" unless match
      match[1]
    end

    def parse_dimension_sections
      sections = {}
      starts = []
      second_level_starts = []
      offset = 0
      @text.each_line do |line|
        if (m = line.match(/^###\s+(\d+)\.\s+(.+?)\s*$/))
          starts << { offset: offset, name: m[2].strip }
        elsif line.match?(/^##\s+/)
          second_level_starts << offset
        end
        offset += line.bytesize
      end

      starts.each_with_index do |entry, index|
        finish_candidates = []
        finish_candidates << starts[index + 1][:offset] if starts[index + 1]
        next_second_level = second_level_starts.find { |candidate| candidate > entry[:offset] }
        finish_candidates << next_second_level if next_second_level
        finish = finish_candidates.min || @text.bytesize

        canonical = canonical_dimension_name(entry[:name])
        next unless canonical
        sections[canonical] = @text.byteslice(entry[:offset]...finish)
      end
      sections
    end

    def canonical_dimension_name(name)
      normalized = name.gsub(/\s+/, " ").strip
      return "# of Sessions" if normalized.start_with?("# of Sessions")
      return "Levels" if normalized == "Levels"
      DimensionGroups::INTERPRETIVE.find { |d| d == normalized }
    end

    def validate_required_sections!
      required = ["# of Sessions", "Levels"] + DimensionGroups::INTERPRETIVE
      missing = required - @sections.keys
      raise SpecificationError, "AFAO #{@version} is missing required dimension sections: #{missing.join(', ')}" unless missing.empty?
    end

    # Exclude selected non-scoring histories plus conservative unbound reference tables.
    # Returns section text, preserving primary anchors; unknown dimensions have no history.
    def strip_non_scoring_subsections(section, dimension_name:, additional_headings: [])
      headings = SCORER_EXCLUDED_SUBSECTIONS.fetch(dimension_name, []) + additional_headings
      return section if headings.empty?

      normalized_headings = headings.map { |heading| normalize_reference_text(heading) }
      cleaned = []
      skipped_heading_level = nil

      section.each_line do |line|
        if (match = line.match(/^([#]{1,6})\s+(.+?)\s*$/))
          heading_level = match[1].length
          skipped_heading_level = nil if skipped_heading_level && heading_level <= skipped_heading_level

          if skipped_heading_level.nil? &&
              normalized_headings.include?(normalize_reference_text(match[2]))
            skipped_heading_level = heading_level
            next
          end
        end

        next if skipped_heading_level

        cleaned << line
      end

      cleaned.join
    end

    def scrub_target_reference(section, target_id:, target_title:)
      if @target_eligibility
        @target_eligibility.verify_target!(adventure_id: target_id, target_title: target_title, afao: self)
      end
      unless @target_eligibility&.historical?
        return scrub_unbound_references(section, target_title: target_title)
      end

      terms = target_reference_terms(target_id: target_id, target_title: target_title)
      section = strip_calibration_benchmarks_for_target(section, target_id: target_id)
      section = strip_target_subsections(section, terms)
      blocks = section.split(/\n{2,}/)
      cleaned = blocks.filter_map do |block|
        if markdown_table?(block)
          lines = block.lines.filter_map { |line| scrub_target_table_line(line, terms) }
          lines.join.strip.empty? ? nil : lines.join
        else
          contains_target_reference?(block, terms) ? nil : block
        end
      end
      cleaned.join("\n\n")
    end

    # Apply the same conservative reference exclusion to every unbound/new target.
    # Remove historical reference subsections/blocks independently of its local ADV;
    # keep primary scale anchors and general rules. Returns rubric text; never reads
    # machine-readable expectations or modifies the selected AFAO source material.
    def scrub_unbound_references(section, target_title:)
      historical_titles = @text.scan(/ADV-\d{4}\s*[—–]\s*([^|*;\n]+)/).flatten
      historical_terms = (adventure_ids(@text) + historical_titles).map { |term| normalize_reference_text(term) }
      title_terms = target_reference_terms(target_id: nil, target_title: target_title)
      terms = (historical_terms + title_terms).reject(&:empty?).uniq
      section = strip_target_subsections(section, terms)
      section.split(/\n{2,}/).filter_map do |block|
        if markdown_table?(block)
          lines = block.lines.reject { |line| contains_target_reference?(line, terms) }
          lines.join unless lines.join.strip.empty?
        else
          block unless contains_target_reference?(block, terms)
        end
      end.join("\n\n")
    end

    def strip_calibration_benchmarks_for_target(section, target_id:)
      target = target_id.to_s.upcase.strip
      return section unless target.match?(/\AADV-\d{4}\z/)

      lines = section.lines
      start = lines.index { |line| line.match?(/^####\s+Calibration Benchmarks\s*$/i) }
      return section unless start

      finish = ((start + 1)...lines.length).find { |i| lines[i].match?(/^####\s+/) } || lines.length
      benchmark_lines = lines[start...finish]
      return section unless benchmark_lines.any? { |line| adventure_ids(line).include?(target) }

      (lines[0...start] + lines[finish...]).join
    end

    def strip_target_subsections(section, terms)
      cleaned = []
      skipped_heading_level = nil

      section.each_line do |line|
        if (match = line.match(/^([#]{1,6})\s+(.+?)\s*$/))
          heading_level = match[1].length
          skipped_heading_level = nil if skipped_heading_level && heading_level <= skipped_heading_level

          if skipped_heading_level.nil? && heading_level == 4
            heading = normalize_reference_text(match[2])
            if terms.any? { |term| heading.include?(term) }
              skipped_heading_level = heading_level
              next
            end
          end
        end

        next if skipped_heading_level

        cleaned << line
      end

      cleaned.join
    end

    def markdown_table?(block)
      lines = block.lines.reject { |line| line.strip.empty? }
      lines.length >= 2 && lines.count { |line| line.lstrip.start_with?("|") } >= 2
    end

    def scrub_target_table_line(line, terms)
      return line unless contains_target_reference?(line, terms)

      cells = table_cells(line)
      return nil if cells.empty?

      scrubbed_cells = cells.map do |cell|
        entries = cell.split(/\s*;\s*/)
        next cell unless entries.length > 1 && entries.all? { |entry| entry.match?(/ADV-\d{4}/) }

        entries.reject { |entry| contains_target_reference?(entry, terms) }.join("; ")
      end

      return nil if scrubbed_cells == cells
      return nil if scrubbed_cells.any? { |cell| contains_target_reference?(cell, terms) }

      "| #{scrubbed_cells.join(' | ')} |\n"
    end

    def contains_target_reference?(value, terms)
      candidate = normalize_reference_text(value)
      terms.any? { |term| candidate.include?(term) }
    end

    def target_reference_terms(target_id:, target_title:)
      terms = [target_id, target_title].compact.map { |value| normalize_reference_text(value) }

      normalized_title = normalize_reference_text(target_title)
      unless normalized_title.empty?
        without_leading_article = normalized_title.sub(/\A(?:the|a|an)\s+/, "")
        terms << without_leading_article unless without_leading_article == normalized_title
      end

      terms.reject(&:empty?).uniq
    end

    def normalize_reference_text(value)
      value.to_s.downcase.gsub(/\s+/, " ").strip
    end

    def subsection_body(section, heading_pattern)
      lines = section.lines
      start = lines.index { |line| line.match?(/^####\s+#{heading_pattern}/i) }
      return nil unless start
      finish = ((start + 1)...lines.length).find { |i| lines[i].match?(/^####\s+/) } || lines.length
      lines[start...finish].join
    end

    def extract_sessions_expectations(expectations)
      block = subsection_body(@sections.fetch("# of Sessions"), "Calibration Benchmarks")
      return unless block
      block.each_line do |line|
        cells = table_cells(line)
        next unless cells.length >= 2
        value = markdown_integer(cells[0])
        next unless value
        adventure_ids(cells[1]).each { |id| expectations[id]["# of Sessions"] = value }
      end
    end

    def extract_level_expectations(expectations)
      block = subsection_body(@sections.fetch("Levels"), "Calibration Reference Cases")
      return unless block
      block.each_line do |line|
        cells = table_cells(line)
        next unless cells.length >= 3
        id = cells[0][/ADV-\d{4}/]
        next unless id
        expectations[id]["Level Start"] = level_value(cells[1])
        expectations[id]["Level End"] = level_value(cells[2])
      end
    end

    def extract_interpretive_expectations(dimension, expectations)
      block = subsection_body(@sections.fetch(dimension), "Calibration Benchmarks")
      return unless block
      block.each_line do |line|
        cells = table_cells(line)
        next unless cells.length >= 2
        score = markdown_integer(cells[0])
        next unless score && score.between?(1, 5)
        adventure_ids(cells[1]).each { |id| expectations[id][dimension] = score }
      end
    end

    def table_cells(line)
      stripped = line.strip
      return [] unless stripped.start_with?("|") && stripped.end_with?("|")
      stripped[1...-1].split("|").map(&:strip)
    end

    def markdown_integer(cell)
      plain = cell.gsub("*", "")
      match = plain.match(/\A\s*(\d+)/)
      match && match[1].to_i
    end

    def level_value(cell)
      plain = cell.gsub("*", "").strip
      return plain.to_i if plain.match?(/\A\d+\z/)
      return "Uncertain" if plain.match?(/uncertain/i)
      nil
    end

    def adventure_ids(cell)
      cell.scan(/ADV-\d{4}/).uniq
    end
  end
end
