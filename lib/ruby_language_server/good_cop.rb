require 'rubocop'

module RubyLanguageServer
  class GoodCop < RuboCop::Runner
    def initialize
      config_store = RuboCop::ConfigStore.new
      config_store.options_config= '.none'
      super({}, config_store)
    end

    def diagnostics(text)
      offenses(text).map do |offense|
        RubyLanguageServer.logger.warn(offense)
      end
      nil
    end

    def offenses(text)
      source = RuboCop::ProcessedSource.new(text, 2.4)
      processed_source = RuboCop::ProcessedSource.new(text, 2.4)
      offenses = inspect_file(processed_source)
      offenses
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
