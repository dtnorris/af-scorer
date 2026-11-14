# frozen_string_literal: true

module AFScoring
  module Providers
    ProviderResult = Struct.new(:parsed, :raw, keyword_init: true)

    class Base
      def provider_name
        self.class.name.split("::").last.sub(/Provider$/, "").downcase
      end

      # Return a serializable description of the exact provider request that
      # score() will issue. Concrete providers override this with their native
      # transport/API payload. The fallback keeps custom/test providers
      # provenance-capable without forcing a new interface implementation.
      def request_artifact(group_name:, prompt:, schema:)
        {
          "provider" => provider_name,
          "transport" => { "kind" => "provider_score" },
          "payload" => {
            "group_name" => group_name,
            "model" => respond_to?(:model) ? model : nil,
            "instructions" => prompt.instructions,
            "input" => prompt.input,
            "schema" => schema
          }
        }
      end

      def score(group_name:, prompt:, schema:)
        raise NotImplementedError
      end
    end
  end
end
