![Build Status](https://github.com/kwerle/ruby_language_server/actions/workflows/test.yml/badge.svg)
![Coverage](https://img.shields.io/endpoint?url=https://raw.githubusercontent.com/kwerle/ruby_language_server/master/.github/badges/coverage.json)
# Overview

https://github.com/kwerle/ruby_language_server

The goal of this project is to provide a [language server](https://microsoft.github.io/language-server-protocol/) implementation for ruby in ruby.

# Status

Used day-to-day.

Help welcome.

# Features

* Definitions
* Completions
* Please see the [FAQ_ROADMAP.md](./FAQ_ROADMAP.md)

# Editor Integrations

You probably want to use one of the developed integrations:
* VSCode - https://github.com/kwerle/vscode_ruby_language_server
* Atom - https://github.com/kwerle/ide-ruby
* Theia - https://github.com/kwerle/theia_ruby_language_server

# Running

`ruby_language_server` will start the program and wait for activity using LSP's STDIO interface

# Development

Master branch is for releases.  Develop branch is for ongoing development.  Fork off develop;
I'll merge to master for releases.

Clone.  I love git [HubFlow](https://datasift.github.io/gitflow/).

Check out the [Makefile](Makefile).  You are going to want to do
`make guard` in one window and `make continuous_development` in another.

I use vscode with the "Ruby Language Server" extension install.  I edit the settings to use
the docker image local_ruby_language_server.  Quitting and restarting vscode to load the next
iteration.

# Similar

* [mtsmfm/language_server-ruby](https://github.com/mtsmfm/language_server-ruby)
* [castwide/solargraph](https://github.com/castwide/solargraph)

# Release instructions to self

For gem release
* bump version in [version.rb](lib/ruby_language_server/version.rb) file and [Gemfile.lock](Gemfile.lock)
* [CHANGELOG.txt](CHANGELOG.txt)
* merge to master, etc
* `make gem_release`

For docker release
* `make publish_cross_platform_image`

# Authors

* [Kurt Werle](kurt@CircleW.org)

# Contributors

* [Sebastian Delmont](sd@notso.net)
* [mattn](https://github.com/mattn)
* *Your name here!*
