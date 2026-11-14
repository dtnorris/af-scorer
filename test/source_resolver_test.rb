# frozen_string_literal: true

require_relative "test_helper"

class SourceResolverTest < Minitest::Test
  def adventure(source_book:, start_page: nil, end_page: nil)
    AFScoring::Adventure.new(id: "ADV-0001", title: "Fixture Adventure", source_book: source_book,
                             start_page: start_page, end_page: end_page)
  end

  def with_resolver(mapping, files: ["first.md", "second.md"])
    Dir.mktmpdir("source-resolver") do |dir|
      files.each { |file| File.write(File.join(dir, file), "fixture") }
      registry_path = File.join(dir, "source_registry.yml")
      File.write(
        registry_path,
        YAML.dump(
          "schema_version" => AFScoring::SourceResolver::REGISTRY_SCHEMA_VERSION,
          "sources" => mapping
        )
      )
      yield AFScoring::SourceResolver.new(source_root: dir, registry_path: registry_path), dir
    end
  end

  def test_missing_registry_fails_closed
    Dir.mktmpdir("source-resolver") do |dir|
      error = assert_raises(AFScoring::ConfigurationError) do
        AFScoring::SourceResolver.new(
          source_root: dir,
          registry_path: File.join(dir, "missing-source_registry.yml")
        )
      end
      assert_includes error.message, "Missing source registry"
    end
  end

  def test_unsupported_registry_schema_fails_closed
    Dir.mktmpdir("source-resolver") do |dir|
      registry_path = File.join(dir, "source_registry.yml")
      File.write(
        registry_path,
        YAML.dump("schema_version" => "adventurefinder-source-registry/v999", "sources" => {})
      )
      error = assert_raises(AFScoring::ConfigurationError) do
        AFScoring::SourceResolver.new(source_root: dir, registry_path: registry_path)
      end
      assert_includes error.message, "Unsupported source registry schema"
    end
  end

  def segmented_mapping(extra = {})
    {
      "Fixture Book" => {
        "segments" => [
          { "start_page" => 22, "end_page" => 102, "file" => "first.md" },
          { "start_page" => 104, "end_page" => 175, "file" => "second.md" }
        ]
      }.merge(extra)
    }
  end

  def test_structured_single_file_mapping_defaults_to_zero_page_marker_offset
    with_resolver({ "Fixture Book" => { "file" => "first.md" } }) do |resolver, dir|
      resolution = resolver.resolve(adventure(source_book: "Fixture Book"))
      assert_equal File.join(dir, "first.md"), resolution.path
      assert_equal "explicit_mapping", resolution.strategy
      assert_equal 0, resolution.page_marker_offset
    end
  end

  def test_legacy_scalar_mapping_is_rejected_by_registry_contract
    with_resolver({ "Fixture Book" => "first.md" }) do |resolver, _dir|
      error = assert_raises(AFScoring::ConfigurationError) do
        resolver.resolve(adventure(source_book: "Fixture Book"))
      end
      assert_includes error.message, "expected mapping with file or segments"
    end
  end

  def test_structured_single_file_mapping_still_supports_explicit_offset
    mapping = { "Shire Adventures" => { "file" => "first.md", "page_marker_offset" => "+3" } }
    with_resolver(mapping) do |resolver, dir|
      resolution = resolver.resolve(adventure(source_book: "Shire Adventures"))
      assert_equal File.join(dir, "first.md"), resolution.path
      assert_equal "explicit_mapping", resolution.strategy
      assert_equal 3, resolution.page_marker_offset
    end
  end

  def test_structured_mapping_rejects_unsigned_page_marker_offset
    mapping = { "Fixture Book" => { "file" => "first.md", "page_marker_offset" => "3" } }
    with_resolver(mapping) do |resolver, _dir|
      error = assert_raises(AFScoring::ConfigurationError) { resolver.resolve(adventure(source_book: "Fixture Book")) }
      assert_includes error.message, 'use an explicitly signed value such as "+3" or "-3"'
    end
  end

  def test_segmented_mapping_selects_first_and_second_files_by_full_range_containment
    with_resolver(segmented_mapping) do |resolver, dir|
      first = resolver.resolve(adventure(source_book: "Fixture Book", start_page: 22, end_page: 28))
      second = resolver.resolve(adventure(source_book: "Fixture Book", start_page: 104, end_page: 109))
      assert_equal File.join(dir, "first.md"), first.path
      assert_equal File.join(dir, "second.md"), second.path
      assert_equal "explicit_segment_mapping", first.strategy
      assert_equal "explicit_segment_mapping", second.strategy
      assert_equal 0, first.page_marker_offset
      assert_equal 0, second.page_marker_offset
    end
  end

  def test_exact_segment_boundary_and_nested_range_resolve
    with_resolver(segmented_mapping) do |resolver, dir|
      exact = resolver.resolve(adventure(source_book: "Fixture Book", start_page: 22, end_page: 102))
      nested = resolver.resolve(adventure(source_book: "Fixture Book", start_page: 40, end_page: 50))
      assert_equal File.join(dir, "first.md"), exact.path
      assert_equal File.join(dir, "first.md"), nested.path
    end
  end

  def test_segment_level_page_marker_offset_is_supported
    mapping = segmented_mapping
    mapping["Fixture Book"]["segments"].first["page_marker_offset"] = "+2"
    with_resolver(mapping) do |resolver, _dir|
      resolution = resolver.resolve(adventure(source_book: "Fixture Book", start_page: 30, end_page: 40))
      assert_equal 2, resolution.page_marker_offset
    end
  end

  def test_cross_segment_range_fails_instead_of_selecting_by_start_page
    with_resolver(segmented_mapping) do |resolver, _dir|
      error = assert_raises(AFScoring::SourceResolutionError) do
        resolver.resolve(adventure(source_book: "Fixture Book", start_page: 90, end_page: 110))
      end
      assert_includes error.message, "No configured source segment"
    end
  end

  def test_uncovered_range_fails_without_filename_fallback
    with_resolver(segmented_mapping, files: ["first.md", "second.md", "Fixture_Book_LLM_Edition.md"]) do |resolver, _dir|
      error = assert_raises(AFScoring::SourceResolutionError) do
        resolver.resolve(adventure(source_book: "Fixture Book", start_page: 103, end_page: 103))
      end
      assert_includes error.message, "No configured source segment"
    end
  end

  def test_missing_adventure_start_page_fails
    with_resolver(segmented_mapping) do |resolver, _dir|
      assert_raises(AFScoring::SourceResolutionError) do
        resolver.resolve(adventure(source_book: "Fixture Book", end_page: 28))
      end
    end
  end

  def test_missing_adventure_end_page_fails
    with_resolver(segmented_mapping) do |resolver, _dir|
      assert_raises(AFScoring::SourceResolutionError) do
        resolver.resolve(adventure(source_book: "Fixture Book", start_page: 22))
      end
    end
  end

  def test_invalid_adventure_range_fails
    with_resolver(segmented_mapping) do |resolver, _dir|
      error = assert_raises(AFScoring::SourceResolutionError) do
        resolver.resolve(adventure(source_book: "Fixture Book", start_page: 30, end_page: 29))
      end
      assert_includes error.message, "Invalid adventure page range"
    end
  end

  def test_overlapping_segments_that_both_contain_range_are_ambiguous
    mapping = segmented_mapping
    mapping["Fixture Book"]["segments"] = [
      { "start_page" => 1, "end_page" => 100, "file" => "first.md" },
      { "start_page" => 50, "end_page" => 150, "file" => "second.md" }
    ]
    with_resolver(mapping) do |resolver, _dir|
      assert_raises(AFScoring::AmbiguousSourceError) do
        resolver.resolve(adventure(source_book: "Fixture Book", start_page: 60, end_page: 70))
      end
    end
  end

  def test_missing_any_segment_file_fails_closed
    with_resolver(segmented_mapping, files: ["first.md"]) do |resolver, _dir|
      error = assert_raises(AFScoring::SourceResolutionError) do
        resolver.resolve(adventure(source_book: "Fixture Book", start_page: 30, end_page: 40))
      end
      assert_includes error.message, "second.md"
    end
  end

  def test_empty_segments_fail
    with_resolver({ "Fixture Book" => { "segments" => [] } }) do |resolver, _dir|
      assert_raises(AFScoring::ConfigurationError) do
        resolver.resolve(adventure(source_book: "Fixture Book", start_page: 30, end_page: 40))
      end
    end
  end

  def test_invalid_segment_boundaries_fail
    [["22", 102], [22, "102"], [0, 20], [30, 20]].each do |start_page, end_page|
      mapping = { "Fixture Book" => { "segments" => [
        { "start_page" => start_page, "end_page" => end_page, "file" => "first.md" }
      ] } }
      with_resolver(mapping) do |resolver, _dir|
        assert_raises(AFScoring::ConfigurationError) do
          resolver.resolve(adventure(source_book: "Fixture Book", start_page: 30, end_page: 40))
        end
      end
    end
  end

  def test_segments_cannot_be_mixed_with_single_file_mapping
    with_resolver(segmented_mapping("file" => "first.md")) do |resolver, _dir|
      error = assert_raises(AFScoring::ConfigurationError) do
        resolver.resolve(adventure(source_book: "Fixture Book", start_page: 30, end_page: 40))
      end
      assert_includes error.message, "segments cannot be combined with file"
    end
  end

  def test_normalized_filename_resolution_is_unchanged_without_explicit_mapping
    with_resolver({}, files: ["Ghosts_of_Saltmarsh_LLM_Edition.md"]) do |resolver, dir|
      resolution = resolver.resolve(adventure(source_book: "Ghosts of Saltmarsh"))
      assert_equal File.join(dir, "Ghosts_of_Saltmarsh_LLM_Edition.md"), resolution.path
      assert_equal "normalized_filename", resolution.strategy
      assert_equal ["SOURCE_RESOLVED_BY_FILENAME"], resolution.warnings
      assert_equal 0, resolution.page_marker_offset
    end
  end

  def test_tyranny_registry_mapping_routes_combined_hardcover_ranges
    mapping = {
      "Tyranny of Dragons" => {
        "segments" => [
          { "start_page" => 22, "end_page" => 102, "file" => "Hoard_of_the_Dragon_Queen_LLM_Edition.md" },
          { "start_page" => 104, "end_page" => 175, "file" => "The_Rise_of_Tiamat_LLM_Edition.md" }
        ]
      }
    }
    files = %w[Hoard_of_the_Dragon_Queen_LLM_Edition.md The_Rise_of_Tiamat_LLM_Edition.md]
    with_resolver(mapping, files: files) do |resolver, dir|
      hoard = resolver.resolve(adventure(source_book: "Tyranny of Dragons", start_page: 22, end_page: 28))
      rise = resolver.resolve(adventure(source_book: "Tyranny of Dragons", start_page: 104, end_page: 109))
      assert_equal File.join(dir, files.first), hoard.path
      assert_equal File.join(dir, files.last), rise.path
      assert_equal 0, hoard.page_marker_offset
      assert_equal 0, rise.page_marker_offset
    end
  end
end
