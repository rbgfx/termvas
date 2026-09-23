# Termvas

> A terminal display backend for Ruby graphics.

[![Gem version](https://badge.fury.io/rb/termvas.svg)](https://rubygems.org/gems/termvas) [![Downloads](https://img.shields.io/gem/dt/termvas?label=downloads)](https://rubygems.org/gems/termvas) [![Ruby](https://img.shields.io/badge/ruby-%3E%3D3.1-CC342D?logo=ruby&logoColor=white)](https://www.ruby-lang.org/) [![CI](https://github.com/rbgfx/termvas/actions/workflows/main.yml/badge.svg)](https://github.com/rbgfx/termvas/actions/workflows/main.yml) [![License](https://img.shields.io/badge/license-MIT-750014.svg)](LICENSE.txt)

**[Features](#features) · [Installation](#installation) · [Requirements](#requirements) · [Quick start](#quick-start) · [Terminal notes](#terminal-notes) · [Development](#development) · [License](#license) · [Website](https://rbgfx.github.io/termvas/)**

---

Termvas displays RGBA frames in terminals and parses keyboard and mouse input for interactive applications.

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

## Requirements

- Ruby 3.1 or newer.
- Half-block output works in ANSI terminals; Kitty, iTerm2, and Sixel output require matching terminal support.

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
