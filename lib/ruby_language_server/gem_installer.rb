# frozen_string_literal: true

require 'bundler/inline'

module RubyLanguageServer
  # Sole purpose is to install gems
  module GemInstaller
    class << self
      def install_gems(additional_gem_names)
        additional_gem_names&.compact!
        additional_gem_names&.reject! { |name| name.strip == '' }
        return if additional_gem_names.nil? || additional_gem_names.empty?

        RubyLanguageServer.logger.info("Trying to install gems #{additional_gem_names}")

        gemfile do
          source 'https://rubygems.org'
          # Lock all the gems we already have installed to the versions we have installed
          # For some reason, installing bundler makes it unhappy.  Whatever.
          Gem::Specification.reject { |s| s.name == 'bundler' }.each do |specification|
            gem(specification.name, specification.version.to_s)
          end
          additional_gem_names.each do |gem_name|
            gem gem_name
          end
        end
      end
    end
  end
end
