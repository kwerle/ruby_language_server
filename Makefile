PROJECT_NAME=ruby_language_server
LOCAL_LINK=-v $(PWD):/tmp/src -w /tmp/src

image:
	docker build -t $(PROJECT_NAME) .

force_rebuild_image:
	docker build --no-cache -t $(PROJECT_NAME) .

guard: image
	echo > active_record.log
	docker run -it --rm $(LOCAL_LINK) -e LOG_LEVEL=DEBUG $(PROJECT_NAME) bundle exec guard
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
	docker run -it --rm $(LOCAL_LINK) $(PROJECT_NAME)  bin/console

test: image
	docker run -it --rm $(LOCAL_LINK) $(PROJECT_NAME) sh -c 'bundle exec rake test && bundle exec rubocop'

shell: image
	docker run -it --rm $(LOCAL_LINK) $(PROJECT_NAME) sh

run_in_shell: image
	docker run -it --rm $(LOCAL_LINK) $(PROJECT_NAME) sh -c '$(COMMAND)'

# Just to make sure it works.
server: image
	docker run -it --rm $(LOCAL_LINK) $(PROJECT_NAME)

gem: image
	rm -f $(PROJECT_NAME)*.gem
	docker run $(LOCAL_LINK) $(PROJECT_NAME) gem build $(PROJECT_NAME)

# Requires rubygems be installed on host
gem_release: gem
	docker run -it --rm $(LOCAL_LINK) $(PROJECT_NAME) gem push $(PROJECT_NAME)*.gem

publish_cross_platform_image:
	(docker buildx ls | grep mybuilder) || docker buildx create --name mybuilder
	docker buildx use mybuilder
	docker buildx build --push --platform linux/amd64,linux/arm64/v8 -t kwerle/$(PROJECT_NAME) .
