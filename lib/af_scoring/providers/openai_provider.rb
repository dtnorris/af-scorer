# frozen_string_literal: true

require "json"

module AFScoring
  module Providers
    class OpenAIProvider < Base
      attr_reader :model

      def initialize(model:, reasoning_effort: "high", api_key: ENV["OPENAI_API_KEY"], client: nil)
        @model = model
        @reasoning_effort = reasoning_effort
        @client = client || build_client(api_key)
      end

      def request_artifact(group_name:, prompt:, schema:)
        {
          "provider" => provider_name,
          "transport" => {
            "kind" => "sdk_call",
            "operation" => "responses.create"
          },
          "payload" => JSON.parse(JSON.generate(request_payload(group_name: group_name, prompt: prompt, schema: schema)))
        }
      end

      def score(group_name:, prompt:, schema:)
        response = @client.responses.create(
          **request_payload(group_name: group_name, prompt: prompt, schema: schema)
        )

        text = extract_output_text(response)
        parsed = JSON.parse(text)
        ProviderResult.new(parsed: parsed, raw: serializable_raw(response))
      rescue JSON::ParserError => e
        raise ProviderError, "OpenAI returned non-JSON structured output for #{group_name}: #{e.message}"
      rescue StandardError => e
        raise if e.is_a?(ProviderError)
        raise ProviderError, "OpenAI scoring failed for #{group_name}: #{e.class}: #{e.message}"
      end

      private

      def request_payload(group_name:, prompt:, schema:)
        {
          model: @model,
          instructions: prompt.instructions,
          input: prompt.input,
          reasoning: { effort: @reasoning_effort },
          text: {
            format: {
              type: "json_schema",
              name: "af_#{group_name}_assessment",
              strict: true,
              schema: schema
            }
          }
        }
      end

      def build_client(api_key)
        raise ConfigurationError, "OPENAI_API_KEY is not set" if api_key.nil? || api_key.empty?
        require "openai"
        OpenAI::Client.new(api_key: api_key)
      rescue LoadError
        raise ConfigurationError, "The official 'openai' Ruby gem is not installed. Run bundle install."
      end

      def extract_output_text(response)
        return response.output_text if response.respond_to?(:output_text) && response.output_text

        hash = response.respond_to?(:to_h) ? response.to_h : response
        hash = stringify_keys(hash)
        texts = Array(hash["output"]).flat_map do |item|
          Array(item["content"]).filter_map do |content|
            content["text"] if ["output_text", "text"].include?(content["type"])
          end
        end
        result = texts.join
        raise ProviderError, "OpenAI response did not contain output text" if result.empty?
        result
      end

      def serializable_raw(response)
        raw = response.respond_to?(:to_h) ? response.to_h : response
        JSON.parse(JSON.generate(raw))
      rescue StandardError
        { "inspect" => response.inspect }
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
end
