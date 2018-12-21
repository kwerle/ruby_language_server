# Overview

https://github.com/kwerle/ruby_language_server

The goal of this project is to provide a [language server](https://code.visualstudio.com/blogs/2016/06/27/common-language-protocol) implementation for ruby in ruby.

# Status

Alpha.  Totally feature incomplete.  Mostly stable.  Used day-to-day.

Help wanted.

# Features

* Definitions (somewhat) - thanks to [ripper-tags](https://github.com/tmm1/ripper-tags)
* Completions (a little)
* Lint - thanks to [RuboCop](https://github.com/bbatsov/rubocop)
* Please see the [FAQ_ROADMAP.md](./FAQ_ROADMAP.md)

# Requirements

* [Docker](http://docker.com/)
* I use [Atom](https://atom.io/) as a client - I'm hoping others work
* I use OS X - I'm hoping others work

# Running

The expectation is that you will be running this using the Atom package ide-ruby.  In general this expects to be launched like

`docker run -v PROJECT_ROOT:/project -w /project ruby_language_server`

*You must mount the project directory to /project*

# Development

Clone.  I love git [HubFlow](https://datasift.github.io/gitflow/).

Check out the [Makefile](Makefile).  You are going to want to do
`make guard` and `make continuous_development`.

* In Atom: install the ide-ruby.  
* Settings > Packages > ide-ruby > Image Name > local_ruby_language_server
* CMD-ALT-CTRL-l (that's an L) will reload the window
* CMD-ALT-i will show debugging info

Write tests and guard will run them.  Make changes and reload the window.  Test them out.

# Similar

* [language_server-ruby](https://github.com/mtsmfm/language_server-ruby)

# Authors

* [Kurt Werle](kurt@CircleW.org)

# Contributors

* *Your name here!*
