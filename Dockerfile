# docker build -t ruby_language_server .
#
# For development:
# docker run -it -v $PWD:/project -v $PWD:/tmp/src -w /tmp/src ruby_language_server sh -c 'bundle && guard'
FROM ruby:3.0-alpine
LABEL maintainer="kurt@CircleW.org"

RUN gem update bundler

# Needed for byebug and some other gems
RUN apk update
RUN apk add curl make g++ sqlite-dev

WORKDIR /usr/local/src
RUN curl -O -L https://github.com/mateusza/SQLite-Levenshtein/archive/master.zip
RUN unzip master.zip
WORKDIR /usr/local/src/SQLite-Levenshtein-master
RUN ./configure
RUN make -j 8 install

WORKDIR /app

# We expect the target project to be mounted here:
ENV RUBY_LANGUAGE_SERVER_PROJECT_ROOT /project/
# ENV LOG_LEVEL DEBUG

COPY Gemfile* ./
COPY ruby_language_server.gemspec .
COPY lib/ruby_language_server/version.rb lib/ruby_language_server/version.rb

RUN bundle install -j 8

COPY . ./

# We must not use bundle exec, here - we are running in the
CMD ["ruby", "/app/exe/ruby_language_server"]
