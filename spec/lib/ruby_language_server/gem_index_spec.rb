# frozen_string_literal: true

require_relative '../../test_helper'
require 'minitest/autorun'
require 'tmpdir'

describe RubyLanguageServer::GemIndex do
  let(:tmp) { Dir.mktmpdir }
  let(:project_root) { File.join(tmp, 'project') }
  let(:data_dir) { File.join(tmp, 'data') }
  let(:project_manager) { RubyLanguageServer::ProjectManager.new('/proj', 'file:///proj/') }
  let(:gem_index) { RubyLanguageServer::GemIndex.new(project_root:, data_dir:, indexer: project_manager.method(:index_file)) }

  let(:lockfile) do
    <<~LOCK
      GEM
        remote: https://rubygems.org/
        specs:
          broken (1.0.0)
          nokogiri (1.16.0-arm64-darwin)
          nokogiri (1.16.0-x86_64-linux)
          tiny (0.1.0)

      GIT
        remote: https://github.com/example/fromgit.git
        revision: 0123456789abcdef0123456789abcdef01234567
        specs:
          fromgit (0.1.0)

      PATH
        remote: .
        specs:
          local (0.1.0)

      PLATFORMS
        ruby

      DEPENDENCIES
        broken
        fromgit!
        local!
        nokogiri
        tiny

      BUNDLED WITH
         2.5.0
    LOCK
  end

  # Builds tiny-0.1.0.gem, with a lib file and a spec file, and returns its path.
  def build_tiny_gem
    source = File.join(tmp, 'tiny_source')
    FileUtils.mkdir_p(File.join(source, 'lib'))
    FileUtils.mkdir_p(File.join(source, 'spec'))
    File.write(File.join(source, 'lib', 'tiny.rb'), "class Tiny\n  # Says hello.\n  def hello(name = 'you')\n  end\nend\n")
    File.write(File.join(source, 'spec', 'tiny_spec.rb'), "class TinySpec\nend\n")
    spec = Gem::Specification.new do |s|
      s.name = 'tiny'
      s.version = '0.1.0'
      s.summary = 'Tiny'
      s.authors = ['Someone']
      s.files = %w[lib/tiny.rb spec/tiny_spec.rb]
    end
    Dir.chdir(source) { File.join(source, Gem::Package.build(spec)) }
  end

  # Downloads become copies of the tiny gem. Any other gem fails to download.
  def stub_downloads(index)
    tiny_gem = build_tiny_gem
    downloaded = []
    index.define_singleton_method(:download) do |locked_gem, dir|
      downloaded << locked_gem.full_name
      next nil unless locked_gem.name == 'tiny'

      FileUtils.cp(tiny_gem, dir)
      File.join(dir, File.basename(tiny_gem))
    end
    downloaded
  end

  after { FileUtils.rm_rf(tmp) }

  describe '#locked_gems' do
    it 'keeps rubygems gems once per version and skips git and path gems' do
      gems = gem_index.locked_gems(lockfile)

      assert_equal(%w[broken-1.0.0 nokogiri-1.16.0 tiny-0.1.0], gems.map(&:full_name).sort)
      assert_equal(['https://rubygems.org/'], gems.map(&:remote).uniq)
      assert_equal(%w[arm64-darwin x86_64-linux], gems.find { |locked_gem| locked_gem.name == 'nokogiri' }.platforms.sort)
      assert_empty(gems.find { |locked_gem| locked_gem.name == 'tiny' }.platforms)
    end
  end

  describe '#load!' do
    before do
      FileUtils.mkdir_p(project_root)
      File.write(File.join(project_root, 'Gemfile.lock'), "GEM\n  remote: https://rubygems.org/\n  specs:\n    broken (1.0.0)\n    tiny (0.1.0)\n\nPLATFORMS\n  ruby\n\nDEPENDENCIES\n  broken\n  tiny\n")
    end

    it "indexes each gem's lib files with the gem's name and version, and skips gems it can't fetch" do
      downloaded = stub_downloads(gem_index)
      gem_index.load!

      assert_equal(%w[broken-1.0.0 tiny-0.1.0], downloaded.sort)
      hello = RubyLanguageServer::ScopeData::Scope.find_by(path: 'Tiny#hello')
      refute_nil(hello)
      assert_equal(['tiny', '0.1.0'], [hello.code_file.gem_name, hello.code_file.gem_version])
      assert(hello.code_file.gem_file?)
      assert_equal('Says hello.', hello.documentation)
      assert_equal("file://#{data_dir}/gems/tiny-0.1.0/lib/tiny.rb", hello.code_file.uri)
      assert_nil(RubyLanguageServer::ScopeData::Scope.find_by(name: 'TinySpec'), 'specs inside a gem are not indexed')
      refute(File.exist?(File.join(data_dir, 'gems', 'cache', 'tiny-0.1.0')), 'the downloaded .gem is removed')
    end

    it 'does nothing without a Gemfile.lock' do
      FileUtils.rm(File.join(project_root, 'Gemfile.lock'))
      downloaded = stub_downloads(gem_index)
      gem_index.load!

      assert_empty(downloaded)
      assert_equal(0, RubyLanguageServer::CodeFile.count)
    end
  end

  describe '#download' do
    it 'tries the plain build, then each platform build, from the remote' do
      requested = []
      gem_index.define_singleton_method(:http_get) do |uri, *|
        requested << uri.to_s
        uri.to_s.end_with?('-x86_64-linux.gem') ? 'gem bytes' : nil
      end
      locked_gem = RubyLanguageServer::GemIndex::LockedGem.new('nokogiri', '1.16.0', 'https://gems.example/', %w[arm64-darwin x86_64-linux])

      path = gem_index.send(:download, locked_gem, tmp)

      assert_equal(%w[https://gems.example/gems/nokogiri-1.16.0.gem https://gems.example/gems/nokogiri-1.16.0-arm64-darwin.gem https://gems.example/gems/nokogiri-1.16.0-x86_64-linux.gem], requested)
      assert_equal('gem bytes', File.read(path))
    end
  end

  describe '#gem_dir' do
    it "reads a gem in the server's own bundle in place" do
      prism = Gem.loaded_specs.fetch('prism')
      downloaded = stub_downloads(gem_index)

      assert_equal(prism.full_gem_path, gem_index.gem_dir(RubyLanguageServer::GemIndex::LockedGem.new('prism', prism.version.to_s, nil, [])))
      assert_empty(downloaded)
    end

    it "reads a gem in the project's vendor/bundle in place" do
      vendored = File.join(project_root, 'vendor', 'bundle', 'ruby', '4.0.0', 'gems', 'nokogiri-1.16.0-x86_64-linux')
      FileUtils.mkdir_p(vendored)
      downloaded = stub_downloads(gem_index)

      assert_equal(vendored, gem_index.gem_dir(RubyLanguageServer::GemIndex::LockedGem.new('nokogiri', '1.16.0', nil, [])))
      assert_empty(downloaded)
    end
  end
end
