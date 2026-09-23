# Termvas

[![Gem version](https://badge.fury.io/rb/termvas.svg)](https://rubygems.org/gems/termvas)
[![Downloads](https://img.shields.io/gem/dt/termvas?label=downloads)](https://rubygems.org/gems/termvas)
[![CI](https://github.com/rbgfx/termvas/actions/workflows/main.yml/badge.svg)](https://github.com/rbgfx/termvas/actions/workflows/main.yml)
[![Ruby](https://img.shields.io/badge/ruby-%3E%3D3.1-CC342D?logo=ruby&logoColor=white)](https://www.ruby-lang.org/)
[![License](https://img.shields.io/badge/license-MIT-750014.svg)](LICENSE.txt)

> A terminal display backend for Ruby graphics.

Termvas presents RGBA frames in terminals through half blocks, Kitty, iTerm2,
or Sixel output. It also parses keyboard and mouse input for interactive
applications.

**[Features](#features) · [Installation](#installation) · [Quick start](#quick-start) · [Terminal notes](#terminal-notes) · [Development](#development)**

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
~~~

Then run:

~~~sh
bundle install
~~~

Or install the released gem:

~~~sh
gem install termvas
~~~

## Quick start

Inspect the current terminal and display an image:

~~~sh
termvas doctor
termvas view image.png
termvas play frames/*.png --fps 10
~~~

Use the backend from Ruby:

~~~ruby
require "termvas"

backend = Termvas::Backend.new(320, 180, protocol: :blocks)
backend.set_pixels(rgba_bytes, 320, 180)
backend.close
~~~

The backend expects top-down RGBA8 bytes. Set
<code>TERMVAS_PROTOCOL</code> to force a protocol.

## Terminal notes

<code>fit: :contain</code> is the default and reduces oversized frames to the
terminal cell area. Use <code>fit: :none</code> to keep the source size.

Inside tmux, Kitty and Sixel output uses DCS passthrough and requires
<code>allow-passthrough on</code> in tmux.

## Development

~~~sh
bundle install
bundle exec rake verify
~~~

See [docs/keys.md](docs/keys.md) for the input event mapping.

## License

[MIT](LICENSE.txt)
