<h1 align="center">Termvas</h1>

<p align="center">A terminal display backend for Ruby graphics.</p>

<p align="center">
  <a href="https://rubygems.org/gems/termvas"><img src="https://badge.fury.io/rb/termvas.svg" alt="Gem Version"></a>
  <a href="https://rubygems.org/gems/termvas"><img src="https://img.shields.io/gem/dt/termvas?label=downloads" alt="Downloads"></a>
  <a href="https://www.ruby-lang.org/"><img src="https://img.shields.io/badge/ruby-%3E%3D3.1-CC342D?logo=ruby&amp;logoColor=white" alt="Ruby Version"></a>
  <a href="LICENSE.txt"><img src="https://img.shields.io/badge/license-MIT-750014.svg" alt="License"></a>
</p>

[Features](#features) · [Installation](#installation) · [Quick Start](#quick-start) · [Terminal Notes](#terminal-notes)

***

Termvas presents RGBA frames in terminals through half blocks, Kitty, iTerm2, or Sixel output. It also parses keyboard and mouse input for interactive applications.

## Features

- Automatic protocol detection with a manual override.
- Half-block output that works in ordinary ANSI terminals.
- Kitty, iTerm2, and Sixel image protocols.
- Image viewing and frame-sequence playback commands.
- Split-safe CSI, keyboard, wheel, and SGR mouse input parsing.
- Nearest-neighbor fitting for frames larger than the terminal.
- Idempotent alternate-screen and cursor restoration.

## Installation

Add Termvas to your Gemfile:

~~~ruby
gem "termvas"

# For Termvas::Backend and the `termvas view` / `play` commands:
gem "rbgl"
gem "tessel", ">= 0.2.0"
~~~

Then run:

~~~sh
bundle install
~~~

Or install the released gem:

~~~sh
gem install termvas
~~~

### Requirements

- Ruby 3.1 or newer.
- Half-block output works in ANSI terminals; Kitty, iTerm2, and Sixel output require matching terminal support.
- `require "termvas"` and `termvas doctor` need no extra gems. The RBGL backend needs `rbgl`; `view` / `play`, iTerm2 output, and median-cut Sixel quantization also need `tessel`.

## Quick Start

Inspect the current terminal and display an image:

~~~sh
termvas doctor
termvas view image.png
termvas play frames/*.png --fps 10
~~~

Use the backend from Ruby:

~~~ruby
require "termvas/rbgl"

backend = Termvas::Backend.new(320, 180, protocol: :blocks)
backend.set_pixels(rgba_bytes, 320, 180)
backend.close
~~~

The backend expects top-down RGBA8 bytes. Set
<code>TERMVAS_PROTOCOL</code> to force a protocol.
For Sixel output, pass <code>quantize: :median_cut</code> to the backend to use
Tessel's shared quantizer; the default uses the fixed palette.

The encoders, protocol detection, input parser, and terminal sizing utilities
load with <code>require "termvas"</code> alone. The optional RBGL backend is
available from <code>require "termvas/rbgl"</code>.

<code>Termvas::Terminal#size</code> returns <code>[columns, rows]</code>.
<code>#cell_size</code> returns estimated pixel dimensions as
<code>[width, height]</code> (8 × 16 by default). Set
<code>TERMVAS_CELL_WIDTH</code> and <code>TERMVAS_CELL_HEIGHT</code> to tune the
estimate; sizing does not query the terminal.

## Terminal notes

<code>fit: :contain</code> is the default and reduces oversized frames to the
terminal cell area. Use <code>fit: :none</code> to keep the source size.

Inside tmux, Kitty and Sixel output uses DCS passthrough and requires
<code>allow-passthrough on</code> in tmux.

## SSH

Remote environment variables may not identify the local terminal. Select a
protocol supported by that terminal explicitly, and lower the frame rate on
slow links:

~~~sh
termvas play frames/*.png --protocol blocks --fps 5
~~~

For the Ruby backend, set <code>protocol: :blocks</code> and a lower
<code>max_fps</code> value.

## Development

~~~sh
bundle install
bundle exec rake verify
~~~

See [docs/keys.md](docs/keys.md) for the input event mapping.

## Contributing

Bug reports and pull requests are welcome at [rbgfx/termvas](https://github.com/rbgfx/termvas).

## License

[MIT](LICENSE.txt)
