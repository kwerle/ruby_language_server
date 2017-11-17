require 'rubocop'

module RubyLanguageServer
  class GoodCop < RuboCop::Runner
    def initialize
      config_store = RuboCop::ConfigStore.new
      config_store.options_config= '.rubocop.yml'
      super({}, config_store)
    end

    # namespace DiagnosticSeverity {
    # 	/**
    # 	 * Reports an error.
    # 	 */
    # 	export const Error = 1;
    # 	/**
    # 	 * Reports a warning.
    # 	 */
    # 	export const Warning = 2;
    # 	/**
    # 	 * Reports an information.
    # 	 */
    # 	export const Information = 3;
    # 	/**
    # 	 * Reports a hint.
    # 	 */
    # 	export const Hint = 4;
    # }

    # interface Diagnostic {
    # 	/**
    # 	 * The range at which the message applies.
    # 	 */
    # 	range: Range;
    #
    # 	/**
    # 	 * The diagnostic's severity. Can be omitted. If omitted it is up to the
    # 	 * client to interpret diagnostics as error, warning, info or hint.
    # 	 */
    # 	severity?: number;
    #
    # 	/**
    # 	 * The diagnostic's code. Can be omitted.
    # 	 */
    # 	code?: number | string;
    #
    # 	/**
    # 	 * A human-readable string describing the source of this
    # 	 * diagnostic, e.g. 'typescript' or 'super lint'.
    # 	 */
    # 	source?: string;
    #
    # 	/**
    # 	 * The diagnostic's message.
    # 	 */
    # 	message: string;
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
        RubyLanguageServer.logger.warn("Could not map severity for #{severity} - returning 2")
        2
      end
    end

    def diagnostics(text)
      offenses(text).map do |offense|
        {
        	range: Location.position_hash(offense.location.line + 1, offense.location.column, offense.location.last_line + 1, offense.location.last_column),
        	severity: diagnostic_severity_for(offense.severity),
        	# code?: number | string;
        	source: 'RuboCop',
        	message: offense.message,
        }
      end
    end

    private

    def offenses(text)
      source = RuboCop::ProcessedSource.new(text, 2.4)
      processed_source = RuboCop::ProcessedSource.new(text, 2.4)
      offenses = inspect_file(processed_source)
      offenses.compact.flatten
    end
  end
end

# {
# 	/**
# 	 * The range at which the message applies.
# 	 */
# 	range: Range;
#
# 	/**
# 	 * The diagnostic's severity. Can be omitted. If omitted it is up to the
# 	 * client to interpret diagnostics as error, warning, info or hint.
# 	 */
# 	severity?: number;
#
# 	/**
# 	 * The diagnostic's code. Can be omitted.
# 	 */
# 	code?: number | string;
#
# 	/**
# 	 * A human-readable string describing the source of this
# 	 * diagnostic, e.g. 'typescript' or 'super lint'.
# 	 */
# 	source?: string;
#
# 	/**
# 	 * The diagnostic's message.
# 	 */
# 	message: string;
# }
