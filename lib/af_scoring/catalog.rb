# frozen_string_literal: true

module AFScoring
  Adventure = Struct.new(
    :id, :title, :page_count, :source_book, :publisher, :start_page, :end_page,
    keyword_init: true
  )

  class Catalog
    REQUIRED_HEADERS = [
      "Adventure ID", "Adventure Title", "Source Book", "Book Publisher", "Start Page", "End Page"
    ].freeze

    HEADER_ALIASES = {
      "ADV - ID" => "Adventure ID"
    }.freeze

    def initialize(path, sheet_name: "Adventure Catalog")
      rows = XlsxReader.new(path).rows(sheet_name: sheet_name)
      raise CatalogError, "Catalog workbook is empty" if rows.empty?
      headers = rows.shift.map { |v| canonical_header(v) }
      missing = REQUIRED_HEADERS - headers
      raise CatalogError, "Catalog missing required columns: #{missing.join(', ')}" unless missing.empty?

      @records = {}
      rows.each do |row|
        values = headers.zip(row).to_h
        id = values["Adventure ID"].to_s.strip
        next if id.empty?
        @records[id] = Adventure.new(
          id: id,
          title: values["Adventure Title"].to_s,
          page_count: values["Page Count"],
          source_book: values["Source Book"].to_s,
          publisher: values["Book Publisher"].to_s,
          start_page: integer_or_nil(values["Start Page"]),
          end_page: integer_or_nil(values["End Page"])
        )
      end
    end

    def fetch(adventure_id)
      @records.fetch(adventure_id) { raise AdventureNotFound, "Adventure ID not found in AMC: #{adventure_id}" }
    end

    def ids
      @records.keys.sort
    end

    private

    def canonical_header(value)
      header = value.to_s.strip
      HEADER_ALIASES.fetch(header, header)
    end

    def integer_or_nil(value)
      return nil if value.nil? || value.to_s.strip.empty?
      Integer(value)
    rescue ArgumentError, TypeError
      nil
    end
  end
end
