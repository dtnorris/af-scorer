# frozen_string_literal: true

require "json"
require "digest"
require "af_scoring"

# Observe this offline CLI process without replacing any owner validator. The
# explicit forbidden roots include private/development inputs supplied by the
# caller. This Ruby observer is not an OS sandbox or a native-extension tracer.
module OfflineObservation
  ROOT = File.realpath(ENV.fetch("AF_SMOKE_CODE_ROOT"))
  FORBIDDEN = JSON.parse(ENV.fetch("AF_SMOKE_FORBIDDEN_ROOTS", "[]"))
  READS = []
  COUNTERS = { "provider_constructions" => 0, "provider_executions" => 0 }

  # Reject a forbidden path before Ruby File access and retain its observed name.
  # Other file operations retain their original return values and exceptions.
  def self.check(path)
    return unless path.is_a?(String)
    expanded = File.expand_path(path)
    READS << expanded
    if FORBIDDEN.any? { |root| expanded == root || expanded.start_with?(root + "/") }
      raise SecurityError, "Forbidden offline input: #{expanded}"
    end
  end
end

%i[read binread readlines foreach open new sysopen file? exist? readable? stat lstat directory? realpath readlink].each do |name|
  original = File.method(name)
  File.define_singleton_method(name) do |path, *arguments, **keywords, &block|
    OfflineObservation.check(path)
    original.call(path, *arguments, **keywords, &block)
  end
end

[AFScoring::Providers::OpenAIProvider, AFScoring::Providers::OllamaProvider, AFScoring::GptOssQualificationOllamaProvider].each do |provider|
  provider.singleton_class.prepend(Module.new do
    # Count and refuse unexpected provider construction in prepare/preflight.
    def new(*)
      OfflineObservation::COUNTERS["provider_constructions"] += 1
      raise "Offline CLI constructed a provider"
    end
  end)
  provider.prepend(Module.new do
    # Count and refuse external execution; no network/provider call is allowed.
    def score(*)
      OfflineObservation::COUNTERS["provider_executions"] += 1
      raise "Offline CLI executed a provider"
    end
  end)
end

at_exit do
  features = $LOADED_FEATURES.select { |path| path.include?("/af_scoring") }
  unexpected = features.reject { |path| path.start_with?(OfflineObservation::ROOT + "/lib/") }
  receipt = {
    "scope" => "Ruby File operations after observer load; loaded scorer feature identities; audited unzip subprocess",
    "counters" => OfflineObservation::COUNTERS, "reads" => OfflineObservation::READS.uniq.sort,
    "loaded" => features.to_h { |path| [path, Digest::SHA256.file(path).hexdigest] }, "unexpected_loaded" => unexpected
  }
  File.write(ENV.fetch("AF_SMOKE_RECEIPT"), JSON.pretty_generate(receipt) + "\n")
  abort "Unexpected scorer load path" unless unexpected.empty?
end
