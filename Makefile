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

shell: build
	docker run -it $(LOCAL_LINK) $(PROJECT_NAME) sh
