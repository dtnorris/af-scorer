# frozen_string_literal: true

module AFScoring
  # Loads the selected standalone owner; never falls back from explicit selection.
  module SourceMarkdownOwner
    module_function

    # Return the supported owner module, or raise error_class for missing/invalid
    # selection. Keep AF_SOURCE_MD_ROOT fixed for the life of the Ruby process.
    def load!(error_class:)
      if ENV.key?("AF_SOURCE_MD_ROOT")
        root = ENV.fetch("AF_SOURCE_MD_ROOT")
        unless !root.strip.empty? && File.absolute_path(root) == root && File.directory?(root)
          raise error_class, "AF_SOURCE_MD_ROOT must select an existing absolute owner directory"
        end
        entry = File.join(root, "lib", "af_source_md.rb")
        raise error_class, "Missing selected source Markdown owner: #{entry}" unless File.file?(entry)
        require entry
        unless defined?(AFSourceMD::ROOT) && AFSourceMD::ROOT == File.realpath(root)
          raise error_class, "Selected source Markdown owner identity does not match #{root}"
        end
      else
        require "af_source_md"
      end
      unless defined?(AFSourceMD::API_VERSION) && AFSourceMD::API_VERSION == "af-source-md/v0.1" &&
             defined?(AFSourceMD::Registry) && defined?(AFSourceMD::SourceRegister) &&
             defined?(AFSourceMD::SourceResolver) && defined?(AFSourceMD::SourceDocument)
        raise error_class, "Unsupported source Markdown owner API; expected af-source-md/v0.1"
      end
      AFSourceMD
    rescue LoadError, SyntaxError, StandardError => error
      raise error_class, "Cannot load source Markdown owner: #{error.message}"
    end
  end
end
