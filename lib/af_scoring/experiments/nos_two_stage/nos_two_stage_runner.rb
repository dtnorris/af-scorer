# frozen_string_literal: true

require "digest"
require "json"

module AFScoring
  class NosTwoStageRunner < Runner
    def initialize(config:, provider: nil, logger: nil, progress: nil)
      NosTwoStage.validate_profile!
      super
      validate_experiment_config!
      @nos_two_stage_prompt_builder = NosTwoStagePromptBuilder.new(afao: @afao)
    end

    def preflight(adventure_id)
      prepared = prepare_adventure(adventure_id)
      adventure = prepared.adventure
      extraction = prepared.extraction
      prompt = @nos_two_stage_prompt_builder.stage1(source_extraction: extraction)
      schema = NosTwoStage.stage1_schema

      target = PreflightTarget.new(
        group_name: NosTwoStage::STAGE1_GROUP,
        label: "NoS two-stage Stage 1 duration-structure extraction",
        artifact_name: NosTwoStage::STAGE1_GROUP,
        dimensions: ["# of Sessions"],
        prompt: prompt,
        schema: schema,
        prompt_sha256: prompt_sha256(prompt),
        schema_sha256: schema_sha256(schema)
      )

      PreflightOutcome.new(
        adventure: adventure,
        source_file: extraction.source_file,
        source_scope: extraction.scope,
        source_warnings: extraction.warnings.dup,
        output_root: validate_output_root!,
        targets: [target],
        run_metadata: nos_run_metadata(
          run_id: "preflight",
          adventure: adventure,
          extraction: extraction
        ).merge(
          "preflight_scope" => "stage1_exact_stage2_dynamic",
          "provider_inference_calls" => 0
        )
      )
    end

    def score(adventure_id, regression: false)
      if regression
        raise SpecificationError,
              "Two-stage # of Sessions experiment does not permit regression mode; keep expected values outside inference"
      end

      prepared = prepare_adventure(adventure_id)
      adventure = prepared.adventure
      extraction = prepared.extraction
      @provider ||= build_provider
      run_id = build_run_id
      raw_paths = []

      raw_paths << @writer.write_run_metadata(
        adventure_id: adventure.id,
        run_id: run_id,
        metadata: nos_run_metadata(run_id: run_id, adventure: adventure, extraction: extraction)
      )

      stage1_prompt = @nos_two_stage_prompt_builder.stage1(source_extraction: extraction)
      stage1_schema = NosTwoStage.stage1_schema
      log("[#{adventure.id}] NoS two-stage Stage 1: extracting source-grounded duration structure")
      raw_paths << write_request_artifact(
        adventure: adventure,
        run_id: run_id,
        group_name: NosTwoStage::STAGE1_GROUP,
        prompt: stage1_prompt,
        schema: stage1_schema
      )
      stage1_raw_persisted = false
      stage1_result = @provider.score(
        group_name: NosTwoStage::STAGE1_GROUP,
        prompt: stage1_prompt,
        schema: stage1_schema
      ) do |raw|
        unless stage1_raw_persisted
          raw_paths << @writer.write_raw(
            adventure_id: adventure.id,
            run_id: run_id,
            group_name: NosTwoStage::STAGE1_GROUP,
            raw: raw
          )
          stage1_raw_persisted = true
        end
      end
      unless stage1_raw_persisted
        raw_paths << @writer.write_raw(
          adventure_id: adventure.id,
          run_id: run_id,
          group_name: NosTwoStage::STAGE1_GROUP,
          raw: stage1_result.raw
        )
      end
      structure = stage1_result.parsed
      validate_stage1_structure!(structure)

      stage2_prompt = NosTwoStagePromptBuilder.new(afao: @afao.for_target(prepared.eligibility)).stage2(
        adventure: adventure,
        structure: structure
      )
      stage2_schema = NosTwoStage.stage2_schema
      log("[#{adventure.id}] NoS two-stage Stage 2: reconciling anonymized structure to normalized sessions")
      raw_paths << write_request_artifact(
        adventure: adventure,
        run_id: run_id,
        group_name: NosTwoStage::STAGE2_GROUP,
        prompt: stage2_prompt,
        schema: stage2_schema
      )
      stage2_raw_persisted = false
      stage2_result = @provider.score(
        group_name: NosTwoStage::STAGE2_GROUP,
        prompt: stage2_prompt,
        schema: stage2_schema
      ) do |raw|
        unless stage2_raw_persisted
          raw_paths << @writer.write_raw(
            adventure_id: adventure.id,
            run_id: run_id,
            group_name: NosTwoStage::STAGE2_GROUP,
            raw: raw
          )
          stage2_raw_persisted = true
        end
      end
      unless stage2_raw_persisted
        raw_paths << @writer.write_raw(
          adventure_id: adventure.id,
          run_id: run_id,
          group_name: NosTwoStage::STAGE2_GROUP,
          raw: stage2_result.raw
        )
      end

      normalized = @normalizer.normalize(
        "sessions_levels",
        stage2_result.parsed,
        expected_dimensions: ["# of Sessions"]
      )

      package = AssessmentPackage.new(
        run_id: run_id,
        adventure: adventure,
        afao_version: @afao.version,
        assessment_spec_version: @assessment_spec.version,
        provider: provider_name,
        model: provider_model,
        source_file: extraction.source_file,
        source_scope: extraction.scope,
        source_warnings: extraction.warnings,
        metrics: normalized.metrics,
        status: "PROPOSED",
        review_disposition: nil,
        package_review_flags: []
      )

      log("[#{adventure.id}] Running deterministic validation")
      @validator.validate!(package, expected_metrics: ["# of Sessions"])
      @review_rules.apply!(package, group_observations: [normalized.observations])

      assessment_csv = @writer.write_package(package)
      log("[#{adventure.id}] Validation passed; review disposition: #{package.review_disposition}")
      log("[#{adventure.id}] CSV: #{assessment_csv}")

      RunOutcome.new(
        package: package,
        assessment_csv: assessment_csv,
        regression_csv: nil,
        comparisons: [],
        raw_paths: raw_paths
      )
    end

    private

    def validate_experiment_config!
      unless @config.dig("scoring", "dimension") == "# of Sessions"
        raise ConfigurationError,
              "#{NosTwoStage.selected_profile} requires --dimension '# of Sessions'"
      end

      if @config.dig("experimental", "group")
        raise ConfigurationError,
              "#{NosTwoStage.selected_profile} cannot be combined with --experimental-group"
      end

      unless @config.dig("llm", "provider") == "ollama"
        raise ConfigurationError,
              "#{NosTwoStage.selected_profile} is a local-only pilot and requires AF_LLM_PROVIDER=ollama"
      end

      unless @config.dig("llm", "model") == NosTwoStage.selected_model
        raise ConfigurationError,
              "#{NosTwoStage.selected_profile} is frozen to #{NosTwoStage.selected_model.inspect}; " \
              "configured model is #{@config.dig('llm', 'model').inspect}"
      end
    end

    def validate_stage1_structure!(structure)
      unless structure.is_a?(Hash)
        raise ValidationError.new(
          "NoS Stage 1 validation failed",
          failures: ["Stage 1 output must be a JSON object"]
        )
      end

      required = NosTwoStage.stage1_schema.fetch("required")
      missing = required - structure.keys
      failures = []
      failures << "Missing Stage 1 fields: #{missing.join(', ')}" unless missing.empty?
      unless structure["major_play_bodies"].is_a?(Array) && !structure["major_play_bodies"].empty?
        failures << "Stage 1 must identify at least one major play body"
      end
      if structure["benchmark_contamination_detected"] == true
        failures << "Stage 1 reported target benchmark contamination; reconciliation is forbidden"
      end

      return if failures.empty?

      raise ValidationError.new("NoS Stage 1 validation failed", failures: failures)
    end

    def write_request_artifact(adventure:, run_id:, group_name:, prompt:, schema:)
      @writer.write_request(
        adventure_id: adventure.id,
        run_id: run_id,
        group_name: group_name,
        request: @provider.request_artifact(
          group_name: group_name,
          prompt: prompt,
          schema: schema
        ),
        prompt_sha256: prompt_sha256(prompt),
        schema_sha256: schema_sha256(schema)
      )
    end

    def prompt_sha256(prompt)
      Digest::SHA256.hexdigest("#{prompt.instructions}\0#{prompt.input}")
    end

    def schema_sha256(schema)
      Digest::SHA256.hexdigest(JSON.generate(schema))
    end

    def nos_run_metadata(run_id:, adventure:, extraction:)
      metadata = {
        "run_id" => run_id,
        "adventure_id" => adventure.id,
        "prompt_profile" => "nos_two_stage_#{NosTwoStage.selected_profile}",
        "experimental" => true,
        "experimental_profile" => NosTwoStage.selected_profile,
        "selected_dimension" => "# of Sessions",
        "groups_scored" => ["sessions_levels"],
        "stage1_group" => NosTwoStage::STAGE1_GROUP,
        "stage2_group" => NosTwoStage::STAGE2_GROUP,
        "stage1_schema_sha256" => schema_sha256(NosTwoStage.stage1_schema),
        "stage2_schema_sha256" => schema_sha256(NosTwoStage.stage2_schema),
        "stage1_catalog_identity_supplied" => false,
        "stage2_catalog_identity_supplied" => false,
        "stage2_raw_source_supplied" => false,
        "paid_api_authorized" => false,
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
  end
end
