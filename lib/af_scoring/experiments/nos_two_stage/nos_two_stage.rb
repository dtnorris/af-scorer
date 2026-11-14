# frozen_string_literal: true

require "json"

module AFScoring
  module NosTwoStage
    PROFILE_ENV = "AF_NOS_TWO_STAGE_PROFILE"
    PROFILE = "nemotron-v0.1"
    MODEL = "nemotron-3-nano:30b"
    GLM_PROFILE = "glm-v0.1"
    GLM_MODEL = "glm-4.7-flash"
    PROFILES = {
      PROFILE => MODEL,
      GLM_PROFILE => GLM_MODEL
    }.freeze
    STAGE1_GROUP = "nos_duration_structure"
    STAGE2_GROUP = "nos_duration_reconciliation"

    STAGE1_SYSTEM_INSTRUCTIONS = <<~TEXT.freeze
      You are the source-evidence extraction stage of an AdventureFinder # of Sessions experiment.

      Extract only duration-relevant structure that is supported by the supplied published source material.
      Do not estimate a number of sessions, a practical range, hours of play, or any other final duration value.
      Do not use prior knowledge of the adventure, product reputation, actual-play reports, reviews, community
      estimates, anthology or campaign format, page count, level span, or generic assumptions about how long
      adventures of this type usually take.

      Treat page markers in the supplied source as evidence locators. Every substantive extracted claim must be
      supported by source evidence. If the source explicitly states a table-play duration, record that statement
      only in the dedicated explicit_table_time_evidence field; do not convert it into a session estimate.

      Identify macro-scale substantive bodies of ordinary play rather than turning each room, encounter, scene,
      chapter, realm, or keyed location into an independent duration unit. Preserve repeated play cycles when the
      source actually supports repetition. Distinguish ordinary play from optional, conditional, mutually exclusive,
      and bypassable material. Record compression or bypass evidence only when the source supports it; do not infer
      compression merely because an adventure is compact, introductory, single-location, linear, or continuous.

      If target-specific AdventureFinder benchmark information somehow appears in the supplied source, do not use
      it and set benchmark_contamination_detected to true. Return only data conforming to the provided schema.
    TEXT

    STAGE2_SYSTEM_INSTRUCTIONS = <<~TEXT.freeze
      You are the reconciliation stage of an AdventureFinder # of Sessions experiment.

      The adventure identity is intentionally withheld. Use only the supplied source-grounded structural extraction
      and the supplied AFAO # of Sessions rules. Do not infer or guess the adventure identity, and do not use prior
      knowledge, actual-play reports, reviews, community duration estimates, product reputation, anthology or
      campaign format, page count, level span, or generic assumptions about how long adventures of this type take.

      Normalize ordinary engaged play to 2.5–3.0 hour sessions as required by AFAO. Reconcile whether that normalized
      table time can realistically contain the ordinary substantive play bodies and repeated cycles in the extraction.
      Repeated ordinary play accumulates normally unless the extraction contains source-supported bypass, compression,
      or mutual-exclusion evidence. Weight optional, conditional, bypassable, and mutually exclusive material rather
      than pretending all branches occur in one playthrough.

      Do not use an additive sessions-per-body, sessions-per-chapter, sessions-per-room, sessions-per-level, or
      sessions-per-page formula. In-fiction elapsed time is not table time. Narrative continuity, a single location,
      or a compact premise does not itself compress substantive play. Conversely, multiple named phases do not each
      require a separate session. The final point estimate and Practical Range must be internally consistent with the
      supplied structural extraction and with any explicit source-supported table-time evidence.

      If benchmark_contamination_detected is true, return Insufficient Evidence rather than using the contaminated
      extraction. Return only data conforming to the provided response schema.
    TEXT

    module_function

    def enabled?
      !ENV.fetch(PROFILE_ENV, "").empty?
    end

    def selected_profile
      ENV.fetch(PROFILE_ENV, "")
    end

    def selected_model
      PROFILES[selected_profile]
    end

    def validate_profile!
      return if PROFILES.key?(selected_profile)

      raise ConfigurationError,
            "Unsupported # of Sessions two-stage profile #{selected_profile.inspect}; " \
            "expected one of #{PROFILES.keys.map(&:inspect).join(', ')}"
    end

    def stage1_schema
      {
        "type" => "object",
        "additionalProperties" => false,
        "properties" => {
          "source_boundary_uncertainty" => { "type" => "boolean" },
          "benchmark_contamination_detected" => { "type" => "boolean" },
          "major_play_bodies" => {
            "type" => "array",
            "minItems" => 1,
            "items" => major_play_body_schema
          },
          "repeated_play_cycles" => {
            "type" => "array",
            "items" => repeated_play_cycle_schema
          },
          "optional_or_mutually_exclusive_material" => {
            "type" => "array",
            "items" => optional_material_schema
          },
          "explicit_bypass_or_compression_evidence" => {
            "type" => "array",
            "items" => sourced_statement_schema
          },
          "explicit_table_time_evidence" => {
            "type" => "array",
            "items" => sourced_statement_schema
          },
          "pacing_and_progression_constraints" => {
            "type" => "array",
            "items" => pacing_constraint_schema
          },
          "coverage_summary" => { "type" => "string" },
          "source_grounding_notes" => { "type" => "string" }
        },
        "required" => %w[
          source_boundary_uncertainty benchmark_contamination_detected major_play_bodies
          repeated_play_cycles optional_or_mutually_exclusive_material
          explicit_bypass_or_compression_evidence explicit_table_time_evidence
          pacing_and_progression_constraints coverage_summary source_grounding_notes
        ]
      }
    end

    def stage2_schema
      SchemaBuilder.for_group("sessions_levels", dimensions: ["# of Sessions"])
    end

    def evidence_array_schema
      {
        "type" => "array",
        "minItems" => 1,
        "items" => SchemaBuilder.evidence_schema
      }
    end

    def major_play_body_schema
      {
        "type" => "object",
        "additionalProperties" => false,
        "properties" => {
          "label" => { "type" => "string" },
          "ordinary_presence" => {
            "type" => "string",
            "enum" => %w[ordinary conditional optional]
          },
          "substantive_play" => { "type" => "string" },
          "evidence" => evidence_array_schema
        },
        "required" => %w[label ordinary_presence substantive_play evidence]
      }
    end

    def repeated_play_cycle_schema
      {
        "type" => "object",
        "additionalProperties" => false,
        "properties" => {
          "label" => { "type" => "string" },
          "ordinary_presence" => {
            "type" => "string",
            "enum" => %w[ordinary conditional optional]
          },
          "repetition_pattern" => { "type" => "string" },
          "evidence" => evidence_array_schema
        },
        "required" => %w[label ordinary_presence repetition_pattern evidence]
      }
    end

    def optional_material_schema
      {
        "type" => "object",
        "additionalProperties" => false,
        "properties" => {
          "label" => { "type" => "string" },
          "relationship" => {
            "type" => "string",
            "enum" => %w[optional conditional mutually_exclusive bypassable]
          },
          "duration_relevance" => { "type" => "string" },
          "evidence" => evidence_array_schema
        },
        "required" => %w[label relationship duration_relevance evidence]
      }
    end

    def sourced_statement_schema
      {
        "type" => "object",
        "additionalProperties" => false,
        "properties" => {
          "description" => { "type" => "string" },
          "evidence" => evidence_array_schema
        },
        "required" => %w[description evidence]
      }
    end

    def pacing_constraint_schema
      {
        "type" => "object",
        "additionalProperties" => false,
        "properties" => {
          "description" => { "type" => "string" },
          "kind" => {
            "type" => "string",
            "enum" => %w[in_fiction_spacing source_pacing_instruction recurring_activity progression_gate other]
          },
          "evidence" => evidence_array_schema
        },
        "required" => %w[description kind evidence]
      }
    end
  end

  class NosTwoStagePromptBuilder
    def initialize(afao:)
      @afao = afao
    end

    def stage1(source_extraction:)
      PromptBuilder::Prompt.new(
        instructions: NosTwoStage::STAGE1_SYSTEM_INSTRUCTIONS,
        input: <<~PROMPT
          # Published Source Material

          The source body below is the only evidence basis for this extraction. Page markers are evidence locators.
          Material outside the canonical source slice must not be used.

          #{source_extraction.text}

          # Duration-Structure Extraction Task

          Extract the macro-scale source-grounded structure needed for a later # of Sessions reconciliation pass.
          Do not produce, imply, recommend, or validate a session count or other final duration estimate.
        PROMPT
      )
    end

    def stage2(adventure:, structure:)
      rubric = @afao.rubric_for_dimension(
        "# of Sessions",
        target_id: adventure.id,
        target_title: adventure.title
      )

      PromptBuilder::Prompt.new(
        instructions: NosTwoStage::STAGE2_SYSTEM_INSTRUCTIONS,
        input: <<~PROMPT
          # AFAO #{@afao.version} # of Sessions Rubric

          #{rubric}

          # Source-Grounded Duration Structure

          The following JSON was produced by the source-extraction stage. Treat it as the complete evidence basis
          for reconciliation. The canonical adventure identity and raw source are intentionally not provided.

          #{JSON.pretty_generate(structure)}

          # Reconciliation Task

          Produce the final # of Sessions assessment from the supplied evidence only. Reconcile the point estimate,
          Practical Range, confidence, and path sensitivity against the full ordinary-play structure before answering.
        PROMPT
      )
    end
  end
end
