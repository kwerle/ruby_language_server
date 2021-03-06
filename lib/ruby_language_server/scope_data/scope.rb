# frozen_string_literal: true

require 'active_record'

module RubyLanguageServer
  module ScopeData
    # The Scope class is basically a container with context.
    # It is used to track top & bottom line, variables in this scope, constants, and children - which could be functions, classes, blocks, etc.  Anything that adds scope.
    class Scope < Base
      has_many :variables, dependent: :destroy
      belongs_to :code_file # , optional: false
      belongs_to :parent, class_name: 'Scope', optional: true
      has_many :children, class_name: 'Scope', foreign_key: :parent_id

      scope :method_scopes, -> { where(class_type: TYPE_METHOD) }
      scope :for_line, ->(line) { where('top_line <= ? AND bottom_line >= ?', line, line).or(where(parent_id: nil)) }
      scope :by_path_length, -> { order(Arel.sql('length(path) DESC')) }
      # attr_accessor :top_line        # first line
      # attr_accessor :bottom_line     # last line
      # attr_accessor :parent          # parent scope
      # attr_accessor :constants       # constants declared in this scope
      # attr_accessor :name            # method
      # attr_accessor :superclass_name # superclass name

      def self.build(parent = nil, type = TYPE_ROOT, name = '', top_line = 1, column = 1)
        full_name = [parent ? parent.full_name : nil, name].compact.join(JoinHash[type])
        create!(
          parent: parent,
          top_line: top_line,
          column: column,
          name: name,
          path: full_name,
          class_type: type
        )
      end

      def full_name
        path # @full_name || @name
      end

      def depth
        return 0 if path.blank?

        scope_parts.count
      end

      # Self and all descendents flattened into array
      def self_and_descendants
        return Scope.all if root_scope?

        Scope.where('path like ?', "#{path}%")
      end

      def descendants
        Scope.where('path like ?', "#{path}_%")
      end

      def set_superclass_name(partial)
        if partial.start_with?('::')
          self.superclass_name = partial.gsub(/^::/, '')
        else
          self.superclass_name = [parent ? parent.full_name : nil, partial].compact.join(JoinHash[class_type])
        end
        save!
      end

      def root_scope?
        class_type == TYPE_ROOT
      end

      def block_scope?
        class_type == TYPE_BLOCK
      end

      # Not a block or root
      def named_scope?
        [TYPE_MODULE, TYPE_CLASS, TYPE_METHOD, TYPE_VARIABLE].include?(class_type)
      end

      private

      def scope_parts
        path&.split(/#{JoinHash.values.reject(&:blank?).uniq.join('|')}/)
      end
    end
  end
end
