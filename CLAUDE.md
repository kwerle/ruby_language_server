# ruby_language_server

A Language Server Protocol server for Ruby, written in Ruby. It parses the project with
Prism, stores what it finds in SQLite through ActiveRecord, and answers definition, hover,
completion and document-symbol requests from that index. It runs in Docker, and the
editor clients (VS Code, Atom, Theia) start the `kwerle/ruby_language_server` image.

## Running Ruby: always in Docker

Never use the host's Ruby. Everything runs in the `ruby_language_server` image, with the
checkout mounted:

- `make test`: specs and rubocop, the same as CI
- `make rubocop`, `make coverage`, `make audit` (bundle-audit)
- `make shell` / `make console`: an interactive shell or console in the container
- `make image`: rebuild the image (the other targets do this first)
- One-off commands: `docker run --rm --user root -v $PWD:/tmp/src -w /tmp/src ruby_language_server sh -c '...'`
- One spec file: `... sh -c 'bundle exec ruby -Ispec spec/lib/ruby_language_server/hover_spec.rb'`

In production the project being edited is mounted read-only at `/project`, and the server
writes only to `/data`.

## The database is reset every startup

The SQLite index is rebuilt from scratch each time the server starts. The server runs in a
fresh container, with `/data` on a tmpfs, so no database survives from one run to the next.

- Schema changes need no migrations and no handling for older databases. Edit
  `lib/db/schema.rb` and that's it.
- Don't report "existing databases won't get the new columns" or similar upgrade problems.
  They can't happen.

## How it fits together

- `exe/ruby_language_server` → `Application` → `IO` (JSON-RPC over stdio, or TCP when
  `LSP_PORT` is set) → `Server`.
- `Server` has one `on_<method>` handler per LSP method (`textDocument/hover` →
  `on_textDocument_hover`). Advertise a capability in `on_initialize` only if it has a handler.
- `ProjectManager` does the work: finding definitions, hover, completion, file changes. On
  initialize it forks a background process (`scan_all_project_files`) that indexes the
  project's files, then Ruby core (`CoreIndex`). Specs and vendor are skipped.
- `CodeFile` is one file's text. It re-parses lazily (`refresh_scopes_if_needed`), at most once
  a second while you type within a line.
- `ScopeParser` / `PrismProcessor` walk the Prism AST into `ScopeData::Scope` rows (root,
  module, class, method and block, with paths like `Foo::Bar#baz`) and `ScopeData::Variable`
  rows. Common DSLs (`attr_*`, rspec, rake, rails associations) are in
  `scope_parser_commands/`.
- `CoreIndex` loads the RBS core signatures (String, Array, Kernel, ...) as scopes with
  `signature` and `documentation`, and **no code file or lines**. The editor can't open the
  `.rbs` files in the container, so go-to-definition returns only records that have a
  `code_file`. Hover and completion still use core. Records with a file come first, so the
  project's own definitions win.
- `LineContext` splits the line at the cursor into receiver words (`Foo::Bar.baz` →
  `['Foo', 'Bar', 'baz']`). LSP positions are 0-based and count UTF-16 code units, while
  stored lines are 1-based.
- `Completion` ranks candidates with a SQLite `LEVENSHTEIN` extension (built into the image)
  and FuzzyMatch. `Hover` renders markdown from a record.

## Environment variables

- `RUBY_LANGUAGE_SERVER_PROJECT_ROOT`: the project root in the container. The image sets
  `/project/`, and without it the client's `rootPath` is used.
- `RUBY_LANGUAGE_SERVER_DATA_DIR`: where the database and logs go (default `/data`)
- `RUBY_LANGUAGE_SERVER_REPARSE_INTERVAL`: re-parse throttle in seconds (the specs use `0`)
- `RUBY_LANGUAGE_SERVER_CORE_INDEX=false`: skip loading Ruby core (the specs set this)
- `LOG_LEVEL`: default `error`. `DEBUG` also writes an ActiveRecord log to the data dir.
- `LSP_PORT`: listen on TCP instead of stdio (used by `make debug_server`)

## Specs

- Minitest with spec syntax, in `spec/lib/ruby_language_server/`, one file per class.
  `spec/test_helper.rb` empties every table before each test.
- The project scan forks, so specs shouldn't depend on it. To test against core, call
  `CoreIndex.load!(only: %w[String ...])`, because loading all of core takes about 2s.
- Rubocop must pass. The config is in `.rubocop.yml`, and line length isn't checked.

## Workflow

- `develop` is the default branch for work. `master` is for releases (HubFlow: release
  branches like `release/0.9.9`, merged to both). Feature branches are named `<issue>-<slug>`
  and are squash-merged into `develop` through a PR. The branch is deleted after merging.
- Plans go in `plans/<issue>-<slug>.md`. That directory is gitignored.
- Add user-facing changes to `CHANGELOG.txt` under `#### Unreleased`, in plain sentences.
- Versions are in `lib/ruby_language_server/version.rb`. A `v*.*.*` tag on `master` runs
  `.github/workflows/release.yml`, which pushes the Docker image (`:latest` and `:<version>`).
  The VS Code client runs `:latest`, so tagging releases to every user.
- Compatibility: removing or changing a capability, a result's shape, or a default that
  clients rely on is a breaking change and needs a major bump (see README "Compatibility").
- `FAQ_ROADMAP.md` lists planned work. Larger ideas get GitHub issues.
