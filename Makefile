 .PHONY: image guard continuous_development console test coverage rubocop shell run_in_shell server debug_server gem gem_release
PROJECT_NAME=ruby_language_server
# The image runs as UID 1000. Dev and test containers run as root, because they write
# coverage/ and logs into the mounted checkout, which CI runners own under another UID.
LOCAL_LINK=--user root -v $(PWD):/tmp/src -w /tmp/src

image:
	docker build -t $(PROJECT_NAME) .

force_rebuild_image:
	docker build --no-cache -t $(PROJECT_NAME) .

guard: image
	echo > active_record.log
	./bin/run_in_shell bundle exec guard
	echo > active_record.log

continuous_development: image
	docker build -t local_ruby_language_server .
	echo "You are going to want to set the ide-ruby 'Image Name' to local_ruby_language_server"
	sleep 15
	while (true) ; \
	do \
	  docker build -t local_ruby_language_server . ; \
	  sleep 2 ; \
	done

console: image
	./bin/run_in_shell bin/console

# Note that we don't use run_in_shell because those are interactive and CI won't like that.
test: image
	docker run --rm $(LOCAL_LINK) $(PROJECT_NAME) sh -c "bundle exec rake test && bundle exec rubocop"

coverage: image
	docker run --rm $(LOCAL_LINK) $(PROJECT_NAME) sh -c "COVERAGE=true bundle exec rake test"

rubocop: image
	docker run --rm $(LOCAL_LINK) $(PROJECT_NAME) sh -c "bundle exec rubocop"

shell: image
	./bin/run_in_shell sh

run_in_shell:
	docker run -it --rm $(LOCAL_LINK) $(PROJECT_NAME) sh -c "${SHELL_COMMAND}"

# Just to make sure it works.
server: image
	./bin/run_in_shell

# Runs this checkout's code (mounted, so no rebuild) under the rdbg debugger, with LSP over TCP.
# VS Code's "Debug server" configuration runs this and attaches; see README "Debugging the server".
# PROJECT is the project the client opens; it is mounted read-only at /project.
DEBUG_LSP_PORT=7658
DEBUG_RDBG_PORT=12345
PROJECT?=$(PWD)
debug_server: image
	-docker rm -f rls-debug >/dev/null 2>&1
	docker run --rm -i --name rls-debug $(LOCAL_LINK) \
	  --mount type=bind,source="$(PROJECT)",target=/project,readonly \
	  -p 127.0.0.1:$(DEBUG_LSP_PORT):$(DEBUG_LSP_PORT) -p 127.0.0.1:$(DEBUG_RDBG_PORT):$(DEBUG_RDBG_PORT) \
	  -e LSP_PORT=$(DEBUG_LSP_PORT) -e LOG_LEVEL=DEBUG -e RUBY_DEBUG_FORK_MODE=parent \
	  $(PROJECT_NAME) bundle exec rdbg --open --host 0.0.0.0 --port $(DEBUG_RDBG_PORT) --nonstop -- exe/ruby_language_server

gem: image
	rm -f $(PROJECT_NAME)*.gem
	./bin/run_in_shell gem build $(PROJECT_NAME)

# Requires rubygems be installed on host
gem_release: gem
	./bin/run_in_shell gem push $(PROJECT_NAME)*.gem
