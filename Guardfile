# frozen_string_literal: true

# A sample Guardfile
# More info at https://github.com/guard/guard#readme

## Uncomment and set this to only include directories you want to watch
# directories %w(app lib config test spec features) \
#  .select{|d| Dir.exists?(d) ? d : UI.warning("Directory #{d} does not exist")}

## Note: if you are using the `directories` clause above and you are not
## watching the project directory ('.'), then you will want to move
## the Guardfile to a watched dir and symlink it back, e.g.
#
#  $ mkdir config
#  $ mv Guardfile config/
#  $ ln -s config/Guardfile .
#
# and, you'll have to watch "config/Guardfile" instead of "Guardfile"

group :red_green_refactor, halt_on_fail: true do
  guard :minitest, all_after_pass: true do
    # with Minitest::Unit
    # watch(%r{^test/(.*)\/?test_(.*)\.rb$})
    # watch(%r{^lib/(.*/)?([^/]+)\.rb$})     { |m| "test/#{m[1]}test_#{m[2]}.rb" }
    # watch(%r{^test/test_helper\.rb$})      { 'test' }

    # with Minitest::Spec
    watch(%r{^spec/**/(.*)_spec\.rb$})
    watch(%r{^lib/(.+)\.rb$})          { |m| "spec/lib/#{m[1]}_spec.rb" }
    watch(%r{^spec/spec_helper\.rb$})  { 'spec' }
  end

  guard :rubocop, cli: [] do
    watch('.rubocop_ruby_language_parser.yml')
    watch(/.+\.rb$/)
    watch(%r{(?:.+/)?\.rubocop(?:_todo)?\.yml$}) { |m| File.dirname(m[0]) }
  end
end
