# frozen_string_literal: true

require_relative "test_helper"

class PortableDefaultsTest < Minitest::Test
  # Public defaults refuse ambient siblings; explicit roots and overrides remain portable.
  def test_explicit_roots_follow_configuration_and_preserve_overrides
    Dir.mktmpdir("component layout") do |dir|
      ["flat", "adventure-finder-components"].each do |layout|
        repo = File.join(dir, layout, "af-cli-scoring-utility")
        FileUtils.mkdir_p(File.join(repo, "config"))
        FileUtils.cp(File.expand_path("../config/default.yml", __dir__), File.join(repo, "config/default.yml"))
        keys = AFScoring::Config::ENV_MAP.keys
        saved = keys.to_h { |key| [key, ENV[key]] }
        begin
          keys.each { |key| ENV.delete(key) }
          error = assert_raises(AFScoring::ConfigurationError) { AFScoring::Config.new(project_root: repo) }
          assert_includes error.message, "Select paths.xlsx_root explicitly"
          ENV["AF_XLSX_ROOT"] = File.join(dir, "selected catalog")
          ENV["AF_SPEC_ROOT"] = File.join(dir, "selected method")
          ENV["AF_SOURCE_ROOT"] = File.join(dir, "selected source")
          config = AFScoring::Config.new(project_root: repo)
          assert_equal ENV["AF_XLSX_ROOT"], config.dig("paths", "xlsx_root")
          assert_equal ENV["AF_SPEC_ROOT"], config.dig("paths", "specification_root")
          assert_equal AFScoring::SelectedMethod::PUBLIC_IDENTITY, config.dig("method", "identity")
          assert_equal ENV["AF_SOURCE_ROOT"], config.dig("paths", "source_root")
          assert_equal "catalog_head", config.dig("files", "catalog_role")
          ENV["AF_XLSX_ROOT"] = File.join(dir, "explicit authority")
          overridden = AFScoring::Config.new(project_root: repo)
          assert_equal ENV["AF_XLSX_ROOT"], overridden.dig("paths", "xlsx_root")
          final = AFScoring::Config.new(project_root: repo, overrides: {"paths" => {"xlsx_root" => File.join(dir, "explicit config")}})
          assert_equal File.join(dir, "explicit config"), final.dig("paths", "xlsx_root")
        ensure
          saved.each { |key, value| ENV[key] = value }
        end
      end
    end
  end
end
