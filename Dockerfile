# docker build -t ruby_language_server .
#
# For development:
# docker run -it -v $PWD:/tmp/src -w /tmp/src ruby_language_server sh -c 'bundle && guard'
FROM ruby:alpine
LABEL maintainer="kurt@CircleW.org"

# Needed for byebug and some other gems
RUN apk update
RUN apk add make
# RUN apk add gcc
RUN apk add g++

WORKDIR /app

COPY Gemfile .

RUN bundle install

COPY . ./

CMD ["ruby", "bin/ruby_language_server"]
