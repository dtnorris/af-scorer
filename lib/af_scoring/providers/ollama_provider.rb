# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

module AFScoring
  module Providers
    class OllamaProvider < Base
      DEFAULT_BASE_URL = "http://127.0.0.1:11434"
      DEFAULT_OPEN_TIMEOUT_SECONDS = 5
      DEFAULT_READ_TIMEOUT_SECONDS = 7200
      DEFAULT_MAX_TOKENS = 4_096

      attr_reader :model, :base_url, :max_tokens

      def initialize(
        model:,
        reasoning_effort: "high",
        base_url: DEFAULT_BASE_URL,
        max_tokens: DEFAULT_MAX_TOKENS,
        transport: nil,
        open_timeout: DEFAULT_OPEN_TIMEOUT_SECONDS,
        read_timeout: DEFAULT_READ_TIMEOUT_SECONDS
      )
        @model = model
        @reasoning_effort = reasoning_effort
        @base_url = (base_url.nil? || base_url.empty?) ? DEFAULT_BASE_URL : base_url
        @max_tokens = normalize_max_tokens(max_tokens)
        @transport = transport
        @open_timeout = open_timeout
        @read_timeout = read_timeout
      end

      def request_artifact(group_name:, prompt:, schema:)
        {
          "provider" => provider_name,
          "transport" => {
            "kind" => "http_post",
            "endpoint" => endpoint_uri.to_s,
            "content_type" => "application/json"
          },
          "payload" => serializable(request_payload(group_name: group_name, prompt: prompt, schema: schema))
        }
      end

      def score(group_name:, prompt:, schema:)
        payload = request_payload(group_name: group_name, prompt: prompt, schema: schema)

        raw = transport(endpoint_uri, payload)
        yield raw if block_given?
        content = raw.dig("choices", 0, "message", "content")
        if content.nil? || content.empty?
          finish_reason = raw.dig("choices", 0, "finish_reason")
          if finish_reason == "length"
            raise ProviderError,
                  "Ollama exhausted max_tokens=#{@max_tokens} before producing assistant content for #{group_name}"
          end

          raise ProviderError, "Ollama response did not contain assistant content for #{group_name}"
        end

        parsed = JSON.parse(content)
        ProviderResult.new(parsed: parsed, raw: raw)
      rescue JSON::ParserError => e
        raise ProviderError, "Ollama returned non-JSON structured output for #{group_name}: #{e.message}"
      rescue StandardError => e
        raise if e.is_a?(ProviderError)
        raise ProviderError, "Ollama scoring failed for #{group_name}: #{e.class}: #{e.message}"
      end

      private

      def request_payload(group_name:, prompt:, schema:)
        payload = {
          model: @model,
          messages: [
            { role: "system", content: prompt.instructions },
            { role: "user", content: prompt.input }
          ],
          max_tokens: @max_tokens,
          temperature: 0,
          stream: false,
          response_format: {
            type: "json_schema",
            json_schema: {
              name: "af_#{group_name}_assessment",
              strict: true,
              schema: schema
            }
          }
        }

        reasoning_effort = normalized_reasoning_effort
        payload[:reasoning_effort] = reasoning_effort if reasoning_effort
        payload
      end

      def normalized_reasoning_effort
        value = @reasoning_effort.to_s.strip
        return nil if value.empty? || value.casecmp("none").zero?

        value
      end

      def normalize_max_tokens(value)
        value = DEFAULT_MAX_TOKENS if value.nil? || value.to_s.strip.empty?
        parsed = value.is_a?(Integer) ? value : Integer(value.to_s, 10)
        unless parsed.positive?
          raise ConfigurationError,
                "Ollama max_tokens must be a positive integer; got #{value.inspect}"
        end
        parsed
      rescue ArgumentError, TypeError
        raise ConfigurationError,
              "Ollama max_tokens must be a positive integer; got #{value.inspect}"
      end

      def serializable(value)
        JSON.parse(JSON.generate(value))
      end

      def endpoint_uri
        uri = URI.parse("#{@base_url.sub(%r{/+$}, '')}/v1/chat/completions")
        unless %w[http https].include?(uri.scheme) && uri.host
          raise ConfigurationError, "Invalid Ollama base URL: #{@base_url.inspect}"
        end
        uri
      rescue URI::InvalidURIError => e
        raise ConfigurationError, "Invalid Ollama base URL #{@base_url.inspect}: #{e.message}"
      end

      def transport(uri, payload)
        return @transport.call(uri, payload) if @transport

        request = Net::HTTP::Post.new(uri.request_uri)
        request["Content-Type"] = "application/json"
        request.body = JSON.generate(payload)

        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == "https"
        http.open_timeout = @open_timeout
        http.read_timeout = @read_timeout
        response = http.request(request)

        unless response.is_a?(Net::HTTPSuccess)
          body = response.body.to_s.gsub(/\s+/, " ").strip
          body = "#{body[0, 500]}..." if body.length > 500
          raise ProviderError, "Ollama HTTP #{response.code} for #{uri}: #{body}"
        end

        JSON.parse(response.body)
      end
    end
  end
end
