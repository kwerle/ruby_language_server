# docker build -t ruby_language_server .
#
# For development:
# docker run -it --user root -v $PWD:/project -v $PWD:/tmp/src -w /tmp/src ruby_language_server sh -c 'bundle && guard'
#
# The server runs as UID 1000 and writes only to /data, so it can run locked down:
# docker run --rm -i --read-only --tmpfs /data:uid=1000,gid=1000 --mount type=bind,source="$PWD",target=/project,readonly ruby_language_server
FROM ruby:4.0-slim
LABEL maintainer="kurt@CircleW.org"

# RUN gem update bundler - Skipping as Ruby 4.0 comes with compatible bundler

# Needed for byebug and some other gems
RUN apt-get update && apt-get install -y \
    curl make g++ sqlite3 libsqlite3-dev libyaml-dev linux-libc-dev build-essential ncurses-bin unzip pkg-config file git \
    && rm -rf /var/lib/apt/lists/*
# changes as of ruby 4:
# ncurses for guard
# linux-headers to build some io code - maybe to do with sockets
# git for bundle-audit to fetch ruby-advisory-db (make audit)

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

# Everything the server writes goes here, so the rest of the filesystem can be read-only:
# docker run --read-only --tmpfs /data:uid=1000,gid=1000 ...
ENV RUBY_LANGUAGE_SERVER_DATA_DIR=/data
RUN groupadd --gid 1000 rls \
    && useradd --uid 1000 --gid rls --no-create-home --home-dir /data --shell /usr/sbin/nologin rls \
    && mkdir -p /data && chown rls:rls /data
USER 1000:1000

# We must not use bundle exec, here - we are running in the
CMD ["ruby", "/app/exe/ruby_language_server"]
