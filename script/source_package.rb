#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "json"
require "pathname"
require "rubygems/package"

# Build or independently inspect an exact regular-file source distribution.
# Inputs are an explicit manifest, archive and private inventory; invalid paths,
# links, modes, missing files or changed bytes raise ArgumentError/IO errors.
module SourcePackage
  module_function

  # Return a safe relative member name; reject traversal and excluded local state.
  def member_path(value)
    parts = value.split("/", -1)
    if value.empty? || Pathname.new(value).absolute? || parts.any? { |part| ["", ".", "..", ".git", ".env", ".bundle", ".aws"].include?(part) || part.start_with?(".env.") } || value.include?("\\")
      raise ArgumentError, "Unsafe package member: #{value.inspect}"
    end
    value
  end

  # Return the reviewed unique allowlist; malformed/unsorted selections refuse.
  def selection(root)
    paths = File.readlines(File.join(root, "Manifest.txt"), chomp: true)
    paths.each { |path| member_path(path) }
    raise ArgumentError, "Manifest must be sorted, unique and include itself" unless paths == paths.sort.uniq && paths.include?("Manifest.txt")
    paths
  end

  # Inspect one regular file without following any selected path's symlinks.
  # Return bytes/mode; missing or unsafe components raise before archive creation.
  def source_file(root, path)
    cursor = root
    path.split("/").each do |part|
      cursor = File.join(cursor, part)
      raise ArgumentError, "Linked package path: #{path}" if File.lstat(cursor).symlink?
    end
    status = File.lstat(cursor)
    raise ArgumentError, "Nonregular package member: #{path}" unless status.file?
    mode = status.mode & 0o7777
    raise ArgumentError, "Unsafe package mode: #{path}" unless [0o644, 0o755].include?(mode)
    [File.binread(cursor), mode]
  end

  # Return the public path/mode/content identity of a member; never opens files.
  def identity(path, bytes, mode)
    { "path" => path, "mode" => format("%04o", mode), "bytes" => bytes.bytesize, "sha256" => Digest::SHA256.hexdigest(bytes) }
  end

  # Write an exclusive deterministic tar and sidecar inventory outside the source.
  # Returns inventory; pre-existing outputs or invalid selections refuse.
  def build(root, archive, inventory)
    root = File.realpath(root)
    raise ArgumentError, "Archive and inventory must differ" if File.expand_path(archive) == File.expand_path(inventory)
    [archive, inventory].each do |path|
      expanded = File.expand_path(path)
      raise ArgumentError, "Outputs must be absent and outside source" if File.exist?(expanded) || File.symlink?(expanded) || expanded.start_with?(root + "/")
    end
    members = selection(root).map { |path| [path, *source_file(root, path)] }
    ENV["SOURCE_DATE_EPOCH"] = "0"
    File.open(archive, File::WRONLY | File::CREAT | File::EXCL, 0o644) do |output|
      Gem::Package::TarWriter.new(output) do |tar|
        members.each { |path, bytes, mode| tar.add_file_simple(path, mode, bytes.bytesize) { |entry| entry.write(bytes) } }
      end
    end
    result = { "format" => "af-scorer-source/v0.1", "archive_sha256" => Digest::SHA256.file(archive).hexdigest,
               "members" => members.map { |path, bytes, mode| identity(path, bytes, mode) } }
    File.open(inventory, File::WRONLY | File::CREAT | File::EXCL, 0o644) { |output| output.write(JSON.pretty_generate(result) + "\n") }
    result
  end

  # Verify archive identities and exact membership before unpacking into an absent root.
  # Returns member count; changed/unlisted/duplicate/nonregular members refuse.
  def unpack(archive, inventory, destination)
    expected = JSON.parse(File.read(inventory))
    raise ArgumentError, "Unknown inventory" unless expected.fetch("format") == "af-scorer-source/v0.1"
    raise ArgumentError, "Archive digest mismatch" unless Digest::SHA256.file(archive).hexdigest == expected.fetch("archive_sha256")
    members = []
    File.open(archive, "rb") do |input|
      Gem::Package::TarReader.new(input) do |tar|
        tar.each do |entry|
          path = member_path(entry.full_name)
          raise ArgumentError, "Nonregular archive member: #{path}" unless entry.file? && entry.header.typeflag == "0"
          members << [path, entry.read, entry.header.mode]
        end
      end
      # TarReader stops at the first zero header. Require exactly the writer's
      # second zero block so ignored trailing data cannot carry unlisted bytes.
      raise ArgumentError, "Unexpected bytes after archive terminator" unless input.read == "\0" * 512
    end
    observed = members.map { |path, bytes, mode| identity(path, bytes, mode) }
    raise ArgumentError, "Member inventory mismatch" unless observed == expected.fetch("members")
    paths = members.map(&:first)
    manifest = members.find { |path, _bytes, _mode| path == "Manifest.txt" }
    raise ArgumentError, "Archive allowlist mismatch" unless manifest && manifest[1].lines(chomp: true) == paths && paths == paths.sort.uniq
    raise ArgumentError, "Unsafe member modes" unless members.all? { |_path, _bytes, mode| [0o644, 0o755].include?(mode) }
    raise ArgumentError, "Destination must be absent" if File.exist?(destination) || File.symlink?(destination)
    require "fileutils"
    FileUtils.mkdir_p(destination)
    members.each do |path, bytes, mode|
      target = File.join(destination, path)
      FileUtils.mkdir_p(File.dirname(target))
      File.open(target, File::WRONLY | File::CREAT | File::EXCL, mode) { |output| output.write(bytes) }
      File.chmod(mode, target)
      raise ArgumentError, "Extracted identity mismatch" unless identity(path, *source_file(destination, path)) == observed.find { |member| member["path"] == path }
    end
    members.length
  end
end

if $PROGRAM_NAME == __FILE__
  begin
    command, *arguments = ARGV
    case command
    when "build"
      raise ArgumentError, "build ROOT ARCHIVE INVENTORY" unless arguments.length == 3
      puts JSON.generate(SourcePackage.build(*arguments))
    when "unpack"
      raise ArgumentError, "unpack ARCHIVE INVENTORY ABSENT_DIRECTORY" unless arguments.length == 3
      puts "Verified #{SourcePackage.unpack(*arguments)} regular files"
    else
      raise ArgumentError, "Use build or unpack"
    end
  rescue StandardError => error
    warn "Package refused: #{error.message}"
    exit 1
  end
end
