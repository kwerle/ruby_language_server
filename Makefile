PROJECT_NAME=ruby_language_server
LOCAL_LINK=-v $(PWD):/tmp/src -w /tmp/src

build:
	docker build -t $(PROJECT_NAME) .

guard: build
	docker run -it $(LOCAL_LINK) $(PROJECT_NAME) sh -c 'bundle && guard'

continuous_development: build
	echo "You are going to want to set the ide-ruby 'Image Name' to local_ruby_language_server"
	sleep 15
	while (true) ; \
	do \
	  docker build -t local_ruby_language_server . ; \
	  sleep 2 ; \
	done

console: build
	docker run -it $(LOCAL_LINK) $(PROJECT_NAME) bin/console

test: build
	docker run -it $(LOCAL_LINK) $(PROJECT_NAME) rake test && rubocop -c .rubocop_ruby_language_parser.yml

shell: build
	docker run -it $(LOCAL_LINK) $(PROJECT_NAME) sh

# Just to make sure it works.
server: build
	docker run -it $(LOCAL_LINK) $(PROJECT_NAME)

gem: build
	rm -f $(PROJECT_NAME)*.gem
	docker run $(LOCAL_LINK) $(PROJECT_NAME) gem build $(PROJECT_NAME)

# Requires rubygems be installed on host
gem_release: gem
	gem push $(PROJECT_NAME)*.gem
