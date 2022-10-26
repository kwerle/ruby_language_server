# frozen_string_literal: true

require 'rubocop'

module RubyLanguageServer
  class GoodCop < RuboCop::Runner
    def initialize(config_path, initialization_error = nil)
      @initialization_error = initialization_error
      unless @initialization_error
        initialize_rubocop_ivars
        @config_store.options_config = config_path
        RubyLanguageServer.logger.debug("Rubocop config_path: #{config_path}")
        super({}, @config_store)
      end
    rescue Exception => e
      RubyLanguageServer.logger.error(e)
      @initialization_error = "There was an issue loading the rubocop configuration file: #{e}.  Maybe you need to add some additional gems to the ide-ruby settings?"
    end

    # namespace DiagnosticSeverity {
    #  /**
    #   * Reports an error.
    #   */
    #  export const Error = 1;
    #  /**
    #   * Reports a warning.
    #   */
    #  export const Warning = 2;
    #  /**
    #   * Reports an information.
    #   */
    #  export const Information = 3;
    #  /**
    #   * Reports a hint.
    #   */
    #  export const Hint = 4;
    # }

    # interface Diagnostic {
    #  /**
    #   * The range at which the message applies.
    #   */
    #  range: Range;
    #
    #  /**
    #   * The diagnostic's severity. Can be omitted. If omitted it is up to the
    #   * client to interpret diagnostics as error, warning, info or hint.
    #   */
    #  severity?: number;
    #
    #  /**
    #   * The diagnostic's code. Can be omitted.
    #   */
    #  code?: number | string;
    #
    #  /**
    #   * A human-readable string describing the source of this
    #   * diagnostic, e.g. 'typescript' or 'super lint'.
    #   */
    #  source?: string;
    #
    #  /**
    #   * The diagnostic's message.
    #   */
    #  message: string;
    # }

    def diagnostic_severity_for(severity)
      case severity.to_s
      when 'error', 'fatal'
        1
      when 'warning'
        2
      when 'refactor', 'convention'
        3
      else
        RubyLanguageServer.logger.error("Could not map severity for #{severity} - returning 2")
        2
      end
    end

    def diagnostics(text, filename = nil)
      return initialization_offenses unless @initialization_error.nil?

      maximum_severity = 4 # (ENV['LINT_LEVEL'] || 4).to_i
      enabled_offenses = offenses(text, filename).reject { |offense| offense.status == :disabled }
      enabled_offenses.map do |offense|
        {
          range: Location.position_hash(offense.location.line, offense.location.column, offense.location.last_line, offense.location.last_column),
          severity: diagnostic_severity_for(offense.severity),
          # code?: number | string;
          code: 'code',
          source: "RuboCop:#{offense.cop_name}",
          message: offense.message
        }
      end.select { |hash| hash[:severity] <= maximum_severity }
    end

    private

    def offenses(text, filename)
      if excluded_file?(filename)
        []
      else
        ruby_version = 3.1
        processed_source = RuboCop::ProcessedSource.new(text, ruby_version, filename)
        offenses = inspect_file(processed_source)
        offenses.compact.flatten.reject(&:blank?) # reject blank because some are `false`
      end
    end

    def initialize_rubocop_ivars
      @config_store ||= RuboCop::ConfigStore.new
      @options ||= {}
      @errors ||= []
      @warnings ||= []
    end

    def inspect_file(source)
      initialize_rubocop_ivars
      super
    end

    def initialization_offenses
      [
        {
          range: Location.position_hash(1, 1, 1, 1),
          severity: 'startup', # diagnostic_severity_for(offense.severity),
          # code?: number | string;
          code: 'code',
          source: 'RuboCop:RubyLanguageServer',
          message: @initialization_error
        }
      ]
    end

    class << self
      def instance
        @config_path ||= config_path
        config_path_timestamp = File.mtime(@config_path)
        if @cached_config_path_timestamp.nil? || @cached_config_path_timestamp < config_path_timestamp
          @cached_config_path_timestamp = config_path_timestamp
          @instance = new(@config_path)
        else
          @instance
        end
      rescue StandardError => e
        @instance = new(@config_path, e.to_s)
      end

      private

      def config_path
        my_path = __FILE__
        pathname = Pathname.new(my_path)
        my_directory = pathname.dirname
        fallback_pathname = "#{my_directory}/../resources/fallback_rubocop.yml"
        project_path = "#{RubyLanguageServer::ProjectManager.root_path}.rubocop.yml"
        possible_config_paths = [project_path, fallback_pathname.to_s]
        possible_config_paths.detect { |path| File.exist?(path) }
      end
    end

    def excluded_file?(filename)
      initialize_rubocop_ivars
      file_config = @config_store.for(filename)
      file_config.file_to_exclude?(filename)
    end
  end
end
