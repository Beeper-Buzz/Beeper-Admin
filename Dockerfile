FROM ruby:2.7.2

RUN apt-get update -qq && apt-get install -y build-essential libpq-dev nodejs

RUN mkdir /beeper-admin
WORKDIR /beeper-admin

COPY Gemfile /beeper-admin/Gemfile
COPY Gemfile.lock /beeper-admin/Gemfile.lock

RUN bundle install

COPY . /beeper-admin

EXPOSE 3000
CMD ["bundle", "exec", "rails", "server", "-b", "0.0.0.0"]