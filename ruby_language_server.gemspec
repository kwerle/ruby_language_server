# frozen_string_literal: true

lib = File.expand_path('lib', __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'ruby_language_server/version'

Gem::Specification.new do |spec|
  spec.name          = 'ruby_language_server'
  spec.version       = RubyLanguageServer::VERSION
  spec.authors       = ['Kurt Werle']
  spec.email         = ['kurt@CircleW.org']

  spec.summary       = 'Provide a language server implementation for ruby in ruby.'
  spec.description   = 'See https://microsoft.github.io/language-server-protocol/ "A Language Server is meant to provide the language-specific smarts and communicate with development tools over a protocol that enables inter-process communication."'
  spec.homepage      = 'https://github.com/kwerle/ruby_language_server'
  spec.license       = 'MIT'

  # Prevent pushing this gem to RubyGems.org. To allow pushes either set the 'allowed_push_host'
  # to allow pushing to a single host or delete this section to allow pushing to any host.
  if spec.respond_to?(:metadata)
    spec.metadata['homepage_uri'] = spec.homepage
    spec.metadata['source_code_uri'] = 'https://github.com/kwerle/ruby_language_server'
    spec.metadata['changelog_uri'] = 'https://github.com/kwerle/ruby_language_server/blob/develop/CHANGELOG.txt'
  else
    raise 'RubyGems 2.0 or newer is required to protect against ' \
      'public gem pushes.'
  end

  # Specify which files should be added to the gem when it is released.
  spec.files         = Dir.glob('{bin,lib,exe}/**/*') + %w[CHANGELOG.txt FAQ_ROADMAP.md Gemfile Gemfile.lock Guardfile LICENSE Makefile README.md Rakefile ruby_language_server.gemspec]

  spec.bindir        = 'exe'
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ['lib']

  # Normally the system will have these - but not if it's a stripped down docker image
  spec.add_dependency 'bundler'
  spec.add_dependency 'etc'
  spec.add_dependency 'json'

  # No - do not put these in dev - they are needed for the app
  spec.add_dependency 'rubocop'
  spec.add_dependency 'rubocop-performance' # Linter - no longer needed - use additional gems?
  spec.add_dependency 'rubocop-rspec'       # Linter - no longer needed - use additional gems?

  spec.add_dependency 'amatch'      # in c
  spec.add_dependency 'fuzzy_match' # completion matching

  spec.add_dependency 'activerecord', '>=5.2', '<7.0'
  spec.add_dependency 'sqlite3'

  spec.add_development_dependency 'guard'
  spec.add_development_dependency 'guard-minitest'
  spec.add_development_dependency 'guard-rubocop'
  spec.add_development_dependency 'minitest'
  spec.add_development_dependency 'minitest-color'
  spec.add_development_dependency 'pry'
  spec.add_development_dependency 'pry-byebug'
  spec.add_development_dependency 'rake' # required by guard :-(
  spec.add_development_dependency 'sexp_processor'
end
