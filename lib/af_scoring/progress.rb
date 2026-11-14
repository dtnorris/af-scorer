# frozen_string_literal: true

module AFScoring
  class Progress
    SPINNER_FRAMES = %w[⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏].freeze

    def initialize(io: $stdout, verbose: false, tty: nil, tick_interval: 0.1, label_interval: 3.0)
      @io = io
      @verbose = verbose
      @tty = tty.nil? ? (io.respond_to?(:tty?) && io.tty?) : tty
      @tick_interval = tick_interval
      @label_interval = label_interval
    end

    def start(adventure_id:, group_name:, dimensions:, source_file:, start_page:, end_page:, provider:, model:)
      Session.new(
        io: @io,
        verbose: @verbose,
        tty: @tty,
        tick_interval: @tick_interval,
        label_interval: @label_interval,
        adventure_id: adventure_id,
        group_name: group_name,
        dimensions: dimensions,
        source_file: source_file,
        start_page: start_page,
        end_page: end_page,
        provider: provider,
        model: model
      )
    end

    def validating(adventure_id:, metric_count:)
      return unless @verbose

      @io.puts "[#{adventure_id}] → validating #{metric_count} assessments"
    end

    class Session
      def initialize(io:, verbose:, tty:, tick_interval:, label_interval:, adventure_id:, group_name:, dimensions:,
                     source_file:, start_page:, end_page:, provider:, model:)
        @io = io
        @verbose = verbose
        @tty = tty
        @tick_interval = tick_interval
        @label_interval = label_interval
        @adventure_id = adventure_id
        @group_name = group_name
        @dimensions = dimensions
        @source_file = source_file
        @start_page = start_page
        @end_page = end_page
        @provider = provider
        @model = model
      end

      def waiting
        @started_at = monotonic_now
        announce_request
        start_animation if @tty

        result = yield
        elapsed = elapsed_time
        finish_animation
        @io.puts "  ← response received [#{format_elapsed(elapsed)}]" if @verbose
        result
      ensure
        finish_animation
      end

      def normalizing
        @io.puts "  → normalizing structured response" if @verbose
      end

      def complete(metric_count)
        elapsed = elapsed_time
        if @verbose
          @io.puts "  ✓ #{@group_name} complete [#{format_elapsed(elapsed)}]"
        else
          @io.puts "[#{@adventure_id}] #{@group_name} ✓ #{format_elapsed(elapsed)} · #{metric_count} dimensions scored"
        end
      end

      private

      def announce_request
        if @verbose
          @io.puts "[#{@adventure_id}] Scoring #{@group_name}"
          @io.puts "  → source: #{File.basename(@source_file)}, pages #{@start_page}–#{@end_page}"
          @io.puts "  → dimensions: #{@dimensions.join(', ')}"
          @io.puts "  → provider: #{@provider}"
          @io.puts "  → model: #{@model}"
          @io.puts "  → sending #{@provider} request"
        elsif !@tty
          @io.puts "[#{@adventure_id}] Scoring #{@group_name} · request dimensions: #{@dimensions.join(' / ')}"
        end
        @io.puts "  … waiting for #{@provider}" if @verbose && !@tty
      end

      def start_animation
        @stop_animation = false
        @animation_thread = Thread.new do
          frame_index = 0
          until @stop_animation
            elapsed = elapsed_time
            label_index = (elapsed / @label_interval).floor % @dimensions.length
            line = if @verbose
                     "  … waiting for #{@provider} #{SPINNER_FRAMES[frame_index % SPINNER_FRAMES.length]} #{format_waiting_elapsed(elapsed)} · #{@dimensions[label_index]}"
                   else
                     "[#{@adventure_id}] #{@group_name} #{SPINNER_FRAMES[frame_index % SPINNER_FRAMES.length]} #{format_waiting_elapsed(elapsed)} · #{@dimensions[label_index]}"
                   end
            @io.print "\r\e[2K#{line}"
            @io.flush if @io.respond_to?(:flush)
            frame_index += 1
            sleep @tick_interval
          end
        end
      end

      def finish_animation
        return unless @animation_thread

        @stop_animation = true
        @animation_thread.join
        @animation_thread = nil
        @io.print "\r\e[2K"
        @io.flush if @io.respond_to?(:flush)
      end

      def monotonic_now
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end

      def elapsed_time
        monotonic_now - (@started_at || monotonic_now)
      end

      def format_waiting_elapsed(seconds)
        format("%3ds", seconds.floor)
      end

      def format_elapsed(seconds)
        format("%.1fs", seconds)
      end
    end
  end
end
