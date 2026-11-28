# frozen_string_literal: true

require 'active_record'

require_relative 'scope_data/base'
require_relative 'scope_data/scope'
require_relative 'scope_data/variable'

module RubyLanguageServer
  class CodeFile < ActiveRecord::Base
    has_many :scopes, class_name: 'RubyLanguageServer::ScopeData::Scope', dependent: :destroy do
      def root_scope
        where(class_type: RubyLanguageServer::ScopeData::Scope::TYPE_ROOT).first
      end
    end
    has_many :variables, class_name: 'RubyLanguageServer::ScopeData::Variable', dependent: :destroy

    attr_accessor :diagnostics

    # True for a file from one of the project's gems (GemIndex), which the editor can't open.
    def gem_file?
      gem_name.present?
    end

    def self.build(uri, text)
      RubyLanguageServer.logger.debug("CodeFile initialize #{uri}")

      create!(uri:, text:)
    end

    SYMBOL_KIND = {
      file: 1,
      module: 5, # 2,
      namespace: 3,
      package: 4,
      class: 5,
      method: 6,
      'singleton method': 6,
      property: 7,
      field: 8,
      constructor: 9,
      enum: 10,
      interface: 11,
      function: 12,
      variable: 13,
      constant: 14,
      string: 15,
      number: 16,
      boolean: 17,
      array: 18
    }.freeze

    # Find the ancestor of this scope with a name and return that.  Or nil.
    def ancestor_scope_name(scope)
      return_scope = scope
      while (return_scope = return_scope.parent)
        return return_scope.name unless return_scope.name.nil? || return_scope.block_scope?
      end
    end

    def tags
      RubyLanguageServer.logger.debug("Asking about tags for #{uri}")
      return [] if text.blank?

      refresh_scopes_if_needed # cause root scope to reset
      return [] if scopes.reload.count <= 1 # just the root

      tags = scopes.reload.map do |scope|
        next if scope.class_type == ScopeData::Base::TYPE_BLOCK
        next if scope.root_scope?

        kind = SYMBOL_KIND[scope.class_type.to_sym] || 7
        kind = 9 if scope.name == 'initialize' # Magical special case
        scope_hash = {
          name: scope.name,
          kind:,
          location: Location.hash(uri, scope.top_line, scope.column, scope.bottom_line)
        }
        container_name = ancestor_scope_name(scope)
        scope_hash[:containerName] = container_name unless container_name.blank?
        scope_hash
      end
      tags += variables.constant_variables.reload.map do |variable|
        name = variable.name
        {
          name:,
          kind: SYMBOL_KIND[:constant],
          location: Location.hash(uri, variable.line, variable.column),
          containerName: variable.scope.name
        }
      end
      # Clients reject a symbol with a blank name, and fail the whole request (task '', attr_accessor '').
      tags = tags.compact.reject { |tag| tag[:name].blank? || tag[:name] == RubyLanguageServer::ScopeData::Scope::TYPE_BLOCK }
      # RubyLanguageServer.logger.debug("Raw tags for #{uri}: #{tags}")
      # If you don't reverse the list then atom? won't be able to find the
      # container and containers will get duplicated.
      tags.reverse_each do |tag|
        child_tags = tags.select { |child_tag| child_tag[:containerName] == tag[:name] }
        max_line = child_tags.map { |child_tag| child_tag[:location][:range][:end][:line].to_i }.max || 0
        tag[:location][:range][:end][:line] = [tag[:location][:range][:end][:line], max_line].max
      end
      tags
    end

    def update_text(new_text)
      return true if new_text == text

      RubyLanguageServer.logger.debug("update_text for #{uri}")
      update(text: new_text, refresh_root_scope: true)
    end

    # While someone types within a line, re-parse at most this often. An edit that
    # changes the number of lines is re-parsed at once, so stored line ranges stay valid.
    # 0 re-parses on every request (the specs use that).
    REPARSE_INTERVAL = Float(ENV.fetch('RUBY_LANGUAGE_SERVER_REPARSE_INTERVAL', '1.0')) # seconds

    def refresh_scopes_if_needed
      return if new_record? # nothing stored yet, so nothing to parse
      return unless refresh_root_scope
      return if reparse_can_wait?

      RubyLanguageServer.logger.debug("Asking about root_scope for #{uri}")
      self.class.transaction do
        # Deleting first also takes SQLite's write lock, which PrismProcessor#store! relies on.
        # delete_all, not destroy: one statement each, instead of one per row.
        RubyLanguageServer::ScopeData::Variable.where(code_file_id: id).delete_all
        RubyLanguageServer::ScopeData::Scope.where(code_file_id: id).delete_all
        new_root = ScopeParser.new(text, code_file_id: id, library: gem_file?).root_scope
        raise ActiveRecord::Rollback if new_root.nil? || new_root.children.blank?

        update_columns(refresh_root_scope: false, parsed_at: monotonic_now, parsed_line_count: line_count)
        new_root
      end
    end

    # True when the last parse was recent and the edits since then kept the line count,
    # so its scopes still line up with the text. The next request after the interval
    # re-parses.
    def reparse_can_wait?
      return false if parsed_at.nil?

      parsed_line_count == line_count && monotonic_now - parsed_at < reparse_interval
    end

    def reparse_interval
      REPARSE_INTERVAL
    end

    def line_count
      text.to_s.count("\n")
    end

    def monotonic_now
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    # Returns the context of what is being typed in the given line
    def context_at_location(position)
      lines = text.to_s.split("\n")
      line = lines[position.line]
      return [] if line.nil? || line.strip.empty?

      LineContext.for(line, LineContext.character_index(line, position.character))
    end
  end
end
