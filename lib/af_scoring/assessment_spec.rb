# frozen_string_literal: true

module AFScoring
  class AssessmentSpec
    PROMPT_SECTIONS = [
      "3. Governing Principles",
      "6. Assessment States and Null Semantics",
      "7. Source Basis and Evidence Requirements",
      "8. Production Assessment Protocol",
      "9. Confidence Guidance",
      "10. Path-Sensitivity Guidance",
      "11. Rationale and Evidence Provenance",
      "12. Quality Control and Review Disposition",
      "13. Blindness and Anti-Bias Requirements",
      "19. LLM Application Guidance"
    ].freeze

    attr_reader :path, :text, :version

    def initialize(path)
      @path = File.expand_path(path)
      raise SpecificationError, "Assessment Specification does not exist: #{@path}" unless File.file?(@path)
      @text = File.read(@path, encoding: "UTF-8")
      @version = detect_version
    end

    def prompt_text
      parser = MarkdownSections.new(@text)
      sections = PROMPT_SECTIONS.filter_map { |heading| parser.find_heading(heading, level: 2)&.body }
      raise SpecificationError, "Unable to extract required Assessment Specification prompt sections" if sections.empty?
      sections.join("\n\n")
    end

    private

    def detect_version
      match = @text.match(/^##\s+Version\s+([^\s]+)\s*$/i)
      raise SpecificationError, "Unable to detect Assessment Specification version in #{@path}" unless match
      match[1]
    end
  end
end
