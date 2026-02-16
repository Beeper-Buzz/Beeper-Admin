FROM ruby:2.7.2

# Fix Debian repository URLs for old Buster image (EOL)
RUN sed -i 's|http://deb.debian.org|http://archive.debian.org|g' /etc/apt/sources.list && \
    sed -i 's|http://security.debian.org|http://archive.debian.org|g' /etc/apt/sources.list && \
    sed -i '/security.debian.org/d' /etc/apt/sources.list

RUN apt-get update -qq && apt-get install -y build-essential libpq-dev nodejs

RUN mkdir /beeper-admin
WORKDIR /beeper-admin

COPY Gemfile /beeper-admin/Gemfile
COPY Gemfile.lock /beeper-admin/Gemfile.lock

RUN bundle install

COPY . /beeper-admin

# Precompile assets for production
RUN RAILS_ENV=production SECRET_KEY_BASE=dummy bundle exec rake assets:precompile

EXPOSE 3000
CMD ["bundle", "exec", "rails", "server", "-b", "0.0.0.0"]