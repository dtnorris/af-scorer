# frozen_string_literal: true

require "digest"

module AFScoring
  # Validate operator-selected historical eligibility against resolved, frozen inputs.
  # An ADV label selects a declaration; equality of the complete context grants it.
  class TargetEligibility
    CONTRACT_VERSION = "afsu-target-eligibility/v0.1"

    attr_reader :context, :calibration

    # Compare one resolved context with Config's explicit target_bindings selection.
    # Returns an eligibility decision; malformed, ambiguous or mismatched declarations
    # raise ConfigurationError. No workbook membership or expected scores are read.
    def initialize(selection:, context:, afao:)
      validate_context!(context)
      @context = freeze_context(Marshal.load(Marshal.dump(context)))
      @afao_sha256 = Digest::SHA256.hexdigest(afao.text)
      @calibration = "none"
      @declared = !selection.nil?
      return unless @declared

      unless selection.is_a?(Hash) && selection.keys.sort == %w[contract_version targets] &&
             selection["contract_version"] == CONTRACT_VERSION && selection["targets"].is_a?(Array)
        raise ConfigurationError, "Invalid target_bindings; expected #{CONTRACT_VERSION} with targets"
      end
      entries = selection.fetch("targets")
      entries.each do |entry|
        unless entry.is_a?(Hash) && (entry.keys - %w[context calibration afao_sha256]).empty? &&
               entry["context"].is_a?(Hash) && entry["context"]["adventure"].is_a?(Hash) &&
               entry.dig("context", "adventure", "id").is_a?(String) &&
               %w[none historical].include?(entry["calibration"])
          raise ConfigurationError, "Invalid target eligibility declaration"
        end
      end
      matches = entries.select { |entry| entry.dig("context", "adventure", "id") == context.dig("adventure", "id") }
      raise ConfigurationError, "Ambiguous target eligibility declaration" if matches.length > 1
      @entry = matches.first
      return unless @entry

      unless @entry["context"] == context
        raise ConfigurationError, "Target eligibility context does not match resolved library/source/content"
      end
      @calibration = @entry.fetch("calibration").dup.freeze
      if (historical? || @entry.key?("afao_sha256")) && @entry["afao_sha256"] != @afao_sha256
        raise ConfigurationError, "Historical calibration AFAO SHA-256 does not match selected method"
      end
    end

    # Return whether this context explicitly selects historical AFAO comparison.
    # This is operator intent, not source adjudication or model qualification.
    def historical?
      @calibration == "historical"
    end

    # Refuse an ID-selected source exception without an exact context declaration.
    # Returns nil for disabled or bound exceptions; raises ConfigurationError otherwise.
    def verify_source_exception!
      if context.dig("source_policy", "allow_inward_boundary_clamp") && !@entry
        raise ConfigurationError, "Source boundary exception requires an explicit matching target context"
      end
      nil
    end

    # Validate an explicit regression request before provider use. Empty declarations
    # intentionally select no historical comparisons; absence is an error, not legacy.
    # Returns self or raises ConfigurationError for missing selection.
    def verify_regression!
      raise ConfigurationError, "Regression requires explicit target_bindings (an empty targets list selects no comparisons)" unless @declared
      self
    end

    # Check consumers' target and current method bytes against this resolved decision.
    # Returns self; mismatched target or loaded/live file changes raise ConfigurationError.
    def verify!(adventure_id:, afao:)
      verify_target!(adventure_id: adventure_id, afao: afao)
      %w[catalog source_registry source_file].each do |key|
        binding = context.fetch(key)
        unless File.file?(binding.fetch("path")) && Digest::SHA256.file(binding.fetch("path")).hexdigest == binding.fetch("sha256")
          raise ConfigurationError, "Target eligibility #{key} content changed"
        end
      end
      unless File.file?(afao.path) && Digest::SHA256.file(afao.path).hexdigest == @afao_sha256
        raise ConfigurationError, "Target eligibility AFAO content changed"
      end
      self
    end

    # Check a rubric consumer against this immutable decision without rereading source
    # files for each dimension. Preparation/reference boundaries verify live bytes.
    # Returns self; a wrong target or changed loaded method raises ConfigurationError.
    def verify_target!(adventure_id:, afao:, target_title: nil)
      unless context.dig("adventure", "id") == adventure_id && Digest::SHA256.hexdigest(afao.text) == @afao_sha256
        raise ConfigurationError, "Target eligibility target or AFAO context changed"
      end
      if target_title && context.dig("adventure", "title") != target_title
        raise ConfigurationError, "Target eligibility title context changed"
      end
      self
    end

    # Return the versioned, score-free decision for prepared-source/run provenance.
    # Contains exact input bindings and intentional absence, never expected values.
    def snapshot
      { "contract_version" => CONTRACT_VERSION, "context" => Marshal.load(Marshal.dump(context)),
        "calibration" => calibration, "afao_sha256" => @afao_sha256,
        "declared" => @declared }
    end

    private

    # Require the complete observed context shape at the direct API boundary.
    # Returns nil; missing/malformed bindings raise ConfigurationError before use.
    def validate_context!(context)
      valid = context.is_a?(Hash) && context.keys.sort == %w[adventure catalog page_marker_offset source_file source_policy source_registry] &&
        context["adventure"].is_a?(Hash) && context["adventure"].keys.sort == %w[end_page id page_count publisher source_book start_page title] &&
        context.dig("adventure", "id").is_a?(String) && context.dig("adventure", "title").is_a?(String) &&
        context["page_marker_offset"].is_a?(Integer) && context["source_policy"].is_a?(Hash) &&
        context["source_policy"].keys.sort == %w[allow_full_source_fallback allow_inward_boundary_clamp max_inward_boundary_clamp_gap source_registry_path source_root]
      valid &&= %w[catalog source_registry source_file].all? do |name|
        binding = context[name]
        binding.is_a?(Hash) && binding.keys.sort == %w[path sha256] && binding["path"].is_a?(String) &&
          binding["sha256"].is_a?(String) && binding["sha256"].match?(/\A[0-9a-f]{64}\z/)
      end
      raise ConfigurationError, "Missing or malformed resolved target context" unless valid
      nil
    end

    # Freeze a copied JSON-shaped context recursively; return that value without I/O.
    # Inputs come from resolved owner bindings; no caller-owned objects are frozen.
    def freeze_context(value)
      case value
      when Hash
        value.each { |key, child| freeze_context(key); freeze_context(child) }
      when Array
        value.each { |child| freeze_context(child) }
      end
      value.freeze
    end
  end
end
