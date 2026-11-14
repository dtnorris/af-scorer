# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "cgi"
require "stringio"

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))
require "af_scoring"
require "af_scoring/experiments"

module TestSupport
  module_function

  def build_xlsx(path, sheet_name:, rows:)
    Dir.mktmpdir("xlsx-fixture") do |dir|
      FileUtils.mkdir_p(File.join(dir, "_rels"))
      FileUtils.mkdir_p(File.join(dir, "xl", "_rels"))
      FileUtils.mkdir_p(File.join(dir, "xl", "worksheets"))

      File.write(File.join(dir, "[Content_Types].xml"), <<~XML)
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
          <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
          <Default Extension="xml" ContentType="application/xml"/>
          <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
          <Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
        </Types>
      XML
      File.write(File.join(dir, "_rels", ".rels"), <<~XML)
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
          <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
        </Relationships>
      XML
      File.write(File.join(dir, "xl", "workbook.xml"), <<~XML)
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
          <sheets><sheet name="#{xml_escape(sheet_name)}" sheetId="1" r:id="rId1"/></sheets>
        </workbook>
      XML
      File.write(File.join(dir, "xl", "_rels", "workbook.xml.rels"), <<~XML)
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
          <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>
        </Relationships>
      XML

      sheet_rows = rows.each_with_index.map do |row, r|
        cells = row.each_with_index.map do |value, c|
          ref = "#{column_letters(c + 1)}#{r + 1}"
          case value
          when Numeric
            %(<c r="#{ref}"><v>#{value}</v></c>)
          when true, false
            %(<c r="#{ref}" t="b"><v>#{value ? 1 : 0}</v></c>)
          when nil
            nil
          else
            %(<c r="#{ref}" t="inlineStr"><is><t>#{xml_escape(value.to_s)}</t></is></c>)
          end
        end.compact.join
        %(<row r="#{r + 1}">#{cells}</row>)
      end.join
      File.write(File.join(dir, "xl", "worksheets", "sheet1.xml"), <<~XML)
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>#{sheet_rows}</sheetData></worksheet>
      XML

      FileUtils.rm_f(path)
      ok = system("zip", "-qr", File.expand_path(path), ".", chdir: dir)
      raise "zip command failed" unless ok
    end
    path
  end

  def column_letters(number)
    letters = +""
    n = number
    while n.positive?
      n -= 1
      letters.prepend((65 + (n % 26)).chr)
      n /= 26
    end
    letters
  end

  def xml_escape(value)
    CGI.escapeHTML(value).gsub("'", "&apos;")
  end

  def dimension_names
    AFScoring::DimensionGroups::INTERPRETIVE
  end

  def minimal_afao(target_id: "ADV-0001", target_title: "Fixture Adventure")
    sections = []
    sections << <<~MD
      ## Version 1.0

      ### 1. # of Sessions
      **Definition:** duration.
      #### Calibration Benchmarks
      | Normalized Sessions | Calibrated benchmark adventures | Calibration regime |
      | ---: | --- | --- |
      | **2** | **#{target_id} — #{target_title}** | Very Short |
    MD
    sections << <<~MD
      ### 2. Levels
      **Definition:** levels.
      #### Calibration Reference Cases
      | Adventure | Level Start | Level End | Calibration role |
      | --- | ---: | ---: | --- |
      | **#{target_id} — #{target_title}** | **1** | **2** | fixture |
    MD
    dimension_names.each_with_index do |name, index|
      sections << <<~MD
        ### #{index + 3}. #{name}
        **Definition:** fixture definition for #{name}.
        | Score | Meaning |
        | ---: | --- |
        | **1 — Minimal** | minimal |
        | **2 — Low** | low |
        | **3 — Mixed** | mixed |
        | **4 — High** | high |
        | **5 — Dominant** | dominant |
        #### Calibration Benchmarks
        | Score | Calibrated benchmark adventures |
        | ---: | --- |
        | **3 — Mixed** | **#{target_id} — #{target_title}** |
      MD
    end
    sections.join("\n")
  end

  # Explicitly select this mechanical fixture's resolved context for historical
  # comparison. Returns the verified eligibility; real preparation errors propagate.
  # Observed context alone is never historical membership evidence in production.
  def bind_historical(config, adventure_id = "ADV-0001")
    prepared = AFScoring::Runner.new(config: config, logger: ->(_message) {}).prepare_source(adventure_id)
    context = prepared.fetch("target_eligibility").fetch("context")
    config.data["target_bindings"] = {
      "contract_version" => AFScoring::TargetEligibility::CONTRACT_VERSION,
      "targets" => [{ "context" => context, "calibration" => "historical", "afao_sha256" => Digest::SHA256.file(config.afao_path).hexdigest }]
    }
    AFScoring::TargetEligibility.new(selection: config.dig("target_bindings"), context: context, afao: AFScoring::AFAO.new(config.afao_path))
  end

  # Supply parser/reference unit tests with a real resolved mechanical context next
  # to their temporary AFAO. Returns [bound AFAO view, eligibility]; owner errors
  # propagate. The caller's temporary-directory lifetime owns all created files.
  def historical_afao(path, target_id: "ADV-0001", target_title: "Fixture Adventure")
    root = File.join(File.dirname(path), "eligibility")
    FileUtils.mkdir_p(File.join(root, "config"))
    build_xlsx(File.join(root, "catalog.xlsx"), sheet_name: "Adventure Catalog", rows: [
      ["Adventure ID", "Adventure Title", "Page Count", "Source Book", "Book Publisher", "Start Page", "End Page"],
      [target_id, target_title, 1, "Mechanical Source", "Fixture", 1, 1]
    ])
    File.write(File.join(root, "source.md"), "<!-- PAGE: 1 -->\n1\n<!-- PAGE: 2 -->\n2\n")
    File.write(File.join(root, "registry.yml"), { "schema_version" => AFScoring::SourceResolver::REGISTRY_SCHEMA_VERSION, "sources" => { "Mechanical Source" => { "file" => "source.md" } } }.to_yaml)
    File.write(File.join(root, "assessment.md"), minimal_assessment_spec)
    File.write(File.join(root, "config/default.yml"), {
      "paths" => { "xlsx_root" => root, "source_root" => root, "specification_root" => root, "output_root" => File.join(root, "output") },
      "files" => { "catalog" => "catalog.xlsx", "source_registry" => "registry.yml", "afao" => path, "assessment_spec" => "assessment.md" },
      "review" => { "low_confidence_threshold" => 60, "moderate_confidence_ceiling" => 74 }
    }.to_yaml)
    config = AFScoring::Config.new(project_root: root)
    eligibility = bind_historical(config, target_id)
    [AFScoring::AFAO.new(path).for_target(eligibility), eligibility]
  end

  def minimal_assessment_spec
    headings = [
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
    ]
    "## Version 0.1\n\n" + headings.map { |h| "## #{h}\nFixture rules for #{h}.\n" }.join("\n")
  end

  def scored_group_payload(group_name, score: 3, confidence: 85)
    observations = {
      "source_boundary_uncertainty" => false,
      "possible_spec_contradiction" => false,
      "notes" => ""
    }
    if group_name == "sessions_levels"
      {
        "group" => group_name,
        "sessions" => {
          "assessment_state" => "Scored",
          "normalized_sessions" => 2,
          "practical_range_low" => 1,
          "practical_range_high" => 3,
          "confidence" => confidence,
          "path_sensitive" => false,
          "rationale" => "Two sessions is the best fit.",
          "evidence" => [{ "locator" => "PAGE: 1", "note" => "Compact two-part structure." }],
          "rubric_ambiguity" => false,
          "evidence_sufficient" => true
        },
        "level_start" => level_payload(1),
        "level_end" => level_payload(2),
        "group_observations" => observations
      }
    else
      {
        "group" => group_name,
        "dimensions" => AFScoring::DimensionGroups.fetch(group_name).map do |dimension|
          {
            "dimension" => dimension,
            "assessment_state" => "Scored",
            "score" => score,
            "confidence" => confidence,
            "path_sensitive" => false,
            "path_variation_affects_anchor" => false,
            "adjacent_lower_reason" => "Substantial recurring evidence exceeds the lower anchor.",
            "adjacent_higher_reason" => "It does not become dominant enough for the higher anchor.",
            "rationale" => "Fixture rationale for #{dimension}.",
            "evidence" => [{ "locator" => "PAGE: 1", "note" => "Fixture evidence." }],
            "rubric_ambiguity" => false,
            "evidence_sufficient" => true
          }
        end,
        "group_observations" => observations
      }
    end
  end

  def level_payload(value)
    {
      "assessment_state" => "Scored",
      "value" => value,
      "rationale" => "Explicit fixture level.",
      "evidence" => [{ "locator" => "PAGE: 1", "note" => "Explicit level guidance." }],
      "rubric_ambiguity" => false,
      "evidence_sufficient" => true
    }
  end

  class FakeProvider < AFScoring::Providers::Base
    attr_reader :model, :calls

    def initialize(score: 3, confidence: 85)
      @model = "fake-model"
      @score = score
      @confidence = confidence
      @calls = []
    end

    def score(group_name:, prompt:, schema:)
      @calls << { group_name: group_name, prompt: prompt, schema: schema }
      payload = TestSupport.scored_group_payload(group_name, score: @score, confidence: @confidence)
      AFScoring::Providers::ProviderResult.new(parsed: payload, raw: { "fixture" => true, "group" => group_name })
    end
  end
end
