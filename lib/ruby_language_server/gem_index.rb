# frozen_string_literal: true

require 'bundler'
require 'fileutils'
require 'net/http'
require 'rubygems/package'

module RubyLanguageServer
  # The project's gems, from its Gemfile.lock, indexed like the project's own files so
  # completion and hover know them.
  #
  # Each gem's files come from the first place that has them: the server's own bundle (the
  # same name and version), the project's vendor/bundle, or a download into the data dir.
  # Gems are downloaded and unpacked, never installed, so no gem code runs. Only rubygems
  # sources count: git and path gems are skipped.
  #
  # Their code files are stored with the gem's name and version. Their paths are inside
  # the container, where the editor can't open them, so go-to-definition leaves them out.
  class GemIndex
    # platforms are the lockfile's builds of it other than plain ruby, like x86_64-linux.
    LockedGem = Struct.new(:name, :version, :remote, :platforms) do
      def full_name
        "#{name}-#{version}"
      end
    end

    DEFAULT_REMOTE = 'https://rubygems.org/'

    # Files under a gem's lib that aren't code it loads, like generator templates.
    SKIP_PATTERN = %r{/templates/}

    DOWNLOAD_TIMEOUT = 30 # seconds, for connecting and for each read
    MAX_REDIRECTS = 5 # rubygems.org redirects .gem downloads to its CDN

    # Indexes the gems in project_root's Gemfile.lock, logging any failure. Set
    # RUBY_LANGUAGE_SERVER_GEM_INDEX=false to skip them (the specs do).
    def self.index_project(project_root, indexer)
      return if ENV['RUBY_LANGUAGE_SERVER_GEM_INDEX'] == 'false' || project_root.nil?

      data_dir = ENV.fetch('RUBY_LANGUAGE_SERVER_DATA_DIR', '/data')
      new(project_root:, data_dir:, indexer:).load!
    rescue StandardError => e
      RubyLanguageServer.logger.error("Couldn't index gems: #{e.class}: #{e}\n#{e.backtrace * "\n"}")
    end

    # indexer is called as indexer.call(uri, text, gem_name:, gem_version:) for each file.
    def initialize(project_root:, data_dir:, indexer:)
      @project_root = project_root
      @data_dir = data_dir
      @indexer = indexer
    end

    def load!
      lockfile = File.join(@project_root, 'Gemfile.lock')
      return unless File.file?(lockfile)

      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      gems = locked_gems(File.read(lockfile))
      file_count = gems.sum { |locked_gem| index_gem(locked_gem) }
      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
      RubyLanguageServer.logger.info("Indexed #{file_count} files from #{gems.length} gems in #{elapsed.round(2)}s")
    end

    # The rubygems-sourced gems in the lockfile text, one per name and version (a lockfile
    # lists a gem once for each platform).
    def locked_gems(lockfile_text)
      specs = Bundler::LockfileParser.new(lockfile_text).specs
      rubygems = specs.select { |spec| spec.source.is_a?(Bundler::Source::Rubygems) }
      rubygems.group_by { |spec| [spec.name, spec.version.to_s] }.map do |(name, version), builds|
        platforms = builds.map { |spec| spec.platform.to_s } - ['ruby']
        LockedGem.new(name, version, builds.first.source.remotes.first&.to_s, platforms)
      end
    end

    # Indexes one gem's lib files. Returns how many there were. A gem that can't be found
    # or read is logged and skipped.
    def index_gem(locked_gem)
      dir = gem_dir(locked_gem)
      return 0 if dir.nil?

      files = Dir.glob(File.join(dir, 'lib', '**', '*.rb')).grep_v(SKIP_PATTERN)
      files.each { |path| index_file(locked_gem, path) }
      files.length
    rescue StandardError => e
      RubyLanguageServer.logger.error("Skipping gem #{locked_gem.full_name}: #{e.class}: #{e}")
      0
    end

    # A directory holding the gem's files, or nil.
    def gem_dir(locked_gem)
      installed_gem_dir(locked_gem) || vendored_gem_dir(locked_gem) || fetch_and_unpack(locked_gem)
    end

    private

    def index_file(locked_gem, path)
      @indexer.call("file://#{path}", File.read(path), gem_name: locked_gem.name, gem_version: locked_gem.version)
    rescue StandardError => e
      RubyLanguageServer.logger.error("Skipping #{path}: #{e.class}: #{e}")
    end

    # The same gem in the server's own bundle.
    def installed_gem_dir(locked_gem)
      spec = Gem::Specification.find_all_by_name(locked_gem.name, "= #{locked_gem.version}").first
      spec.full_gem_path if spec && File.directory?(spec.full_gem_path)
    end

    # The gem in the project's vendor/bundle, with or without a platform suffix.
    def vendored_gem_dir(locked_gem)
      pattern = File.join(@project_root, 'vendor', 'bundle', 'ruby', '*', 'gems', "#{locked_gem.full_name}{,-*}")
      Dir.glob(pattern).find { |dir| File.directory?(dir) }
    end

    # Downloads the .gem into the data dir and unpacks it there. Returns the directory,
    # or nil if the download failed.
    def fetch_and_unpack(locked_gem)
      destination = File.join(@data_dir, 'gems', locked_gem.full_name)
      return destination if File.directory?(destination)

      download_dir = File.join(@data_dir, 'gems', 'cache', locked_gem.full_name)
      FileUtils.mkdir_p(download_dir)
      gem_file = download(locked_gem, download_dir)
      return nil if gem_file.nil?

      Gem::Package.new(gem_file).extract_files(destination)
      destination
    ensure
      FileUtils.rm_rf(download_dir) if download_dir
    end

    # Downloads the .gem from the gem's remote into dir: the plain ruby build if there is
    # one, else one of the lockfile's platform builds. Returns its path, or nil.
    def download(locked_gem, dir)
      remote = (locked_gem.remote || DEFAULT_REMOTE).chomp('/')
      file_names = [locked_gem.full_name, *locked_gem.platforms.map { |platform| "#{locked_gem.full_name}-#{platform}" }].map { |name| "#{name}.gem" }
      file_names.each do |file_name|
        body = http_get(URI("#{remote}/gems/#{file_name}"))
        next if body.nil?

        path = File.join(dir, file_name)
        File.binwrite(path, body)
        return path
      end
      RubyLanguageServer.logger.warn("Couldn't download gem #{locked_gem.full_name} from #{remote}")
      nil
    end

    # The body of a successful GET of uri, following redirects, or nil.
    def http_get(uri, redirects = MAX_REDIRECTS)
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https', open_timeout: DOWNLOAD_TIMEOUT, read_timeout: DOWNLOAD_TIMEOUT) do |http|
        http.request(Net::HTTP::Get.new(uri))
      end
      case response
      when Net::HTTPSuccess then response.body
      when Net::HTTPRedirection then redirects.positive? ? http_get(URI.join(uri, response['location']), redirects - 1) : nil
      end
    end
  end
end
