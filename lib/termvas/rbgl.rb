# frozen_string_literal: true

require "rbgl"
require "termvas"

module Termvas
  class Backend < RBGL::GUI::Backend
    attr_reader :width, :height, :protocol

    def initialize(width, height, protocol: :auto, fit: :contain, max_fps: 30, quantize: :fixed, tmux: :auto, output: $stdout, input: $stdin, alt_screen: true, **_options)
      super(Integer(width), Integer(height), "Termvas")
      @protocol = protocol == :auto ? Detector.protocol : protocol.to_sym
      @quantize = quantize.to_sym
      tmux = ENV.key?("TMUX") if tmux == :auto
      tmux &&= %i[kitty sixel].include?(@protocol)
      raise ArgumentError, "unsupported terminal protocol: #{@protocol}" unless %i[blocks kitty iterm2 sixel].include?(@protocol)
      @fit = fit.to_sym
      raise ArgumentError, "fit must be :contain or :none" unless %i[contain none].include?(@fit)
      @max_fps = max_fps.nil? ? nil : Float(max_fps)
      raise ArgumentError, "max_fps must be positive and finite" if @max_fps && (!@max_fps.positive? || !@max_fps.finite?)
      @terminal = Terminal.new(input: input, output: output, alt_screen: alt_screen, tmux: tmux)
      @output = output
      @input = input
      @closed = false
      @previous = nil
      @parser = InputParser.new
      @last_frame_at = nil
      @terminal.open
    end

    def open = (@terminal.open; self)

    def present(framebuffer)
      pixels = framebuffer.respond_to?(:to_rgba_bytes) ? framebuffer.to_rgba_bytes : framebuffer
      set_pixels(pixels, framebuffer.width, framebuffer.height)
    end

    def set_pixels(bytes, width = @width, height = @height)
      bytes = validate_rgba_buffer(bytes, width, height)
      width, height = Integer(width), Integer(height)
      if @fit == :contain
        columns, rows = @terminal.size
        target_width, target_height = Scaler.contain(width, height, columns, rows)
        bytes, width, height = Scaler.nearest(bytes, width, height, target_width, target_height)
      end
      @previous = nil if @previous_size && @previous_size != [width, height]
      return if @previous == bytes
      now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      return if @last_frame_at && @max_fps && now - @last_frame_at < 1.0 / @max_fps

      encoded = case @protocol
      when :kitty then Encoders::Kitty.encode(bytes, width, height)
      when :iterm2
        require "tessel"
        Encoders::ITerm2.encode(Tessel::PNG.encode(Tessel::Image.from_rgba(width, height, bytes)), width: width, height: height)
      when :sixel then Encoders::Sixel.encode(bytes, width, height, quantize: @quantize)
      else Encoders::Blocks.encode(bytes, width, height, previous: @previous)
      end
      @terminal.write(encoded)
      @previous = bytes.dup
      @previous_size = [width, height]
      @last_frame_at = now
    end

    def poll_events
      return [] unless @input.respond_to?(:read_nonblock)
      resize = if @terminal.resized?
        columns, rows = @terminal.size
        { type: :resize, columns: columns, rows: rows }
      end
      bytes = @input.read_nonblock(4096, exception: false)
      events = bytes.is_a?(String) ? @parser.feed(bytes) : []
      events = map_mouse_events(events)
      events.unshift(resize) if resize
      if events.any? { |event| event[:key] == :close }
        @closed = true
        @terminal.close
      end
      events
    rescue IOError, Errno::EIO
      []
    end

    def should_close?
      @closed
    end

    def close
      return if @closed
      @closed = true
      @terminal.close
    end

    private

    def map_mouse_events(events)
      return events unless @previous_size

      columns, rows = @terminal.size
      display_width = [@previous_size[0], columns].min
      display_height = [@previous_size[1], rows * 2].min
      events.filter_map do |event|
        next event unless event.key?(:x) && event.key?(:y)

        x = event[:x] * display_width.to_f / columns
        y = event[:y] * display_height.to_f / rows
        next if x >= display_width || y >= display_height

        event.merge(x: x, y: y)
      end
    end
  end
end
