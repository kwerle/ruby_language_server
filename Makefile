 .PHONY: image guard continuous_development console test shell run_in_shell server gem gem_release publish_cross_platform_image
PROJECT_NAME=ruby_language_server
LOCAL_LINK=-v $(PWD):/tmp/src -w /tmp/src

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

test: image
	docker run --rm $(LOCAL_LINK) $(PROJECT_NAME) sh -c "bundle exec rake test && bundle exec rubocop"

coverage: image
	./bin/run_in_shell "COVERAGE=true bundle exec rake test"

shell: image
	./bin/run_in_shell sh

run_in_shell:
	docker run -it --rm $(LOCAL_LINK) $(PROJECT_NAME) sh -c "${SHELL_COMMAND}"

# Just to make sure it works.
server: image
	./bin/run_in_shell

gem: image
	rm -f $(PROJECT_NAME)*.gem
	./bin/run_in_shell gem build $(PROJECT_NAME)

# Requires rubygems be installed on host
gem_release: gem
	./bin/run_in_shell gem push $(PROJECT_NAME)*.gem

publish_cross_platform_image:
	(docker buildx ls | grep mybuilder) || ./bin/run_in_shell docker buildx create --name mybuilder
	./bin/run_in_shell docker buildx use mybuilder
	./bin/run_in_shell docker buildx build --push --platform linux/amd64,linux/arm64/v8 -t kwerle/$(PROJECT_NAME) .
