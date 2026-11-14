# frozen_string_literal: true
require_relative "test_helper"

class SourceTest < Minitest::Test
  def test_explicit_resolution_and_page_extraction
    Dir.mktmpdir do |dir|
      source = File.join(dir, "Fixture_Book.md")
      File.write(source, "header\n<!-- PAGE: 1 -->\none\n<!-- PAGE: 2 -->\ntwo\n<!-- PAGE: 3 -->\nthree\n")
      registry = File.join(dir, "source_registry.yml")
      File.write(
        registry,
        {
          "schema_version" => AFScoring::SourceResolver::REGISTRY_SCHEMA_VERSION,
          "sources" => { "Fixture Book" => { "file" => "Fixture_Book.md" } }
        }.to_yaml
      )
      adv = AFScoring::Adventure.new(id: "ADV-0001", title: "Fixture", source_book: "Fixture Book", start_page: 1, end_page: 2)
      resolution = AFScoring::SourceResolver.new(source_root: dir, registry_path: registry).resolve(adv)
      assert_equal "explicit_mapping", resolution.strategy
      extraction = AFScoring::SourceDocument.new(resolution.path).extract(start_page: 1, end_page: 2)
      assert_includes extraction.text, "one"
      assert_includes extraction.text, "two"
      refute_includes extraction.text, "three"
      assert_equal "canonical_page_slice", extraction.scope
    end
  end

  def test_missing_boundary_fails_by_default
    Dir.mktmpdir do |dir|
      source = File.join(dir, "source.md")
      File.write(source, "<!-- PDF Page 1 -->\none\n")
      assert_raises(AFScoring::SourceBoundaryError) do
        AFScoring::SourceDocument.new(source).extract(start_page: 1, end_page: 2)
      end
    end
  end
end

class SourceUnicodeNormalizationTest < Minitest::Test
  def test_normalized_resolution_handles_diacritics
    Dir.mktmpdir do |dir|
      source = File.join(dir, "Forgotten_Realms_Adventures_in_Faerun_LLM_Edition.md")
      File.write(source, "<!-- PAGE: 1 -->\ntext\n")
      registry = File.join(dir, "source_registry.yml")
      File.write(
        registry,
        {
          "schema_version" => AFScoring::SourceResolver::REGISTRY_SCHEMA_VERSION,
          "sources" => {}
        }.to_yaml
      )
      adv = AFScoring::Adventure.new(id: "ADV-0001", title: "Fixture", source_book: "Forgotten Realms: Adventures in Faerûn")
      resolution = AFScoring::SourceResolver.new(source_root: dir, registry_path: registry).resolve(adv)
      assert_equal source, resolution.path
      assert_equal "normalized_filename", resolution.strategy
    end
  end
end
