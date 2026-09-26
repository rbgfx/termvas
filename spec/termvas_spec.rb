# frozen_string_literal: true

require "stringio"

RSpec.describe Termvas do
  it "loads its encoders without rbgl" do
    root = File.expand_path("..", __dir__)
    pid = Process.spawn(Gem.ruby, "-Ilib", "-e", "require 'termvas'; exit 1 if defined?(RBGL::GUI::Backend)", chdir: root, out: File::NULL)
    _, status = Process.wait2(pid)

    expect(status.success?).to be(true)
  end

  it "has a version number" do
    expect(Termvas::VERSION).not_to be nil
  end

  it "encodes two rows as half blocks" do
    bytes = [255, 0, 0, 255, 0, 0, 255, 255].pack("C*")

    output = Termvas::Encoders::Blocks.encode(bytes, 1, 2)

    expect(output).to include("▀")
    expect(output).to include("38;2;255;0;0")
  end

  it "scales images to the available cell area" do
    bytes = Array.new(8 * 8 * 4, 255).pack("C*")

    expect(Termvas::Scaler.contain(8, 8, 3, 2)).to eq([3, 2])
    expect(Termvas::Scaler.nearest(bytes, 8, 8, 3, 2).drop(1)).to eq([3, 2])
    expect { Termvas::Scaler.nearest(bytes, 8, 8, 0, 2) }.to raise_error(ArgumentError)
    expect { Termvas::Scaler.nearest("", 8, 8, 3, 2) }.to raise_error(ArgumentError, /buffer size/)
  end

  it "applies contain when fit is provided as a string" do
    input = Struct.new(:winsize) do
      def read_nonblock(_size, exception:) = nil
      def tty? = false
    end.new([2, 4])
    output = StringIO.new
    backend = Termvas::Backend.new(8, 8, protocol: :blocks, fit: "contain", max_fps: nil,
                                   output: output, input: input, alt_screen: false)
    backend.set_pixels(Array.new(8 * 8 * 4, 255).pack("C*"))

    expect(backend.instance_variable_get(:@previous_size)).to eq([4, 4])
  ensure
    backend&.close
  end

  it "rejects an unknown fit mode" do
    expect do
      Termvas::Backend.new(1, 1, protocol: :blocks, fit: :stretch, output: StringIO.new, input: StringIO.new, alt_screen: false)
    end.to raise_error(ArgumentError, /fit/)
  end

  it "rejects a non-finite frame limit" do
    expect do
      Termvas::Backend.new(1, 1, protocol: :blocks, max_fps: Float::INFINITY,
                           output: StringIO.new, input: StringIO.new, alt_screen: false)
    end.to raise_error(ArgumentError, /max_fps/)
  end

  it "parses split arrow and mouse sequences" do
    parser = Termvas::InputParser.new

    expect(parser.feed("\e[")).to eq([])
    expect(parser.feed("A").first[:key]).to eq(:up)
    event = parser.feed("\e[<0;4;5M").first
    expect(event).to include(type: :mouse_press, x: 3, y: 4)
  end

  it "parses CSI modifiers, wheel events, and mouse motion" do
    parser = Termvas::InputParser.new

    expect(parser.feed("\e[1;5A").first).to include(type: :key_press, key: :up, modifiers: [:control])
    expect(parser.feed("\e[<64;4;5M").first).to include(type: :scroll, dx: 0.0, dy: 1.0, modifiers: [])
    expect(parser.feed("\e[<52;4;5M").first).to include(type: :mouse_move, button: 0, modifiers: [:shift, :control])
    expect(parser.feed("\e[3~").first[:key]).to eq(:delete)
  end

  it "continues reading keys after unsupported CSI sequences" do
    parser = Termvas::InputParser.new
    expect(parser.feed("\e[?")).to eq([])
    expect(parser.feed("25lx")).to eq([{ type: :key_press, key: :x, char: "x" }])
    expect(parser.feed("\e[<0;2;3Xy")).to eq([{ type: :key_press, key: :y, char: "y" }])
  end

  it "maps terminal mouse cells into the displayed image" do
    input = Class.new do
      def initialize
        @bytes = "\e[<0;2;1M\e[<0;5;1M"
      end
      def winsize = [2, 4]
      def read_nonblock(_size, exception:) = @bytes.tap { @bytes = nil }
      def tty? = false
    end.new
    output = StringIO.new
    backend = Termvas::Backend.new(4, 2, protocol: :blocks, max_fps: nil, output: output, input: input, alt_screen: false)
    backend.set_pixels([255, 255, 255, 255].pack("C4") * 8)

    expect(backend.poll_events).to eq([{ type: :mouse_press, x: 1.0, y: 0.0, button: 0, modifiers: [] }])
  ensure
    backend&.close
  end

  it "reads terminal size in columns and rows" do
    input = Struct.new(:winsize).new([24, 80])

    expect(Termvas::Terminal.new(input: input, alt_screen: false).size).to eq([80, 24])
  end

  it "estimates cell pixels and accepts environment overrides" do
    terminal = Termvas::Terminal.new(env: { "TERMVAS_CELL_WIDTH" => "10", "TERMVAS_CELL_HEIGHT" => "20" })
    expect(terminal.cell_size).to eq([10, 20])
    expect(Termvas::Terminal.new(env: { "TERMVAS_CELL_WIDTH" => "0" }).cell_size).to eq([8, 16])
  end

  it "presents changed frames through an rbgl window" do
    output = StringIO.new
    backend = Termvas::Backend.new(1, 2, protocol: :blocks, max_fps: nil, output: output, input: StringIO.new, alt_screen: false)
    window = RBGL::GUI::Window.new(width: 1, height: 2, backend: backend)
    first = [255, 0, 0, 255, 0, 0, 255, 255].pack("C*")
    second = [0, 255, 0, 255, 0, 0, 255, 255].pack("C*")
    window.set_pixels(first)
    window.set_pixels(first)
    window.set_pixels(second)
    expect(output.string.scan("▀").length).to eq(2)
    expect(output.string).to include("38;2;0;255;0")
  ensure
    window&.close
  end

  it "quantizes arbitrary colors before Sixel encoding" do
    pixels = [200, 30, 40, 255].pack("C*")
    expect(Termvas::Encoders::Sixel.encode(pixels, 1, 1)).to include("@")
  end

  it "uses tessel for median cut Sixel quantization" do
    bytes = [255, 0, 0, 255, 0, 255, 0, 255, 0, 0, 255, 255, 255, 255, 255, 255].pack("C*")
    output = Termvas::Encoders::Sixel.encode(bytes, 2, 2, quantize: :median_cut)

    expect(output).to include("#0;2;")
  end

  it "wraps Kitty output for tmux passthrough" do
    output = StringIO.new
    terminal = Termvas::Terminal.new(output: output, alt_screen: false, tmux: true)
    terminal.write("\e_Ga=T;payload\e\\")

    expect(output.string).to eq("\ePtmux;\e\e\e_Ga=T;payload\e\e\\\e\\")
  end

  it "enables and restores SGR mouse tracking for TTY input" do
    input = StringIO.new
    raw = false
    input.define_singleton_method(:tty?) { true }
    input.define_singleton_method(:raw!) { raw = true }
    input.define_singleton_method(:cooked!) { raw = false }
    output = StringIO.new
    terminal = Termvas::Terminal.new(input: input, output: output, alt_screen: false)
    terminal.open.close

    expect(raw).to be(false)
    expect(output.string).to include("\e[?1000h\e[?1003h\e[?1006h")
    expect(output.string).to include("\e[?1000l\e[?1003l\e[?1006l")
  end

  it "restores the terminal when input requests close" do
    output = StringIO.new
    backend = Termvas::Backend.new(1, 1, protocol: :blocks, output: output, input: StringIO.new("\x03"), alt_screen: true)

    backend.poll_events
    backend.close

    expect(output.string).to include("\e[?1049l")
    expect(output.string.scan("\e[?1049l").length).to eq(1)
  end

  it "throttles changed frames when max_fps is set" do
    output = StringIO.new
    backend = Termvas::Backend.new(1, 1, protocol: :blocks, max_fps: 1, output: output, input: StringIO.new, alt_screen: false)
    red = [255, 0, 0, 255].pack("C4")
    blue = [0, 0, 255, 255].pack("C4")

    backend.set_pixels(red)
    first = output.string
    backend.set_pixels(blue)

    expect(output.string).to eq(first)
  ensure
    backend&.close
  end

  it "reports a pending terminal resize once" do
    output = StringIO.new
    backend = Termvas::Backend.new(8, 4, protocol: :blocks, output: output, input: StringIO.new, alt_screen: false)
    backend.instance_variable_get(:@terminal).instance_variable_set(:@resized, true)

    expect(backend.poll_events).to eq([{ type: :resize, columns: 80, rows: 24 }])
    expect(backend.poll_events).to eq([])
  ensure
    backend&.close
  end
end
