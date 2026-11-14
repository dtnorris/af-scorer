# frozen_string_literal: true

require "open3"
require "rexml/document"

module AFScoring
  # Minimal read-only XLSX reader for small AdventureFinder source workbooks.
  # It intentionally supports only the cell types needed by the canonical
  # catalog/reference sheets. This avoids a spreadsheet dependency in the CLI.
  class XlsxReader
    NS = { "m" => "http://schemas.openxmlformats.org/spreadsheetml/2006/main" }.freeze
    REL_NS = { "r" => "http://schemas.openxmlformats.org/package/2006/relationships" }.freeze

    def initialize(path)
      @path = File.expand_path(path)
      raise CatalogError, "Workbook does not exist: #{@path}" unless File.file?(@path)
      raise CatalogError, "unzip command is required to read XLSX files" unless system("command -v unzip >/dev/null 2>&1")
    end

    def sheet_names
      workbook = xml("xl/workbook.xml")
      REXML::XPath.match(workbook, "//m:sheets/m:sheet", NS).map { |el| el.attributes["name"] }
    end

    def rows(sheet_name: nil)
      target = sheet_name || sheet_names.first
      sheet_path = sheet_xml_path(target)
      shared = shared_strings
      sheet = xml(sheet_path)
      output = []

      REXML::XPath.match(sheet, "//m:sheetData/m:row", NS).each do |row_el|
        row = []
        REXML::XPath.match(row_el, "m:c", NS).each do |cell|
          ref = cell.attributes["r"]
          col_index = column_index(ref)
          row[col_index] = cell_value(cell, shared)
        end
        output << row
      end
      output
    end

    private

    def read_zip(path)
      stdout, stderr, status = Open3.capture3("unzip", "-p", @path, path)
      raise CatalogError, "Cannot read #{path} from #{@path}: #{stderr.strip}" unless status.success?
      stdout
    end

    def xml(path)
      REXML::Document.new(read_zip(path))
    rescue REXML::ParseException => e
      raise CatalogError, "Invalid XLSX XML #{path}: #{e.message}"
    end

    def shared_strings
      content = read_zip("xl/sharedStrings.xml")
      doc = REXML::Document.new(content)
      REXML::XPath.match(doc, "//m:si", NS).map do |si|
        REXML::XPath.match(si, ".//m:t", NS).map(&:text).join
      end
    rescue CatalogError
      []
    end

    def sheet_xml_path(sheet_name)
      workbook = xml("xl/workbook.xml")
      sheet = REXML::XPath.match(workbook, "//m:sheets/m:sheet", NS).find { |el| el.attributes["name"] == sheet_name }
      raise CatalogError, "Worksheet not found: #{sheet_name}" unless sheet

      relationship_id = sheet.attributes["r:id"] || sheet.attributes["id"]
      rels = REXML::Document.new(read_zip("xl/_rels/workbook.xml.rels"))
      rel = REXML::XPath.match(rels, "//r:Relationship", REL_NS).find { |el| el.attributes["Id"] == relationship_id }
      raise CatalogError, "Worksheet relationship not found for #{sheet_name}" unless rel

      target = rel.attributes["Target"]
      target.start_with?("/") ? target.sub(%r{^/}, "") : File.join("xl", target).gsub(%r{/+}, "/")
    end

    def column_index(ref)
      letters = ref.to_s[/[A-Z]+/]
      return 0 unless letters
      letters.chars.reduce(0) { |sum, ch| sum * 26 + ch.ord - 64 } - 1
    end

    def cell_value(cell, shared)
      type = cell.attributes["t"]
      if type == "inlineStr"
        return REXML::XPath.match(cell, "m:is/m:t", NS).map(&:text).join
      end

      value = REXML::XPath.match(cell, "m:v", NS).first&.text
      return nil if value.nil?

      case type
      when "s"
        shared.fetch(value.to_i, value)
      when "b"
        value == "1"
      when "str"
        value
      else
        numeric(value)
      end
    end

    def numeric(value)
      return value.to_i if value.match?(/\A-?\d+\z/)
      return value.to_f if value.match?(/\A-?\d+\.\d+\z/)
      value
    end
  end
end
