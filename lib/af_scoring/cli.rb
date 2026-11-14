# frozen_string_literal: true

require "optparse"
require "json"
require "fileutils"

module AFScoring
  class CLI
    def initialize(argv, project_root: File.expand_path("../..", __dir__), out: $stdout, err: $stderr)
      @argv = argv.dup
      @project_root = project_root
      @out = out
      @err = err
    end

    def run
      options = parse_options
      return 0 if options[:help]
      if options[:render_preflight] && !options[:preflight]
        raise OptionParser::ParseError, "--render-preflight requires --preflight"
      end
      if options[:prepared_source] && !options[:preflight]
        raise OptionParser::ParseError, "--prepared-source requires --preflight"
      end
      if options[:prepare_source] && options[:preflight]
        raise OptionParser::ParseError, "--prepare-source cannot be combined with --preflight"
      end
      if options[:prepare_source] && options[:prepared_source]
        raise OptionParser::ParseError, "--prepare-source cannot be combined with --prepared-source"
      end

      config = Config.new(
        project_root: @project_root,
        config_path: options[:config],
        overrides: config_overrides(options)
      )
      progress = Progress.new(io: @out, verbose: options[:verbose])
      runner = Runner.new(config: config, logger: ->(message) { @out.puts(message) }, progress: progress)

      if options[:prepare_source]
        if options[:regression_all] || options[:batch] || options[:regression_id] || options[:with_regression]
          raise OptionParser::ParseError,
                "--prepare-source accepts one positional Adventure ID and cannot be combined with regression or batch modes"
        end
        adventure_id = @argv.shift
        raise OptionParser::ParseError, "--prepare-source requires one positional Adventure ID" unless adventure_id
        unless @argv.empty?
          raise OptionParser::ParseError, "Unexpected arguments: #{@argv.join(' ')}"
        end

        payload = runner.prepare_source(adventure_id)
        prepared_path = write_prepared_source(payload, options.fetch(:prepare_source))
        print_prepared_source(payload, prepared_path)
        return 0
      end

      if options[:preflight]
        if options[:regression_all] || options[:batch] || options[:regression_id] || options[:with_regression]
          raise OptionParser::ParseError,
                "--preflight accepts one positional Adventure ID and cannot be combined with regression or batch modes"
        end
        adventure_id = @argv.shift
        raise OptionParser::ParseError, "--preflight requires one positional Adventure ID" unless adventure_id
        unless @argv.empty?
          raise OptionParser::ParseError, "Unexpected arguments: #{@argv.join(' ')}"
        end

        prepared_source = options[:prepared_source] && load_prepared_source(options[:prepared_source])
        outcome = runner.preflight(adventure_id, prepared_source: prepared_source)
        rendered_path = options[:render_preflight] && write_preflight_render(outcome, options[:render_preflight])
        print_preflight(outcome, rendered_path: rendered_path)
        return 0
      end

      if options[:regression_all]
        return run_many(runner, runner.reference_set.ids, regression: true)
      end

      if options[:batch]
        ids = load_batch_ids(options[:batch])
        return run_many(runner, ids, regression: options[:with_regression])
      end

      adventure_id = options[:regression_id] || @argv.shift
      unless adventure_id
        @err.puts parser
        return 2
      end
      unless @argv.empty?
        raise OptionParser::ParseError, "Unexpected arguments: #{@argv.join(' ')}"
      end

      outcome = runner.score(adventure_id, regression: !!options[:regression_id])
      print_outcome(outcome)
      0
    rescue AFScoring::Error => e
      @err.puts "ERROR: #{e.message}"
      if e.respond_to?(:failures) && e.failures&.any?
        e.failures.each { |failure| @err.puts "  - #{failure}" }
      end
      1
    rescue OptionParser::ParseError => e
      @err.puts "ERROR: #{e.message}"
      @err.puts parser
      2
    end

    private

    def parse_options
      options = {}
      @parser = OptionParser.new do |opts|
        opts.banner = "Usage: bin/af-score [options] ADV-XXXX"
        opts.separator ""
        opts.separator "Modes:"
        opts.on("--preflight", "Resolve source and build exact prompt/schema without model inference") { options[:preflight] = true }
        opts.on("--render-preflight PATH", "With --preflight, write exact prompt/schema/metadata JSON") { |v| options[:render_preflight] = v }
        opts.on("--prepare-source PATH", "Resolve/extract one adventure source once and write a reusable zero-inference prepared-source JSON") { |v| options[:prepare_source] = v }
        opts.on("--prepared-source PATH", "With --preflight, reuse a prepared-source JSON after validating its frozen source bindings") { |v| options[:prepared_source] = v }
        opts.on("--batch PATH", "Score Adventure IDs listed one per line") { |v| options[:batch] = v }
        opts.on("--regression ADV-ID", "Blind-score one adventure, then compare with AFAO calibration expectations") { |v| options[:regression_id] = v }
        opts.on("--regression-all", "Regression-score all Adventure IDs listed in the reference workbook") { options[:regression_all] = true }
        opts.on("--with-regression", "With --batch, compare each scored adventure when references exist") { options[:with_regression] = true }
        opts.on("--dimension DIMENSION", "Score only one canonical AFAO dimension") { |v| options[:dimension] = v }
        opts.separator ""
        opts.separator "Configuration:"
        opts.on("--config PATH", "Additional YAML config") { |v| options[:config] = v }
        opts.on("--model MODEL", "Override configured model") { |v| options[:model] = v }
        opts.on("--output DIR", "Override output directory") { |v| options[:output] = v }
        opts.on("--experimental-group GROUP", "Score only one existing dimension group (test-only)") { |v| options[:experimental_group] = v }
        opts.on("--verbose", "Show detailed scoring lifecycle output") { options[:verbose] = true }
        opts.on("-h", "--help", "Show help") do
          @out.puts opts
          options[:help] = true
        end
      end
      @parser.parse!(@argv)
      options
    end

    def parser
      @parser || OptionParser.new { |opts| opts.banner = "Usage: bin/af-score [options] ADV-XXXX" }
    end

    def config_overrides(options)
      overrides = {}
      overrides["llm"] = { "model" => options[:model] } if options[:model]
      overrides["paths"] = { "output_root" => options[:output] } if options[:output]
      overrides["scoring"] = { "dimension" => options[:dimension] } if options[:dimension]
      if options[:experimental_group]
        overrides["experimental"] = { "group" => options[:experimental_group] }
      end
      overrides
    end

    def load_batch_ids(path)
      raise ConfigurationError, "Batch file does not exist: #{path}" unless File.file?(path)
      File.readlines(path, chomp: true).map(&:strip).reject { |line| line.empty? || line.start_with?("#") }
    end

    # Score the supplied IDs, reporting per-ID failures and returning an exit status.
    # Explicit regression validates its selected workbook even for an empty batch;
    # reference errors propagate to the CLI error handler before any scoring begins.
    def run_many(runner, ids, regression: false)
      runner.reference_set if regression
      failures = []
      ids.each do |id|
        begin
          outcome = runner.score(id, regression: regression)
          print_outcome(outcome)
        rescue AFScoring::Error => e
          failures << [id, e]
          @err.puts "[#{id}] ERROR: #{e.message}"
        end
      end
      @out.puts "Completed #{ids.length - failures.length}/#{ids.length}; failures=#{failures.length}"
      failures.empty? ? 0 : 1
    end

    def write_prepared_source(payload, path)
      expanded = File.expand_path(path)
      FileUtils.mkdir_p(File.dirname(expanded))
      File.write(expanded, JSON.pretty_generate(payload))
      expanded
    end

    def load_prepared_source(path)
      expanded = File.expand_path(path)
      raise ConfigurationError, "Prepared source does not exist: #{expanded}" unless File.file?(expanded)

      payload = JSON.parse(File.read(expanded))
      raise ConfigurationError, "Prepared source must be a JSON object: #{expanded}" unless payload.is_a?(Hash)

      payload
    rescue JSON::ParserError => e
      raise ConfigurationError, "Invalid prepared source JSON #{expanded}: #{e.message}"
    end

    def print_prepared_source(payload, path)
      @out.puts "Prepared source: PASS (no model inference)"
      @out.puts "Adventure: #{payload.dig('adventure', 'id')} — #{payload.dig('adventure', 'title')}"
      @out.puts "Source: #{payload.dig('source_file', 'path')} [#{payload.dig('extraction', 'scope')}]"
      @out.puts "Prepared source artifact: #{path}"
      @out.puts "Provider inference calls: 0"
    end

    def write_preflight_render(outcome, path)
      expanded = File.expand_path(path)
      FileUtils.mkdir_p(File.dirname(expanded))
      payload = {
        "adventure_id" => outcome.adventure.id,
        "adventure_title" => outcome.adventure.title,
        "source_file" => outcome.source_file,
        "source_scope" => outcome.source_scope,
        "source_warnings" => outcome.source_warnings,
        "output_root" => outcome.output_root,
        "run_metadata" => outcome.run_metadata,
        "targets" => outcome.targets.map do |target|
          {
            "group_name" => target.group_name,
            "label" => target.label,
            "artifact_name" => target.artifact_name,
            "dimensions" => target.dimensions,
            "prompt_sha256" => target.prompt_sha256,
            "schema_sha256" => target.schema_sha256,
            "prompt" => {
              "instructions" => target.prompt.instructions,
              "input" => target.prompt.input
            },
            "schema" => target.schema
          }
        end
      }
      File.write(expanded, JSON.pretty_generate(payload))
      expanded
    end

    def print_preflight(outcome, rendered_path: nil)
      @out.puts "Preflight: PASS (no model inference)"
      @out.puts "Adventure: #{outcome.adventure.id} — #{outcome.adventure.title}"
      @out.puts "Source: #{outcome.source_file} [#{outcome.source_scope}]"
      outcome.source_warnings.each { |warning| @out.puts "Source warning: #{warning}" }
      @out.puts "Output root: #{outcome.output_root}"
      @out.puts "Targets: #{outcome.targets.length}"
      outcome.targets.each do |target|
        @out.puts(
          "  - #{target.label}: #{target.dimensions.join(', ')} " \
          "prompt_sha256=#{target.prompt_sha256} schema_sha256=#{target.schema_sha256}"
        )
      end
      @out.puts "Rendered preflight: #{rendered_path}" if rendered_path
      @out.puts "Provider inference calls: 0"
    end

    def print_outcome(outcome)
      package = outcome.package
      metric_review_count = package.metrics.count { |m| m.review_flags.any? { |f| f.start_with?("REVIEW:") } }
      @out.puts "Result: #{package.status} / #{package.review_disposition}"
      @out.puts "Review-triggered metrics: #{metric_review_count}/#{package.metrics.length}"
      @out.puts "Assessment CSV: #{outcome.assessment_csv}"
      if outcome.regression_csv
        disagreements = outcome.comparisons.reject(&:exact_match)
        unless disagreements.empty?
          @out.puts "Regression disagreements:"
          disagreements.each do |comparison|
            delta = comparison.numeric_delta.nil? ? "" : " (delta #{format('%+g', comparison.numeric_delta)})"
            @out.puts "  - #{comparison.metric}: expected #{comparison.expected.inspect}, proposed #{comparison.proposed.inspect}#{delta}"
          end
        end
        @out.puts "Regression CSV: #{outcome.regression_csv}"
      end
    end
  end
end
