# docker build -t ruby_language_server .
#
# For development:
# docker run -it -v $PWD:/tmp/src -w /tmp/src ruby_language_server guard
FROM ruby

WORKDIR /app

COPY lib/ruby_language_server/version.rb lib/ruby_language_server/
COPY Gemfile ruby_language_server.gemspec ./

RUN bundle install

COPY . ./

CMD ["bash"]
