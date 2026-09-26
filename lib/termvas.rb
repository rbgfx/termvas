# frozen_string_literal: true

require "io/console"
require "zlib"

require_relative "termvas/version"

module Termvas
  class Error < StandardError; end

  module Scaler
    module_function

    def contain(width, height, columns, rows)
      raise ArgumentError, "dimensions must be positive" unless [width, height, columns, rows].all?(&:positive?)
      scale = [1.0, columns.to_f / width, (rows * 2).to_f / height].min
      [[(width * scale).floor, 1].max, [[((height * scale).floor / 2) * 2, 2].max, rows * 2].min]
    end

    def nearest(bytes, width, height, target_width, target_height)
      width, height, target_width, target_height = [width, height, target_width, target_height].map(&:to_i)
      raise ArgumentError, "dimensions must be positive" unless [width, height, target_width, target_height].all?(&:positive?)
      bytes = String.try_convert(bytes)
      raise ArgumentError, "pixel buffer must be a String" unless bytes
      expected_size = width * height * 4
      raise ArgumentError, "pixel buffer size mismatch" unless bytes.bytesize == expected_size
      return [bytes, width, height] if width == target_width && height == target_height
      output = "".b
      target_height.times do |y|
        source_y = y * height / target_height
        target_width.times do |x|
          source_x = x * width / target_width
          output << bytes.byteslice((source_y * width + source_x) * 4, 4)
        end
      end
      [output, target_width, target_height]
    end
  end

  module Encoders
    module Blocks
      module_function

      def encode(bytes, width, height, previous: nil)
        cells = "\e[H".dup
        (0...height).step(2) do |y|
          current = nil
          width.times do |x|
            top = bytes.byteslice((y * width + x) * 4, 4) || "\0\0\0\0".b
            bottom = bytes.byteslice(((y + 1) * width + x) * 4, 4) || "\0\0\0\0".b
            old_top = previous&.byteslice((y * width + x) * 4, 4)
            old_bottom = previous&.byteslice(((y + 1) * width + x) * 4, 4)
            if previous && old_top == top && old_bottom == bottom
              cells << "\e[C"
              next
            end
            if current != [top, bottom]
              cells << "\e[38;2;#{top.getbyte(0)};#{top.getbyte(1)};#{top.getbyte(2)}m"
              cells << "\e[48;2;#{bottom.getbyte(0)};#{bottom.getbyte(1)};#{bottom.getbyte(2)}m"
              current = [top, bottom]
            end
            cells << "▀"
          end
          cells << "\e[0m\r\n"
        end
        cells
      end
    end

    module Kitty
      module_function

      def encode(bytes, width, height, id: 1, compress: true)
        payload = compress ? Zlib::Deflate.deflate(bytes) : bytes
        encoded = [payload].pack("m0")
        chunks = encoded.scan(/.{1,4096}/m)
        chunks.each_with_index.map do |chunk, index|
          more = index == chunks.length - 1 ? 0 : 1
          control = "a=T,f=32,s=#{width},v=#{height},i=#{id},q=2,m=#{more}"
          control << ",o=z" if compress
          "\e_G#{control};#{chunk}\e\\"
        end.join
      end
    end

    module ITerm2
      module_function

      def encode(png_bytes, width:, height:)
        "\e[H\e]1337;File=inline=1;width=#{width}px;height=#{height}px;preserveAspectRatio=1:#{[png_bytes].pack("m0")}\a"
      end
    end

    module Sixel
      module_function

      def encode(bytes, width, height, palette: nil, quantize: :fixed)
        quantize = quantize.to_sym
        raise ArgumentError, "unsupported Sixel quantizer: #{quantize}" unless %i[fixed median_cut].include?(quantize)
        if quantize == :median_cut
          raise ArgumentError, "palette cannot be combined with median cut" if palette
          require "tessel"
          quantized, palette = Tessel::Quantize.quantize(Tessel::Image.from_rgba(width, height, bytes), colors: 256)
        end
        fixed_palette = palette.nil?
        palette ||= default_palette
        indices = if quantized
          quantized.bytes
        else
          bytes.bytes.each_slice(4).map do |r, g, b, _a|
          if fixed_palette
            red = (r * 5.0 / 255).round
            green = (g * 5.0 / 255).round
            blue = (b * 5.0 / 255).round
            cube = red * 36 + green * 6 + blue
            gray = ((r + g + b) / 3.0 * 39 / 255).round
            cube_color = palette[cube]
            gray_color = palette[216 + gray]
            cube_distance = [r, g, b].zip(cube_color).sum { |a, c| (a - c)**2 }
            gray_distance = [r, g, b].zip(gray_color).sum { |a, c| (a - c)**2 }
            cube_distance <= gray_distance ? cube : 216 + gray
          else
            palette.each_index.min_by { |index| [r, g, b].zip(palette[index]).sum { |a, c| (a - c)**2 } }
          end
          end
        end.pack("C*")
        output = +"\ePq"
        palette.each_with_index { |(r, g, b), index| output << "##{index};2;#{r * 100 / 255};#{g * 100 / 255};#{b * 100 / 255}" }
        (0...height).step(6) do |band|
          palette.each_index do |index|
            output << "##{index}"
            x = 0
            while x < width
              run = 0
              while x + run < width && sixel_column(indices, width, x + run, band, index) == sixel_column(indices, width, x, band, index)
                run += 1
              end
              column = sixel_column(indices, width, x, band, index)
              if run > 3
                output << "!#{run}#{(63 + column).chr}"
              else
                output << (63 + column).chr * run
              end
              x += run
            end
            output << "$"
          end
          output << "-" if band + 6 < height
        end
        output << "\e\\"
      end

      def sixel_column(indices, width, x, y, index)
        value = 0
        6.times do |offset|
          next unless indices.getbyte((y + offset) * width + x) == index
          value |= 1 << offset
        end
        value
      end
      private_class_method :sixel_column

      def default_palette
        6.times.flat_map { |r| 6.times.flat_map { |g| 6.times.map { |b| [r * 51, g * 51, b * 51] } } } + Array.new(40) { |index| value = index * 255 / 39; [value, value, value] }
      end
      private_class_method :default_palette
    end
  end

  class InputParser
    CSI_KEYS = { "A" => :up, "B" => :down, "C" => :right, "D" => :left, "H" => :home, "F" => :end }.freeze
    CSI_TILDE_KEYS = { 1 => :home, 2 => :insert, 3 => :delete, 4 => :end, 5 => :page_up, 6 => :page_down }.freeze

    def initialize
      @buffer = "".b
    end

    def feed(bytes)
      @buffer << bytes
      events = []
      loop do
        if @buffer.start_with?("\e[")
          sequence = @buffer.match(/\A\e\[[0-?]*[ -\/]*[@-~]/)
          break unless sequence
          unless sequence[0].match?(/\A\e\[<\d+;\d+;\d+[Mm]\z|\A\e\[[0-9;]*[A-Za-z~]\z/)
            @buffer = @buffer.byteslice(sequence[0].bytesize..).to_s.b
            next
          end
        end
        if @buffer.start_with?("\e[<")
          match = @buffer.match(/\A\e\[<([0-9]+);([0-9]+);([0-9]+)([Mm])/
          )
          break unless match
          @buffer = @buffer.byteslice(match[0].bytesize..).to_s.b
          button = match[1].to_i
          event = { x: match[2].to_i - 1, y: match[3].to_i - 1, modifiers: mouse_modifiers(button) }
          if button & 64 != 0
            event.merge!(type: :scroll, dx: 0.0, dy: (button & 1).zero? ? 1.0 : -1.0)
          elsif button & 32 != 0
            event.merge!(type: :mouse_move, button: button & 3)
          else
            event.merge!(type: match[4] == "M" ? :mouse_press : :mouse_release, button: button & 3)
          end
          events << event
        elsif @buffer.start_with?("\e[")
          match = @buffer.match(/\A\e\[([0-9;]*)([A-Za-z~])/)
          break unless match
          @buffer = @buffer.byteslice(match[0].bytesize..).to_s.b
          parameters = match[1].split(";").reject(&:empty?).map(&:to_i)
          key = if match[2] == "~"
            CSI_TILDE_KEYS[parameters.first] || :unknown
          elsif match[2] == "Z"
            :tab
          else
            CSI_KEYS[match[2]] || match[2].to_sym
          end
          event = { type: :key_press, key: key }
          modifiers = match[2] == "Z" ? [:shift] : csi_modifiers(parameters[1] || 1)
          event[:modifiers] = modifiers unless modifiers.empty?
          events << event
        elsif @buffer.start_with?("\eO")
          break if @buffer.bytesize < 3
          key = { "P" => :f1, "Q" => :f2, "R" => :f3, "S" => :f4 }[@buffer.getbyte(2).chr] || @buffer.getbyte(2).chr.to_sym
          @buffer = @buffer.byteslice(3..).to_s.b
          events << { type: :key_press, key: key }
        elsif @buffer.start_with?("\e")
          break if @buffer.bytesize < 2
          @buffer = @buffer.byteslice(1..).to_s.b
          events << { type: :key_press, key: :escape }
        else
          byte = @buffer.getbyte(0)
          break unless byte
          @buffer = @buffer.byteslice(1..).to_s.b
          key = case byte
          when 3 then :close
          when 9 then :tab
          when 13 then :enter
          when 127 then :backspace
          when 32..126 then byte.chr.to_sym
          else next
          end
          events << { type: :key_press, key: key, char: byte.chr }
        end
      end
      events
    end

    def flush
      return [] if @buffer.empty?
      @buffer = "".b
      [{ type: :key_press, key: :escape }]
    end

    private

    def csi_modifiers(value)
      modifier_bits(value.to_i - 1)
    end

    def mouse_modifiers(button)
      modifier_bits((button >> 2) & 7)
    end

    def modifier_bits(value)
      [[:shift, 1], [:alt, 2], [:control, 4]].filter_map { |name, bit| name if value & bit != 0 }
    end
  end

  class Detector
    def self.protocol(env = ENV)
      forced = env["TERMVAS_PROTOCOL"]
      return forced.to_sym if forced
      return :kitty if env["TERM"] == "xterm-kitty" || env["KITTY_WINDOW_ID"] || %w[WezTerm ghostty].include?(env["TERM_PROGRAM"])
      return :iterm2 if env["TERM_PROGRAM"] == "iTerm.app"
      :blocks
    end
  end

  class Terminal
    attr_reader :input, :output

    def initialize(input: $stdin, output: $stdout, alt_screen: true, tmux: false, env: ENV)
      @input = input
      @output = output
      @alt_screen = alt_screen
      @env = env
      @closed = false
      @opened = false
      @raw = false
      @tmux = tmux
      @resized = false
      @signal_handlers = {}
    end

    def size
      rows, columns = @input.winsize
      return [columns, rows] if rows.to_i.positive? && columns.to_i.positive?

      fallback_size
    rescue Errno::ENODEV, Errno::ENOTTY, IOError, NoMethodError
      fallback_size
    end

    def cell_size
      [environment_dimension("TERMVAS_CELL_WIDTH", 8), environment_dimension("TERMVAS_CELL_HEIGHT", 16)]
    end

    def open
      return self if @opened
      @opened = true
      @mouse_tracking = false
      if @input.respond_to?(:tty?) && @input.tty?
        if @input.respond_to?(:raw!)
          @input.raw!
          @raw = true
        end
        @output.write("\e[?1000h\e[?1003h\e[?1006h")
        @mouse_tracking = true
      end
      install_signal_handlers
      @output.write("\e[?1049h") if @alt_screen
      @output.write("\e[?25l")
      @output.flush
      at_exit { restore }
      self
    end

    def write(value)
      value = "\ePtmux;\e#{value.gsub("\e", "\e\e")}\e\\" if @tmux
      @output.write(value)
      @output.flush
    end

    def restore
      return if @closed
      @closed = true
      restore_signal_handlers
      begin
        @output.write("\e[?25h\e[?1000l\e[?1003l\e[?1006l") if @mouse_tracking
        @output.write("\e[?25h") unless @mouse_tracking
        @output.write("\e[?1049l") if @alt_screen
        @output.flush
      ensure
        @input.cooked! if @raw
        @raw = false
      end
    end

    alias close restore

    def resized?
      resized = @resized
      @resized = false
      resized
    end

    private

    def install_signal_handlers
      handlers = { "WINCH" => proc { @resized = true }, "INT" => proc { restore }, "TERM" => proc { restore } }
      exit_codes = { "INT" => 130, "TERM" => 143 }
      handlers.each do |signal, handler|
        previous = nil
        previous = Signal.trap(signal) do |number|
          handler.call
          previous.call(number) if previous.respond_to?(:call)
          exit(exit_codes[signal]) if exit_codes.key?(signal)
        end
        @signal_handlers[signal] = previous
      end
    rescue ArgumentError, Errno::EINVAL
      restore_signal_handlers
    end

    def restore_signal_handlers
      @signal_handlers.each { |signal, previous| Signal.trap(signal, previous) }
      @signal_handlers.clear
    rescue ArgumentError, Errno::EINVAL
      @signal_handlers.clear
    end

    def fallback_size
      columns = Integer(@env.fetch("COLUMNS", 80))
      rows = Integer(@env.fetch("LINES", 24))
      [columns.positive? ? columns : 80, rows.positive? ? rows : 24]
    rescue ArgumentError, TypeError
      [80, 24]
    end

    def environment_dimension(name, fallback)
      value = Integer(@env.fetch(name, fallback))
      value.positive? ? value : fallback
    rescue ArgumentError, TypeError
      fallback
    end
  end

end
