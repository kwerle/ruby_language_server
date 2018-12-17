# frozen_string_literal: true

require 'bundler/inline'

# Deal with the various languageserver calls.
module RubyLanguageServer
  module GemInstaller
    class << self
      def install_gems(gem_names)
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
