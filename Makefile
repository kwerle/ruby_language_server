PROJECT_NAME=ruby_language_server

build:
	docker build -t $(PROJECT_NAME) .

guard: build
	docker run -it -v $(PWD):/tmp/src -w /tmp/src ruby_language_server sh -c 'bundle && guard'

continuous_development: build
	echo "You are going to want to set the ide-ruby 'Image Name' to local_ruby_language_server"
	sleep 15
	while (true) ; \
	do \
	  docker build -t local_ruby_language_server . ; \
	  sleep 2 ; \
	done
