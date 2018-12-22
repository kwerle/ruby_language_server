# frozen_string_literal: true

require 'bundler/inline'

module RubyLanguageServer
  # Sole purpose is to install gems
  module GemInstaller
    class << self
      def install_gems(gem_names)
        return if gem_names.nil? || gem_names.empty?

        RubyLanguageServer.logger.info("Trying to install gems #{gem_names}")
        gemfile do
          source 'https://rubygems.org'
          gem_names.each do |gem_name|
            gem gem_name
          end
        end
      end
    end
  end
end
