# frozen_string_literal: true

module AFScoring
  module NosTwoStage
    module_function

    def anonymize_structure(value, adventure:)
      redact_identity_value(value, identity_terms(adventure))
    end

    def contains_target_identity?(value, adventure:)
      serialized = JSON.generate(value)
      identity_terms(adventure).any? do |term|
        serialized.match?(/#{Regexp.escape(term)}/i)
      end
    end

    def identity_terms(adventure)
      values = %i[id title source_book publisher].filter_map do |attribute|
        next unless adventure.respond_to?(attribute)

        value = adventure.public_send(attribute).to_s.strip
        value unless value.empty?
      end

      title = adventure.respond_to?(:title) ? adventure.title.to_s.strip : ""
      unless title.empty?
        without_leading_article = title.sub(/\A(?:the|a|an)\s+/i, "").strip
        values << without_leading_article unless without_leading_article == title
      end

      values
        .reject { |value| value.empty? || (value.length < 4 && !value.match?(/\AADV-/i)) }
        .uniq
        .sort_by { |value| -value.length }
    end

    def redact_identity_value(value, terms)
      case value
      when Hash
        value.each_with_object({}) do |(key, nested), redacted|
          redacted[key] = redact_identity_value(nested, terms)
        end
      when Array
        value.map { |nested| redact_identity_value(nested, terms) }
      when String
        terms.reduce(value.dup) do |redacted, term|
          redacted.gsub(/#{Regexp.escape(term)}/i, "[TARGET]")
        end
      else
        value
      end
    end
    private_class_method :redact_identity_value
  end

  module NosTwoStagePromptIdentityRedaction
    def stage2(adventure:, structure:)
      anonymized = NosTwoStage.anonymize_structure(structure, adventure: adventure)
      if NosTwoStage.contains_target_identity?(anonymized, adventure: adventure)
        raise ValidationError.new(
          "NoS Stage 2 identity redaction failed",
          failures: ["Target identity survived deterministic structure redaction"]
        )
      end

      super(adventure: adventure, structure: anonymized)
    end
  end

  NosTwoStagePromptBuilder.prepend(NosTwoStagePromptIdentityRedaction)
end
