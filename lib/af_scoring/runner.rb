# frozen_string_literal: true

require "securerandom"
require "time"
require "digest"
require "json"

module AFScoring
  RunOutcome = Struct.new(
    :package, :assessment_csv, :regression_csv, :comparisons, :raw_paths,
    keyword_init: true
  )
  PreflightTarget = Struct.new(
    :group_name, :label, :artifact_name, :dimensions, :prompt, :schema,
    :prompt_sha256, :schema_sha256,
    keyword_init: true
  )
  PreflightOutcome = Struct.new(
    :adventure, :source_file, :source_scope, :source_warnings, :output_root,
    :targets, :run_metadata,
    keyword_init: true
  )
  PreparedAdventure = Struct.new(
    :adventure, :extraction, :levels_context, :eligibility,
    keyword_init: true
  )

  # Prepare and score selected catalog sources under the configured operative definitions.
  # Reference inputs are required only for explicit regression/access, before scoring.
  class Runner
    PREPARED_SOURCE_CONTRACT_VERSION = "afsu-prepared-source/v0.2"

    attr_reader :config

    # Initialize governing definitions, source resolution and result validation from config.
    # An optional provider/logger/progress is reused; governing/config errors propagate.
    def initialize(config:, provider: nil, logger: nil, progress: nil)
      @config = config
      @logger = logger || ->(message) { puts message }
      @progress = progress
      @selected_method = SelectedMethod.new(@config)
      @selected_method.verify!
      verify_governing_files!
      @catalog_path = @config.catalog_path
      @source_root = File.expand_path(@config.dig("paths", "source_root"))
      @source_registry_path = @config.source_registry_path
      @catalog_binding = file_binding(@catalog_path)
      @registry_binding = file_binding(@source_registry_path)
      @catalog = Catalog.new(@catalog_path)
      @afao = AFAO.new(@config.afao_path)
      @assessment_spec = AssessmentSpec.new(@config.assessment_spec_path)
      verify_selected_method!
      @source_resolver = SourceResolver.new(
        source_root: @source_root,
        registry_path: @source_registry_path
      )
      @normalizer = Normalizer.new
      @validator = Validator.new
      @review_rules = ReviewRules.new(
        low_confidence_threshold: @config.dig("review", "low_confidence_threshold"),
        moderate_confidence_ceiling: @config.dig("review", "moderate_confidence_ceiling")
      )
      @writer = CsvWriter.new(@config.dig("paths", "output_root"))
      @provider = provider
    end

    # Load and cache the selected regression enumerator on explicit access.
    # Returns a ReferenceSet; missing configuration/files raise ConfigurationError,
    # while invalid workbook content retains CatalogError/RegressionReferenceError.
    def reference_set
      return @reference_set if @reference_set

      workbook_path = @config.regression_workbook_path
      raise ConfigurationError, "Missing regression workbook: #{workbook_path}" unless File.file?(workbook_path)

      @reference_set = Regression::ReferenceSet.new(
        workbook_path: workbook_path
      )
    end

    # Resolve/freeze one target without inference. Returns a v0.2 source payload;
    # configuration, eligibility and source errors propagate before any provider use.
    def prepare_source(adventure_id)
      prepared = prepare_adventure(adventure_id, include_levels_context: true)
      prepared_source_payload(prepared)
    end

    # Serialize one validated preparation, including eligibility independent of permissions.
    # Returns a v0.2 payload; callers must not treat observed hashes as historical authority.
    def prepared_source_payload(prepared)
      extraction = prepared.extraction

      {
        "contract_version" => PREPARED_SOURCE_CONTRACT_VERSION,
        "adventure" => adventure_snapshot(prepared.adventure),
        "catalog" => file_binding(@catalog_path),
        "source_registry" => file_binding(@source_registry_path),
        "source_policy" => source_policy_snapshot(prepared.adventure.id),
        "source_file" => file_binding(extraction.source_file),
        "target_eligibility" => prepared.eligibility.snapshot,
        "extraction" => {
          "text" => extraction.text,
          "source_file" => extraction.source_file,
          "scope" => extraction.scope,
          "start_page" => extraction.start_page,
          "end_page" => extraction.end_page,
          "warnings" => extraction.warnings.dup
        },
        "levels_context" => prepared.levels_context
      }
    end
    private :prepared_source_payload

    # Render exact blind requests, optionally validating a frozen v0.2 payload.
    # Returns PreflightOutcome; stale source/method/eligibility bindings refuse.
    def preflight(adventure_id, prepared_source: nil)
      verify_selected_method!
      prepared = if prepared_source
                   prepared_adventure_from_payload(adventure_id, prepared_source)
                 else
                   prepare_adventure(adventure_id)
                 end
      adventure = prepared.adventure
      extraction = prepared.extraction

      targets = scoring_targets.map do |target|
        prompt, schema = build_target_inputs(
          target,
          adventure: adventure,
          extraction: extraction,
          levels_context: prepared.levels_context
        )
        PreflightTarget.new(
          group_name: target.group_name,
          label: target.label,
          artifact_name: target.artifact_name,
          dimensions: target.dimensions,
          prompt: prompt,
          schema: schema,
          prompt_sha256: Digest::SHA256.hexdigest("#{prompt.instructions}\0#{prompt.input}"),
          schema_sha256: Digest::SHA256.hexdigest(JSON.generate(schema))
        )
      end

      PreflightOutcome.new(
        adventure: adventure,
        source_file: extraction.source_file,
        source_scope: extraction.scope,
        source_warnings: extraction.warnings.dup,
        output_root: validate_output_root!,
        targets: targets,
        run_metadata: run_metadata(run_id: "preflight", adventure: adventure, extraction: extraction)
      )
    end

    # Produce a validated/reviewed proposal for the selected Adventure ID.
    # Regression validates its workbook before provider construction/inference, then
    # compares AFAO expectations after the blind proposal. Returns RunOutcome;
    # configuration, reference, source, specification, provider and validation errors propagate.
    def score(adventure_id, regression: false)
      reference_set if regression
      prepared = prepare_adventure(adventure_id)
      prepared.eligibility.verify_regression! if regression
      adventure = prepared.adventure
      extraction = prepared.extraction
      levels_context = prepared.levels_context
      @provider ||= build_provider
      run_id = build_run_id

      metrics = []
      observations = []
      raw_paths = []
      if run_metadata_required?
        raw_paths << @writer.write_run_metadata(
          adventure_id: adventure_id,
          run_id: run_id,
          metadata: run_metadata(run_id: run_id, adventure: adventure, extraction: extraction)
        )
        log("[#{adventure_id}] Combat prompt profile: combat_guardrail_v0.7.1") if combat_scoring?
      end
      scoring_targets.each do |target|
        prompt, schema = build_target_inputs(
          target,
          adventure: adventure,
          extraction: extraction,
          levels_context: levels_context
        )
        raw_paths << @writer.write_request(
          adventure_id: adventure_id,
          run_id: run_id,
          group_name: target.artifact_name,
          request: @provider.request_artifact(
            group_name: target.group_name,
            prompt: prompt,
            schema: schema
          ),
          prompt_sha256: Digest::SHA256.hexdigest("#{prompt.instructions}\0#{prompt.input}"),
          schema_sha256: Digest::SHA256.hexdigest(JSON.generate(schema))
        )
        progress_session = build_progress_session(
          adventure: adventure,
          extraction: extraction,
          group_name: target.label,
          dimensions: target.dimensions
        )
        log("[#{adventure_id}] Scoring #{target.label}") unless progress_session
        raw_persisted = false
        score_call = -> do
          @provider.score(
            group_name: target.group_name,
            prompt: prompt,
            schema: schema
          ) do |raw|
            unless raw_persisted
              raw_paths << @writer.write_raw(
                adventure_id: adventure_id,
                run_id: run_id,
                group_name: target.artifact_name,
                raw: raw
              )
              raw_persisted = true
            end
          end
        end
        result = progress_session ? progress_session.waiting(&score_call) : score_call.call
        unless raw_persisted
          raw_paths << @writer.write_raw(
            adventure_id: adventure_id,
            run_id: run_id,
            group_name: target.artifact_name,
            raw: result.raw
          )
        end
        progress_session&.normalizing
        normalized = @normalizer.normalize(
          target.group_name,
          result.parsed,
          expected_dimensions: target.dimensions
        )
        metrics.concat(normalized.metrics)
        observations << normalized.observations
        progress_session&.complete(normalized.metrics.length)
      end

      package = AssessmentPackage.new(
        run_id: run_id,
        adventure: adventure,
        afao_version: @afao.version,
        assessment_spec_version: @assessment_spec.version,
        provider: @provider.respond_to?(:provider_name) ? @provider.provider_name : @config.dig("llm", "provider"),
        model: @provider.respond_to?(:model) ? @provider.model : @config.dig("llm", "model"),
        source_file: extraction.source_file,
        source_scope: extraction.scope,
        source_warnings: extraction.warnings,
        metrics: metrics,
        status: "PROPOSED",
        review_disposition: nil,
        package_review_flags: []
      )

      if @progress
        @progress.validating(adventure_id: adventure_id, metric_count: metrics.length)
      else
        log("[#{adventure_id}] Running deterministic validation")
      end
      @validator.validate!(package, expected_metrics: expected_metric_names)
      @review_rules.apply!(package, group_observations: observations)

      comparisons = []
      regression_csv = nil
      if regression
        # Deliberately derive expected results only after the blind proposal exists.
        expected = reference_set.expected_for(adventure_id, afao: @afao, eligibility: prepared.eligibility)
        expected = expected.select { |metric, _| expected_metric_names.include?(metric) } if focused_scoring?
        if expected.empty?
          package.package_review_flags << "REVIEW:NO_REGRESSION_EXPECTATIONS"
          package.review_disposition = "REVIEW_REQUIRED"
          log("[#{adventure_id}] No explicit AFAO calibration expectations found for regression")
        else
          comparisons = Regression::Comparator.new.compare(package, expected)
          disagreements = comparisons.reject(&:exact_match)
          unless disagreements.empty?
            package.package_review_flags << "REVIEW:REGRESSION_DISAGREEMENT"
            package.package_review_flags.uniq!
            package.review_disposition = "REVIEW_REQUIRED"
          end
          regression_csv = @writer.write_regression(package, comparisons)
          log("[#{adventure_id}] Regression: #{comparisons.count(&:exact_match)}/#{comparisons.length} exact")
        end
      end

      assessment_csv = @writer.write_package(package)
      log("[#{adventure_id}] Validation passed; review disposition: #{package.review_disposition}")
      log("[#{adventure_id}] CSV: #{assessment_csv}")
      log("[#{adventure_id}] Regression CSV: #{regression_csv}") if regression_csv

      RunOutcome.new(
        package: package,
        assessment_csv: assessment_csv,
        regression_csv: regression_csv,
        comparisons: comparisons,
        raw_paths: raw_paths
      )
    end

    private

    # Resolve a live catalog target and validate explicit contextual eligibility before
    # extraction. Returns PreparedAdventure; owner/configuration errors propagate.
    def prepare_adventure(adventure_id, include_levels_context: nil)
      verify_selected_method!
      verify_file_binding!(@catalog_binding, @catalog_path, "loaded catalog")
      verify_file_binding!(@registry_binding, @source_registry_path, "loaded source registry")
      adventure = @catalog.fetch(adventure_id)
      log("[#{adventure_id}] Resolving source for #{adventure.title}")
      resolution = @source_resolver.resolve(adventure)
      eligibility = TargetEligibility.new(
        selection: @config.dig("target_bindings"),
        context: {
          "adventure" => adventure_snapshot(adventure),
          "catalog" => file_binding(@catalog_path),
          "source_registry" => file_binding(@source_registry_path),
          "source_file" => file_binding(resolution.path),
          "page_marker_offset" => resolution.page_marker_offset || 0,
          "source_policy" => source_policy_snapshot(adventure.id)
        },
        afao: @afao
      )
      eligibility.verify_source_exception!
      @prompt_builder = PromptBuilder.new(afao: @afao.for_target(eligibility), assessment_spec: @assessment_spec)
      @target_eligibility = eligibility
      source_document = SourceDocument.new(resolution.path)
      extraction = source_document.extract(
        start_page: adventure.start_page,
        end_page: adventure.end_page,
        page_marker_offset: resolution.page_marker_offset || 0,
        allow_full_source_fallback: !!@config.dig("source", "allow_full_source_fallback"),
        allow_inward_boundary_clamp: source_boundary_clamp_allowed?(adventure.id),
        max_inward_boundary_clamp_gap: source_boundary_clamp_max_gap(adventure.id)
      )
      extraction.warnings.concat(resolution.warnings)

      include_levels_context = scoring_targets.any? { |target| target.dimensions.include?("Levels") } if include_levels_context.nil?
      levels_context = if include_levels_context
                         source_document.levels_context_before(
                           start_page: adventure.start_page,
                           page_marker_offset: resolution.page_marker_offset || 0
                         )
                       else
                         ""
                       end

      PreparedAdventure.new(
        adventure: adventure,
        extraction: extraction,
        levels_context: levels_context,
        eligibility: eligibility
      )
    end

    # Revalidate a v0.2 payload against real current resolution and extraction.
    # Returns PreparedAdventure; stale, altered or cross-library payloads refuse with
    # SourceResolutionError (underlying owner/configuration errors retain their types).
    def prepared_adventure_from_payload(adventure_id, payload)
      unless payload.is_a?(Hash) && payload["contract_version"] == PREPARED_SOURCE_CONTRACT_VERSION
        raise SourceResolutionError,
              "prepared source contract must be #{PREPARED_SOURCE_CONTRACT_VERSION.inspect}"
      end

      current = prepare_adventure(adventure_id, include_levels_context: true)
      unless payload == prepared_source_payload(current)
        raise SourceResolutionError, "prepared source content/context does not match current resolved preparation for #{adventure_id}"
      end
      current
    end

    def adventure_snapshot(adventure)
      {
        "id" => adventure.id,
        "title" => adventure.title,
        "page_count" => adventure.page_count,
        "source_book" => adventure.source_book,
        "publisher" => adventure.publisher,
        "start_page" => adventure.start_page,
        "end_page" => adventure.end_page
      }
    end

    def source_policy_snapshot(adventure_id)
      {
        "source_root" => @source_root,
        "source_registry_path" => @source_registry_path,
        "allow_full_source_fallback" => !!@config.dig("source", "allow_full_source_fallback"),
        "allow_inward_boundary_clamp" => source_boundary_clamp_allowed?(adventure_id),
        "max_inward_boundary_clamp_gap" => source_boundary_clamp_max_gap(adventure_id)
      }
    end

    def file_binding(path)
      expanded = File.expand_path(path)
      {
        "path" => expanded,
        "sha256" => Digest::SHA256.file(expanded).hexdigest
      }
    end

    def verify_file_binding!(binding, expected_path, label)
      unless binding.is_a?(Hash)
        raise SourceResolutionError, "prepared source #{label} binding is missing"
      end

      actual_path = File.expand_path(binding["path"].to_s)
      expected = File.expand_path(expected_path.to_s)
      unless actual_path == expected && File.file?(actual_path)
        raise SourceResolutionError, "prepared source #{label} path changed: expected #{expected}, got #{actual_path}"
      end

      expected_sha = binding["sha256"].to_s.downcase
      actual_sha = Digest::SHA256.file(actual_path).hexdigest
      unless expected_sha.match?(/\A[0-9a-f]{64}\z/) && actual_sha == expected_sha
        raise SourceResolutionError, "prepared source #{label} SHA-256 changed"
      end
    end

    def source_boundary_clamp_allowed?(adventure_id)
      approved = Array(@config.dig("source", "allow_inward_boundary_clamp_adventure_ids"))
        .map(&:to_s)
      approved.include?(adventure_id.to_s)
    end

    def source_boundary_clamp_max_gap(adventure_id)
      configured = @config.dig(
        "source",
        "inward_boundary_clamp_max_gap_by_adventure",
        adventure_id.to_s
      )
      return SourceDocument::MAX_BOUNDARY_MARKER_GAP if configured.nil?

      gap = Integer(configured)
      raise ConfigurationError, "Inward boundary clamp max gap for #{adventure_id} must be at least 1" if gap < 1

      gap
    rescue ArgumentError, TypeError
      raise ConfigurationError,
            "Invalid inward boundary clamp max gap for #{adventure_id}: #{configured.inspect}"
    end

    # Build one prompt/schema with a contextual AFAO view, preserving selected loaders.
    # Returns [Prompt, schema]; specification/eligibility errors propagate before use.
    def build_target_inputs(target, adventure:, extraction:, levels_context:)
      prompt = @prompt_builder.build(
        group_name: target.group_name,
        dimensions: target.dimensions,
        adventure: adventure,
        source_extraction: extraction,
        levels_context: target.dimensions.include?("Levels") ? levels_context : nil
      )
      schema = SchemaBuilder.for_group(target.group_name, dimensions: target.dimensions)
      [prompt, schema]
    end

    def validate_output_root!
      output_root = File.expand_path(@config.dig("paths", "output_root"))
      probe = output_root
      until File.exist?(probe) || File.dirname(probe) == probe
        probe = File.dirname(probe)
      end

      unless File.directory?(probe) && File.writable?(probe)
        raise ConfigurationError,
              "Output path is not writable: #{output_root} (nearest existing ancestor: #{probe})"
      end

      output_root
    end

    # Check the catalog and operative definition files required by every mode.
    # Returns the checked mapping; missing files raise ConfigurationError.
    def verify_governing_files!
      {
        "AMC" => @config.catalog_path,
        "AFAO" => @config.afao_path,
        "Assessment Specification" => @config.assessment_spec_path
      }.each do |label, path|
        raise ConfigurationError, "Missing #{label}: #{path}" unless File.file?(path)
      end
    end

    # Recheck public files and the already loaded parser inputs before preparing a request.
    # Returns nil for historical selections; public integrity failures raise SpecificationError.
    def verify_selected_method!
      @selected_method.verify!(afao: @afao, assessment_spec: @assessment_spec)
    end

    def build_progress_session(adventure:, extraction:, group_name:, dimensions:)
      return unless @progress

      @progress.start(
        adventure_id: adventure.id,
        group_name: group_name,
        dimensions: dimensions,
        source_file: extraction.source_file,
        start_page: adventure.start_page,
        end_page: adventure.end_page,
        provider: provider_name,
        model: provider_model
      )
    end

    def provider_name
      @provider.respond_to?(:provider_name) ? @provider.provider_name : @config.dig("llm", "provider")
    end

    def provider_model
      @provider.respond_to?(:model) ? @provider.model : @config.dig("llm", "model")
    end

    def run_metadata_required?
      @selected_method&.public? || combat_scoring? || !experimental_group.nil?
    end

    def combat_scoring?
      scoring_targets.any? { |target| target.dimensions.include?("Combat Emphasis") }
    end

    def experimental_group
      @config.dig("experimental", "group")
    end

    def selected_dimension
      @config.dig("scoring", "dimension")
    end

    def scoring_targets
      group = experimental_group
      dimension = selected_dimension

      if group && dimension
        raise SpecificationError, "--dimension cannot be combined with --experimental-group"
      end

      if dimension
        target = ScoringTarget.for_dimension(dimension)
        return [target]
      end

      return scoring_targets_for_group(group) if group

      DimensionGroups::GROUPS.keys.flat_map { |group_name| scoring_targets_for_group(group_name) }
    end

    def scoring_targets_for_group(group_name)
      return [
        ScoringTarget.for_dimension("# of Sessions"),
        ScoringTarget.for_dimension("Levels")
      ] if group_name == "sessions_levels"

      [ScoringTarget.for_group(group_name)]
    end

    def scoring_groups
      scoring_targets.map(&:group_name).uniq
    end

    def focused_scoring?
      !selected_dimension.nil? || !experimental_group.nil?
    end

    def expected_metric_names
      scoring_targets.flat_map(&:metric_names)
    end

    def run_metadata(run_id:, adventure:, extraction:)
      metadata = {
        "run_id" => run_id,
        "adventure_id" => adventure.id,
        "prompt_profile" => combat_scoring? ? "combat_guardrail_v0.7.1" : "experimental_group",
        "experimental" => !experimental_group.nil?,
        "experimental_group" => experimental_group,
        "selected_dimension" => selected_dimension,
        "groups_scored" => scoring_groups,
        "guardrail_sha256" => combat_scoring? ? Digest::SHA256.hexdigest(PromptBuilder::COMBAT_GUARDRAIL_V0_7_1) : nil,
        "afao_version" => @afao.version,
        "assessment_spec_version" => @assessment_spec.version,
        "provider" => provider_name,
        "model" => provider_model,
        "reasoning_effort" => @config.dig("llm", "reasoning_effort"),
        "source_file" => extraction.source_file,
        "source_scope" => extraction.scope
      }
      metadata["method"] = @selected_method.binding if @selected_method&.public?
      metadata["target_eligibility"] = @target_eligibility.snapshot if @target_eligibility
      metadata
    end

    def build_provider
      case @config.dig("llm", "provider")
      when "openai"
        Providers::OpenAIProvider.new(
          model: @config.dig("llm", "model"),
          reasoning_effort: @config.dig("llm", "reasoning_effort")
        )
      when "ollama"
        Providers::OllamaProvider.new(
          model: @config.dig("llm", "model"),
          reasoning_effort: @config.dig("llm", "reasoning_effort"),
          base_url: @config.dig("llm", "ollama_base_url"),
          max_tokens: @config.dig("llm", "max_tokens")
        )
      when "gpt_oss_qualification"
        GptOssQualificationOllamaProvider.new(
          base_url: @config.dig("llm", "ollama_base_url")
        )
      else
        raise ConfigurationError, "Unsupported LLM provider: #{@config.dig('llm', 'provider')}"
      end
    end

    def build_run_id
      "#{Time.now.utc.strftime('%Y%m%dT%H%M%SZ')}_#{SecureRandom.hex(4)}"
    end

    def log(message)
      @logger.call(message)
    end
  end
end
