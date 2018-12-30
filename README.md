# Overview

https://github.com/kwerle/ruby_language_server

The goal of this project is to provide a [language server](https://microsoft.github.io/language-server-protocol/) implementation for ruby in ruby.

# Status

Beta.  It does some stuff.  Pretty stable.  Used day-to-day.

Help wanted.

# Features

* Definitions
* Completions
* Lint - thanks to [RuboCop](https://github.com/bbatsov/rubocop)
* Please see the [FAQ_ROADMAP.md](./FAQ_ROADMAP.md)

# Editor Integrations

You probably want to use one of the developed integrations:
* Atom - https://github.com/kwerle/ide-ruby
* Theia - https://github.com/kwerle/theia_ruby_language_server

# Running

`ruby_language_server` will start the program and wait for activity using LSP's STDIO interface

# Development

Clone.  I love git [HubFlow](https://datasift.github.io/gitflow/).

Check out the [Makefile](Makefile).  You are going to want to do
`make guard` in one window and `make continuous_development` in another.

* In Atom: install the ide-ruby.  
* Settings > Packages > ide-ruby > Image Name > local_ruby_language_server
* CMD-ALT-CTRL-l (that's an L) will reload the window
* CMD-ALT-i will show debugging info

Write tests and guard will run them.  Make changes and reload the window.  Test them out.

# Similar

* [mtsmfm/language_server-ruby](https://github.com/mtsmfm/language_server-ruby)
* [castwide/solargraph](https://github.com/castwide/solargraph)

# Authors

* [Kurt Werle](kurt@CircleW.org)

# Contributors

* *Your name here!*
