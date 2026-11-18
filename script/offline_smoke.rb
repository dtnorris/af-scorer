#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "open3"
require "rbconfig"
require "digest"
require "fileutils"
require_relative "../test/test_helper"

# Exercise the real packaged executable using numeric source mechanics. Arguments
# are the exact public specification root, an absent private evidence root, and
# optional forbidden roots. Errors preserve raw receipts and exit nonzero. No
# validator is stubbed; transport/provider execution is prohibited by the observer.
module OfflineSmoke
  module_function

  # Invoke one fresh CLI process in a cleared environment, retaining binary stdout,
  # stderr and raw status. Return status; process/IO exceptions propagate.
  def invoke(root, evidence, spec, forbidden, label, arguments)
    receipt = File.join(evidence, "#{label}.observation.json")
    environment = {
      "PATH" => ENV.fetch("PATH"), "HOME" => File.join(evidence, "home"),
      "TMPDIR" => File.join(evidence, "tmp"), "LANG" => "en_US.UTF-8",
      "BUNDLE_GEMFILE" => File.join(root, "Gemfile"), "BUNDLE_FROZEN" => "true",
      "BUNDLE_APP_CONFIG" => File.join(evidence, "bundle-config"),
      "AF_SMOKE_CODE_ROOT" => root, "AF_SMOKE_FORBIDDEN_ROOTS" => JSON.generate(forbidden),
      "AF_SMOKE_RECEIPT" => receipt,
      "AF_XLSX_ROOT" => evidence, "AF_CATALOG_WORKBOOK" => "catalog.xlsx",
      "AF_SOURCE_ROOT" => evidence, "AF_SPEC_ROOT" => spec,
      "AF_OUTPUT_DIR" => File.join(evidence, "output")
    }
    environment["AF_SOURCE_MD_ROOT"] = ENV.fetch("AF_SOURCE_MD_ROOT") if ENV.key?("AF_SOURCE_MD_ROOT")
    command = [RbConfig.ruby, "-rbundler/setup", "-I", File.join(root, "lib"),
               "-r", File.join(root, "script/observe_cli.rb"), File.join(root, "bin/af-score"), *arguments]
    stdout, stderr, status = Open3.capture3(environment, *command, chdir: evidence, unsetenv_others: true, binmode: true)
    File.binwrite(File.join(evidence, "#{label}.stdout"), stdout)
    File.binwrite(File.join(evidence, "#{label}.stderr"), stderr)
    File.write(File.join(evidence, "#{label}.command.json"), JSON.pretty_generate({ "argv" => command, "environment" => environment, "status" => status.exitstatus, "signal" => status.termsig }) + "\n")
    observation = JSON.parse(File.read(receipt))
    raise "Provider used: #{label}" unless observation.fetch("counters").values.all?(&:zero?)
    raise "Unexpected loaded code" unless observation.fetch("unexpected_loaded").empty?
    status.exitstatus
  end

  # Create explicit numeric sources/catalog and run success/removal/restoration.
  # Return a metadata summary; failure leaves evidence intact for private review.
  def run(spec, evidence, forbidden)
    root = File.expand_path("..", __dir__)
    raise "Evidence directory must be absent" if File.exist?(evidence)
    FileUtils.mkdir_p([evidence, File.join(evidence, "home"), File.join(evidence, "tmp")])
    binary = "\x00\xFF\x0A".b
    stdout, stderr, status = Open3.capture3(RbConfig.ruby, "-e", 'STDOUT.binmode; STDERR.binmode; STDOUT.write("\\x00\\xFF\\x0A"); STDERR.write("error"); exit 7', binmode: true)
    raise "Subprocess observer changed bytes/status" unless stdout == binary && stderr == "error" && status.exitstatus == 7
    File.binwrite(File.join(evidence, "observer-binary.stdout"), stdout)
    File.binwrite(File.join(evidence, "observer-binary.stderr"), stderr)
    method_root = File.join(evidence, "method")
    FileUtils.mkdir_p(method_root)
    ["documents.json", *AFScoring::SelectedMethod::PUBLIC_FILES.values.map(&:first)].each do |name|
      FileUtils.cp(File.join(spec, name), method_root)
    end
    TestSupport.build_xlsx(File.join(evidence, "catalog.xlsx"), sheet_name: "Adventure Catalog", rows: [
      ["Adventure ID", "Adventure Title", "Page Count", "Source Book", "Book Publisher", "Start Page", "End Page"],
      ["ADV-0001", "Mechanical Fixture", 2, "Mechanical Source", "Fixture", 1, 2]
    ])
    File.write(File.join(evidence, "source.md"), "<!-- PAGE: 1 -->\n1\n<!-- PAGE: 2 -->\n2\n<!-- PAGE: 3 -->\n3\n")
    File.write(File.join(evidence, "source_registry.yml"), { "schema_version" => AFScoring::SourceResolver::REGISTRY_SCHEMA_VERSION,
      "sources" => { "Mechanical Source" => { "file" => "source.md" } } }.to_yaml)
    prepared = File.join(evidence, "prepared.json")
    render = File.join(evidence, "preflight.json")
    prepare_arguments = ["--prepare-source", prepared, "ADV-0001"]
    replay_arguments = ["--preflight", "--prepared-source", prepared, "--render-preflight", render, "ADV-0001"]
    raise "Prepare failed; inspect prepare.stderr" unless invoke(root, evidence, method_root, forbidden, "prepare", prepare_arguments) == 0
    payload = JSON.parse(File.read(prepared))
    raise "Wrong prepared contract" unless payload.fetch("contract_version") == "afsu-prepared-source/v0.2"
    %w[catalog source_registry source_file].each do |key|
      binding = payload.fetch(key)
      raise "Wrong source binding: #{key}" unless Digest::SHA256.file(binding.fetch("path")).hexdigest == binding.fetch("sha256")
    end
    raise "Replay failed; inspect replay.stderr" unless invoke(root, evidence, method_root, forbidden, "replay", replay_arguments) == 0
    original_render = File.binread(render)
    rendered = JSON.parse(original_render)
    raise "Wrong method" unless rendered.dig("run_metadata", "method", "identity") == AFScoring::SelectedMethod::PUBLIC_IDENTITY
    raise "Incomplete target set" unless rendered.fetch("targets").length == 8
    provider = AFScoring::Providers::OpenAIProvider.new(model: "gpt-5.6-terra", reasoning_effort: "high", client: Object.new)
    requests = rendered.fetch("targets").map do |target|
      prompt = AFScoring::PromptBuilder::Prompt.new(instructions: target.fetch("prompt").fetch("instructions"), input: target.fetch("prompt").fetch("input"))
      provider.request_artifact(group_name: target.fetch("group_name"), prompt: prompt, schema: target.fetch("schema"))
    end
    File.write(File.join(evidence, "requests.json"), JSON.pretty_generate(requests) + "\n")
    inventory_path = File.join(method_root, "documents.json")
    inventory = File.binread(inventory_path)
    negative_root = File.join(evidence, "method-negative")
    FileUtils.cp_r(method_root, negative_root)
    negative_inventory = File.join(negative_root, "documents.json")
    begin
      File.unlink(negative_inventory)
      raise "Missing method accepted prepare" unless invoke(root, evidence, negative_root, forbidden, "missing-prepare", prepare_arguments) == 1
      raise "Missing method accepted replay" unless invoke(root, evidence, negative_root, forbidden, "missing-replay", replay_arguments) == 1
      %w[missing-prepare missing-replay].each do |label|
        raise "Wrong refusal" unless File.read(File.join(evidence, "#{label}.stderr")).include?("Missing public method file:")
      end
    ensure
      File.binwrite(negative_inventory, inventory)
    end
    raise "Restored prepare failed" unless invoke(root, evidence, negative_root, forbidden, "restored-prepare", prepare_arguments) == 0
    raise "Restored replay failed" unless invoke(root, evidence, negative_root, forbidden, "restored-replay", replay_arguments) == 0
    raise "Restoration changed render" unless File.binread(render) == original_render
    summary = { "result" => "PASS", "prepared_contract" => payload.fetch("contract_version"),
      "method" => rendered.dig("run_metadata", "method"), "source_policy" => payload.fetch("source_policy"),
      "prompt_hashes" => rendered.fetch("targets").to_h { |target| [target.fetch("label"), target.fetch("prompt_sha256")] },
      "schema_hashes" => rendered.fetch("targets").to_h { |target| [target.fetch("label"), target.fetch("schema_sha256")] },
      "requests_sha256" => Digest::SHA256.file(File.join(evidence, "requests.json")).hexdigest,
      "limit" => "Ruby observation, not kernel confinement; request rendering uses an inert external SDK client, no score call" }
    File.write(File.join(evidence, "summary.json"), JSON.pretty_generate(summary) + "\n")
    puts JSON.generate(summary)
  end
end

if $PROGRAM_NAME == __FILE__
  raise "Usage: offline_smoke.rb PINNED_SPEC_ROOT ABSENT_PRIVATE_EVIDENCE_ROOT [FORBIDDEN_ROOT ...]" unless ARGV.length >= 2
  spec, evidence, *forbidden = ARGV.map { |path| File.expand_path(path) }
  OfflineSmoke.run(spec, evidence, forbidden)
end
