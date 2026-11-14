# frozen_string_literal: true

require_relative "test_helper"
require_relative "../script/source_package"

# Keep package safety controls independent of any real catalog or private checkout.
class SourcePackageTest < Minitest::Test
  # Create only two small content-free members; all outputs remain in scratch.
  def setup
    @scratch = Dir.mktmpdir("source-package")
    @root = File.join(@scratch, "source")
    FileUtils.mkdir_p(@root)
    File.write(File.join(@root, "Manifest.txt"), "Manifest.txt\nmechanical.bin\n")
    File.binwrite(File.join(@root, "mechanical.bin"), "\x00\xFF\n".b)
    # Package fixtures need exact safe modes regardless of the caller's umask.
    File.chmod(0o644, File.join(@root, "Manifest.txt"), File.join(@root, "mechanical.bin"))
    @archive = File.join(@scratch, "source.tar")
    @inventory = File.join(@scratch, "inventory.json")
  end

  # Remove only this test's scratch; filesystem exceptions propagate.
  def teardown
    FileUtils.remove_entry(@scratch)
  end

  # Binary bytes and executable/regular modes survive exact independent unpacking.
  def test_roundtrip_and_reproducible_archive
    File.chmod(0o755, File.join(@root, "mechanical.bin"))
    SourcePackage.build(@root, @archive, @inventory)
    destination = File.join(@scratch, "unpacked")
    assert_equal 2, SourcePackage.unpack(@archive, @inventory, destination)
    assert_equal "\x00\xFF\n".b, File.binread(File.join(destination, "mechanical.bin"))
    assert_equal 0o755, File.stat(File.join(destination, "mechanical.bin")).mode & 0o777
    second_archive = File.join(@scratch, "second.tar")
    SourcePackage.build(@root, second_archive, File.join(@scratch, "second.json"))
    assert_equal File.binread(@archive), File.binread(second_archive)
    assert_raises(ArgumentError) { SourcePackage.unpack(@archive, @inventory, destination) }
  end

  # Missing selections, linked members and unsafe modes refuse before output creation.
  def test_missing_linked_and_unsafe_source_refuse
    path = File.join(@root, "mechanical.bin")
    File.unlink(path)
    assert_raises(Errno::ENOENT) { SourcePackage.build(@root, @archive, @inventory) }
    refute File.exist?(@archive)
    File.symlink(@inventory, path)
    assert_raises(ArgumentError) { SourcePackage.build(@root, @archive, @inventory) }
    File.unlink(path)
    File.write(path, "1")
    File.chmod(0o666, path)
    assert_raises(ArgumentError) { SourcePackage.build(@root, @archive, @inventory) }
  end

  # Refuse traversal/private state even if a selection explicitly requests it.
  def test_unsafe_allowlist_refuses
    ["../outside", "/absolute", "path//empty", ".git/config", ".env", ".env.local", ".aws/credentials", "path/../outside"].each do |path|
      assert_raises(ArgumentError) { SourcePackage.member_path(path) }
    end
  end

  # An unlisted archive member refuses after its new outer digest is acknowledged;
  # checking the archive digest alone cannot establish the selected member set.
  def test_injected_member_refuses_even_with_matching_archive_digest
    SourcePackage.build(@root, @archive, @inventory)
    File.open(@archive, "wb") do |output|
      Gem::Package::TarWriter.new(output) do |tar|
        %w[Manifest.txt mechanical.bin].each do |path|
          bytes = File.binread(File.join(@root, path))
          tar.add_file_simple(path, 0o644, bytes.bytesize) { |entry| entry.write(bytes) }
        end
        tar.add_file_simple("private-unlisted.txt", 0o644, 1) { |entry| entry.write("0") }
      end
    end
    inventory = JSON.parse(File.read(@inventory))
    inventory["archive_sha256"] = Digest::SHA256.file(@archive).hexdigest
    File.write(@inventory, JSON.generate(inventory))
    error = assert_raises(ArgumentError) { SourcePackage.unpack(@archive, @inventory, File.join(@scratch, "unpacked")) }
    assert_includes error.message, "Member inventory mismatch"
    refute File.exist?(File.join(@scratch, "unpacked"))
  end

  # Tar-reader termination cannot hide bytes beyond the reviewed member set,
  # even when a caller acknowledges the modified archive's outer digest.
  def test_bytes_after_archive_terminator_refuse
    SourcePackage.build(@root, @archive, @inventory)
    File.open(@archive, "ab") { |output| output.write("unlisted-private-tail") }
    inventory = JSON.parse(File.read(@inventory))
    inventory["archive_sha256"] = Digest::SHA256.file(@archive).hexdigest
    File.write(@inventory, JSON.generate(inventory))
    error = assert_raises(ArgumentError) { SourcePackage.unpack(@archive, @inventory, File.join(@scratch, "unpacked")) }
    assert_includes error.message, "Unexpected bytes after archive terminator"
    refute File.exist?(File.join(@scratch, "unpacked"))
  end
end
