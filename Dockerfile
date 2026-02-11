# docker build -t ruby_language_server .
#
# For development:
# docker run -it -v $PWD:/project -v $PWD:/tmp/src -w /tmp/src ruby_language_server sh -c 'bundle && guard'
FROM ruby:4.0-slim
LABEL maintainer="kurt@CircleW.org"

# RUN gem update bundler - Skipping as Ruby 4.0 comes with compatible bundler

# Needed for byebug and some other gems
RUN apt-get update && apt-get install -y \
    curl make g++ sqlite3 libsqlite3-dev libyaml-dev linux-libc-dev build-essential ncurses-bin unzip pkg-config file \
    && rm -rf /var/lib/apt/lists/*
# changes as of ruby 4:
# ncurses for guard
# linux-headers to build some io code - maybe to do with sockets

WORKDIR /usr/local/src
RUN curl -O -L https://github.com/mateusza/SQLite-Levenshtein/archive/master.zip
RUN unzip master.zip
WORKDIR /usr/local/src/SQLite-Levenshtein-master
RUN ./configure
RUN make install

WORKDIR /app
RUN rm -rf /usr/local/src

# We expect the target project to be mounted here:
ENV RUBY_LANGUAGE_SERVER_PROJECT_ROOT=/project/
# ENV LOG_LEVEL DEBUG

COPY Gemfile* ruby_language_server.gemspec ./
COPY lib/ruby_language_server/version.rb lib/ruby_language_server/version.rb

RUN bundle install

COPY . ./

# We must not use bundle exec, here - we are running in the
CMD ["ruby", "/app/exe/ruby_language_server"]
