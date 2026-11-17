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
* Document symbols
* Please see the [FAQ_ROADMAP.md](./FAQ_ROADMAP.md)

# Editor Integrations

You probably want to use one of the developed integrations:
* VSCode - https://github.com/kwerle/vscode_ruby_language_server
* Atom - https://github.com/kwerle/ide-ruby
* Theia - https://github.com/kwerle/theia_ruby_language_server

# Running

`ruby_language_server` will start the program and wait for activity using LSP's STDIO interface

The Docker image runs as an unprivileged user (UID 1000) and writes only to `/data`
(the SQLite database, and the ActiveRecord log when `LOG_LEVEL=DEBUG`). Set
`RUBY_LANGUAGE_SERVER_DATA_DIR` to use a different directory. So it can run locked down,
with the project mounted read-only:

```sh
docker run --rm -i --read-only --tmpfs /data:uid=1000,gid=1000 \
  --mount type=bind,source="$PWD",target=/project,readonly \
  kwerle/ruby_language_server
```

Docker mounts a plain `--tmpfs` as root-owned and not writable by other users, so the
`uid=1000,gid=1000` options are needed.

# Compatibility

The server stays backward compatible with the protocol clients use today. Removing or
changing a capability, a result's shape, or a default that clients rely on is a breaking
change. Breaking changes get a major version bump, announced in advance in
[CHANGELOG.txt](CHANGELOG.txt) and a GitHub issue. While the version is 0.x, the first
breaking change will be 1.0.0, so clients can treat any 0.x release as compatible.

Clients can read the running version from `serverInfo` in the `initialize` result, for example
`{ "name": "ruby_language_server", "version": "0.9.8" }`. Servers older than the release
that added it don't send `serverInfo`.

# Development

Master branch is for releases.  Develop branch is for ongoing development.  Fork off develop;
I'll merge to master for releases.

Clone.  I love git [HubFlow](https://datasift.github.io/gitflow/).

Check out the [Makefile](Makefile).  You are going to want to do
`make guard` in one window and `make continuous_development` in another.

I use vscode with the "Ruby Language Server" extension install.  I edit the settings to use
the docker image local_ruby_language_server.  Quitting and restarting vscode to load the next
iteration.

## Debugging the server

You can debug this checkout's code with breakpoints, through a client in an Extension
Development Host window. You need the [rdbg extension](https://marketplace.visualstudio.com/items?itemName=KoichiSasada.vscode-rdbg)
and a checkout of [vscode_ruby_language_server](https://github.com/kwerle/vscode_ruby_language_server).

1. Check out vscode_ruby_language_server next to this repo (`../vscode_ruby_language_server`).
2. Set breakpoints in `lib/`.
3. In this repo's window, Run and Debug "Debug server + client". It runs `make debug_server`,
   which starts the server in Docker with this checkout mounted (no image rebuild needed), LSP
   on TCP port 7658 and rdbg on 12345, and attaches the debugger. It also builds the client and
   opens an Extension Development Host window on this repo whose client connects to port 7658.
4. Open a Ruby file in that new window. Breakpoints hit once the client sends requests; until
   then the server just waits for the connection.

Notes:

* The project the client opens must be the one mounted at `/project`. Both default to this
  repo; to use another, run `make debug_server PROJECT=/path/to/project` and open that folder.
* The server accepts one connection per run and exits when it closes, so closing the client
  window ends the session. Run "Debug server + client" again to start over.
* The background scanner runs in a forked process, which isn't debugged
  (`RUBY_DEBUG_FORK_MODE=parent`).
* Rebuild the image (`make image`) only after changing the Gemfile.
* No Ruby is needed on the host. The rdbg extension checks `rdbg --version` even when attaching,
  so "Debug server" sets `rdbgPath` to `bin/rdbg`, which runs rdbg in the debug container.

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
