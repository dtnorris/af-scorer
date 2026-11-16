# frozen_string_literal: true

require "minitest/autorun"
require "open3"
require "tmpdir"
require "fileutils"
require_relative "../lib/af_scoring/errors"
require_relative "../lib/af_scoring/source_markdown_owner"

# A selected owner is mandatory even when valid ambient code is available.
class SourceOwnerTest < Minitest::Test
  # Exercise both real source adapters in fresh Ruby processes, refuse invalid
  # selection and restore the selected owner without modifying mechanical input.
  def test_explicit_owner_refusal_and_restoration
    owner = AFScoring::SourceMarkdownOwner.load!(error_class: AFScoring::ConfigurationError)
    Dir.mktmpdir("scorer-source-owner-") do |root|
      markdown = File.join(root, "source.md")
      registry = File.join(root, "source_registry.yml")
      text = "<!-- Printed Page 1 -->\nα\n<!-- Printed Page 2 -->\nΩ\n"
      File.binwrite(markdown, text)
      File.write(registry, "schema_version: adventurefinder-source-registry/v0.1\nsources:\n  Mechanical Source:\n    file: source.md\n")
      invalid = File.join(root, "invalid-owner")
      FileUtils.mkdir_p(File.join(invalid, "lib"))
      File.write(File.join(invalid, "lib", "af_source_md.rb"), "# unsupported owner\n")
      program = <<~'RUBY'
        require "af_scoring/errors"
        require "af_scoring/source_resolver"
        require "af_scoring/source_document"
        request = Struct.new(:source_book, :start_page, :end_page).new("Mechanical Source", 1, 2)
        resolved = AFScoring::SourceResolver.new(source_root: ARGV.fetch(0), registry_path: ARGV.fetch(1)).resolve(request)
        extracted = AFScoring::SourceDocument.new(resolved.path).extract(start_page: 1, end_page: 2)
        raise "Wrong public shape" unless extracted.is_a?(AFScoring::SourceDocument::Extraction)
        STDOUT.write(extracted.text)
      RUBY
      command = [RbConfig.ruby, "-I", File.expand_path("../lib", __dir__), "-e", program, root, registry]
      before = [File.binread(registry), File.binread(markdown)]
      ["", File.join(root, "missing-owner"), invalid].each do |selection|
        stdout, stderr, status = Open3.capture3({"AF_SOURCE_MD_ROOT" => selection, "RUBYLIB" => File.join(owner::ROOT, "lib")}, *command)
        refute status.success?
        assert_empty stdout
        assert_match(/source Markdown owner|AF_SOURCE_MD_ROOT/, stderr)
        assert_equal before, [File.binread(registry), File.binread(markdown)]
      end
      stdout, stderr, status = Open3.capture3({"AF_SOURCE_MD_ROOT" => owner::ROOT}, *command)
      assert status.success?, stderr
      assert_equal text, stdout
    end
  end
end
