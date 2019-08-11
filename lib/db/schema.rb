require 'byebug'

ActiveRecord::Schema.define do
  def write(*args)
    RubyLanguageServer.logger.debug(args)
  end
  create_table :scopes, force: true do |t|
    t.integer :parent_id
    t.integer :top_line        # first line
    t.integer :bottom_line     # last line
    t.integer :column
    t.string  :name, default: ''
    t.string  :superclass_name
    t.string  :path
    t.string  :class_type, null: false
  end

  create_table :variables, force: true do |t|
    t.references :scope
    t.integer :line
    t.integer :column
    t.string  :name
    t.string  :path
    t.string  :variable_type
  end
end
