# frozen_string_literal: true

module RubyLanguageServer
  module ScopeData
    # The Scope class is basically a container with context.
    # It is used to track top & bottom line, variables in this scope, constants, and children - which could be functions, classes, blocks, etc.  Anything that adds scope.
    class Scope < Base
      has_many :variables, dependent: :destroy
      belongs_to :parent, class_name: 'Scope', optional: true
      has_many :children, class_name: 'Scope', foreign_key: :parent_id

      scope :for_line, -> (line) { where('top_line <= ? AND bottom_line >= ?', line, line).or(where(parent_id: nil)) }
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

      # Return the deepest child scopes of this scope - and on up.
      # Not done recuresively because we don't really need to.
      # Normally called on a root scope.
      # def scopes_at(position)
      #   line = position.line
      #   matching_scopes = self_and_descendants.where('top_line <= ?', line).where('bottom_line >= ?', line)
      #   deepest_scope = matching_scopes.max_by(&:depth)
      #   deepest_scope&.self_and_ancestors || []
      # end

      # Self and all descendents flattened into array
      def self_and_descendants
        return Scope.all if root_scope?

        Scope.where("path like ?", "#{path}%")
      end

      def descendants
        Scope.where("path like ?", "#{path}_%")
      end

      # [self, parent, parent.parent...]
      # def self_and_ancestors
      #   return [self] if path.blank?
      #   remaining_path = path.dup
      #   ancestor_paths = scope_parts.inject([]) do |ary, scope_part|
      #     ary << remaining_path
      #     remaining_path =
      #     ary
      #   end
      #   [self, parent&.self_and_ancestors].flatten.compact
      # end

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

      private

      def scope_parts
        path&.split(/#{JoinHash.values.reject(&:blank?).uniq.join('|')}/)
      end
    end
  end
end
