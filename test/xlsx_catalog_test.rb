# frozen_string_literal: true
require_relative "test_helper"

class XlsxCatalogTest < Minitest::Test
  def test_catalog_lookup_from_xlsx
    Dir.mktmpdir do |dir|
      path = File.join(dir, "catalog.xlsx")
      TestSupport.build_xlsx(path, sheet_name: "Adventure Catalog", rows: [
        ["Adventure ID", "Adventure Title", "Page Count", "Source Book", "Book Publisher", "Start Page", "End Page"],
        ["ADV-0001", "Fixture Adventure", 2, "Fixture Book", "Fixture Publisher", 1, 2]
      ])
      catalog = AFScoring::Catalog.new(path)
      adv = catalog.fetch("ADV-0001")
      assert_equal "Fixture Adventure", adv.title
      assert_equal 1, adv.start_page
      assert_equal 2, adv.end_page
      assert_raises(AFScoring::AdventureNotFound) { catalog.fetch("ADV-9999") }
    end
  end
end
