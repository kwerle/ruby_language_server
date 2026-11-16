![Build Status](https://github.com/kwerle/ruby_language_server/actions/workflows/test.yml/badge.svg)
![Coverage](https://img.shields.io/endpoint?url=https://raw.githubusercontent.com/kwerle/ruby_language_server/copilot/add-test-coverage-badge/.github/badges/coverage.json)
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

Images are published only by the [release workflow](.github/workflows/release.yml), when a
`v*` tag is pushed for a commit on master. Never push `kwerle/ruby_language_server` from a
laptop: the VS Code client runs `:latest` on every start.

* bump version in [version.rb](lib/ruby_language_server/version.rb) file and [Gemfile.lock](Gemfile.lock)
* [CHANGELOG.txt](CHANGELOG.txt)
* `git flow release start 0.9.8` ... `git flow release finish 0.9.8`
  (with `git config gitflow.prefix.versiontag v`, this tags master as `v0.9.8`)
* `git push origin master develop v0.9.8`
* CI checks the tag matches `version.rb`, builds and pushes `:latest` and `:0.9.8`
  for amd64 and arm64, signs the image with cosign, and creates the GitHub release.
* The gem is still released by hand: `make gem_release`

To verify a published image:

```sh
cosign verify kwerle/ruby_language_server:latest \
  --certificate-identity-regexp '^https://github.com/kwerle/ruby_language_server/.github/workflows/release.yml@refs/tags/v' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com
```

# Authors

* [Kurt Werle](kurt@CircleW.org)

# Contributors

* [Sebastian Delmont](sd@notso.net)
* [mattn](https://github.com/mattn)
* *Your name here!*
