# docker build -t ruby_language_server .
#
# For development:
# docker run -it -v $PWD:/project -v $PWD:/tmp/src -w /tmp/src ruby_language_server sh -c 'bundle && guard'
FROM ruby:2.6-alpine
LABEL maintainer="kurt@CircleW.org"

# Needed for byebug and some other gems
RUN apk update
RUN apk add make
RUN apk add g++

WORKDIR /app

COPY Gemfile .
COPY ruby_language_server.gemspec .
COPY lib/ruby_language_server/version.rb lib/ruby_language_server/version.rb

RUN bundle install

COPY . ./

CMD ["ruby", "/app/bin/ruby_language_server"]
