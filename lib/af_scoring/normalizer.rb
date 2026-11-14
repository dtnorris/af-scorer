# frozen_string_literal: true

module AFScoring
  class Normalizer
    def normalize(group_name, payload, expected_dimensions: nil)
      payload = stringify_keys(payload)
      returned_group = payload["group"]
      raise NormalizationError, "Expected group #{group_name}, got #{returned_group.inspect}" unless returned_group == group_name

      expected_dimensions ||= DimensionGroups.fetch(group_name)
      if group_name == "sessions_levels"
        normalize_sessions_levels(payload, expected_dimensions)
      else
        normalize_interpretive(group_name, payload, expected_dimensions)
      end
    end

    private

    def normalize_sessions_levels(payload, expected_dimensions)
      metrics = []
      if expected_dimensions.include?("# of Sessions")
        sessions = payload.fetch("sessions")
        metrics << MetricAssessment.new(
        metric: "# of Sessions",
        kind: "sessions",
        assessment_state: sessions["assessment_state"],
        value: sessions["normalized_sessions"],
        range_low: sessions["practical_range_low"],
        range_high: sessions["practical_range_high"],
        confidence: sessions["confidence"],
        path_sensitive: sessions["path_sensitive"],
        path_variation_affects_anchor: nil,
        rationale: sessions["rationale"],
        evidence: evidence(sessions["evidence"]),
        rubric_ambiguity: sessions["rubric_ambiguity"],
        evidence_sufficient: sessions["evidence_sufficient"],
        review_flags: [],
        group: "sessions_levels"
      )
      end

      if expected_dimensions.include?("Levels")
        metrics << normalize_level("Level Start", payload.fetch("level_start"))
        metrics << normalize_level("Level End", payload.fetch("level_end"))
      end
      NormalizedGroup.new(metrics: metrics, observations: stringify_keys(payload.fetch("group_observations")))
    rescue KeyError => e
      raise NormalizationError, "Missing sessions/levels output field: #{e.message}"
    end

    def normalize_level(metric, data)
      MetricAssessment.new(
        metric: metric,
        kind: "level",
        assessment_state: data["assessment_state"],
        value: data["value"],
        rationale: data["rationale"],
        evidence: evidence(data["evidence"]),
        rubric_ambiguity: data["rubric_ambiguity"],
        evidence_sufficient: data["evidence_sufficient"],
        review_flags: [],
        group: "sessions_levels"
      )
    end

    def normalize_interpretive(group_name, payload, expected)
      items = Array(payload.fetch("dimensions"))
      returned = items.map { |item| item["dimension"] }
      unless returned.sort == expected.sort
        raise NormalizationError,
              "Group #{group_name} returned dimensions #{returned.inspect}; expected #{expected.inspect}"
      end

      metrics = items.map do |data|
        MetricAssessment.new(
          metric: data["dimension"],
          kind: "interpretive",
          assessment_state: data["assessment_state"],
          value: data["score"],
          confidence: data["confidence"],
          path_sensitive: data["path_sensitive"],
          path_variation_affects_anchor: data["path_variation_affects_anchor"],
          rationale: data["rationale"],
          evidence: evidence(data["evidence"]),
          adjacent_lower_reason: data["adjacent_lower_reason"],
          adjacent_higher_reason: data["adjacent_higher_reason"],
          rubric_ambiguity: data["rubric_ambiguity"],
          evidence_sufficient: data["evidence_sufficient"],
          review_flags: [],
          group: group_name
        )
      end
      NormalizedGroup.new(metrics: metrics, observations: stringify_keys(payload.fetch("group_observations")))
    rescue KeyError => e
      raise NormalizationError, "Missing interpretive output field for #{group_name}: #{e.message}"
    end

    def evidence(items)
      Array(items).map do |item|
        item = stringify_keys(item)
        Evidence.new(locator: item["locator"], note: item["note"])
      end
    end

    def stringify_keys(value)
      case value
      when Hash
        value.each_with_object({}) { |(k, v), h| h[k.to_s] = stringify_keys(v) }
      when Array
        value.map { |v| stringify_keys(v) }
      else
        value
      end
    end
  end
end
