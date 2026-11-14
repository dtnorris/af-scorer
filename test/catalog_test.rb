# frozen_string_literal: true

require_relative "test_helper"

class CatalogTest < Minitest::Test
  def test_accepts_current_amc_adv_id_header
    Dir.mktmpdir do |dir|
      path = File.join(dir, "catalog.xlsx")
      TestSupport.build_xlsx(
        path,
        sheet_name: "Adventure Catalog",
        rows: [
          [
            "ADV - ID", "Adventure Title", "Page Count", "Source Book",
            "Book Publisher", "Start Page", "End Page", "Combat Emphasis"
          ],
          [
            "ADV-0033", "Against the Giants", 46, "Tales from the Yawning Portal",
            "Wizards of the Coast", 165, 210, 5
          ]
        ]
      )

      adventure = AFScoring::Catalog.new(path).fetch("ADV-0033")

      assert_equal "ADV-0033", adventure.id
      assert_equal "Against the Giants", adventure.title
      assert_equal 46, adventure.page_count
      assert_equal "Tales from the Yawning Portal", adventure.source_book
      assert_equal "Wizards of the Coast", adventure.publisher
      assert_equal 165, adventure.start_page
      assert_equal 210, adventure.end_page
    end
  end

  def test_preserves_legacy_adventure_id_header_compatibility
    Dir.mktmpdir do |dir|
      path = File.join(dir, "catalog.xlsx")
      TestSupport.build_xlsx(
        path,
        sheet_name: "Adventure Catalog",
        rows: [
          ["Adventure ID", "Adventure Title", "Source Book", "Book Publisher", "Start Page", "End Page"],
          ["ADV-0001", "Fixture Adventure", "Fixture Book", "Fixture Publisher", 1, 2]
        ]
      )

      assert_equal "ADV-0001", AFScoring::Catalog.new(path).fetch("ADV-0001").id
    end
  end
end
