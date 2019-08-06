# frozen_string_literal: true

require 'bundler/inline'

module RubyLanguageServer
  # Sole purpose is to install gems
  module GemInstaller
    class << self
      def install_gems(gem_names)
        gem_names&.compact!
        gem_names&.reject! { |name| name.strip == '' }
        return if gem_names.nil? || gem_names.empty?

        RubyLanguageServer.logger.info("Trying to install gems #{gem_names}")
        rubocop_gem = Gem::Specification.find_by_name 'rubocop'
        gemfile do
          source 'https://rubygems.org'
          gem 'rubocop', rubocop_gem.version.to_s
          gem_names.each do |gem_name|
            gem gem_name
          end
        end
      end
    end
  end
end
