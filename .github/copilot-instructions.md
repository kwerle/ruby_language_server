# GitHub Copilot Instructions for ruby_language_server

## Running Commands

This project uses Docker for a consistent development environment. **Always use `bin/run_in_shell` instead of running Ruby, Bundler, or RSpec commands directly on the host.**

### Examples

❌ **Don't do this:**
```bash
bundle exec rspec spec/lib/ruby_language_server/project_manager_spec.rb
ruby -v
bundle install
```

✅ **Do this instead:**
```bash
./bin/run_in_shell bundle exec rspec spec/lib/ruby_language_server/project_manager_spec.rb
./bin/run_in_shell ruby -v
./bin/run_in_shell bundle install
```

### How it works

- `bin/run_in_shell` is a wrapper script that runs commands inside a Docker container
- It ensures all Ruby, Bundler, and gem commands run in the correct environment
- The container has all dependencies pre-installed and properly configured

### Common Commands

- Run tests: `./bin/run_in_shell bundle exec rake test`
- Run specific test: `./bin/run_in_shell bundle exec ruby -Itest spec/path/to/file_spec.rb`
- Open console: `./bin/run_in_shell bin/console`
- Shell access: `./bin/run_in_shell sh`
- Bundle install: `./bin/run_in_shell bundle install`

### Testing Framework

This project uses **Minitest**, not RSpec. Test files are located in the `spec/` directory but use Minitest syntax (`assert_equal`, `assert`, etc.).

### Make targets

You can also use make targets which automatically use `run_in_shell`:
- `make test` - Run all tests
- `make console` - Open interactive console
- `make shell` - Open shell in container
