# https://docs.docker.com/compose/rails/#define-the-project
FROM ruby:2.7.2
# Fix Debian repository URLs for old Buster image
RUN sed -i 's|http://deb.debian.org|http://archive.debian.org|g' /etc/apt/sources.list && \
    sed -i 's|http://security.debian.org|http://archive.debian.org|g' /etc/apt/sources.list && \
    sed -i '/security.debian.org/d' /etc/apt/sources.list
# The qq is for silent output in the console
RUN apt-get update -qq && apt-get install -y \
    build-essential \
    libpq-dev \
    nodejs \
    npm \
    curl \
    && rm -rf /var/lib/apt/lists/*

RUN apt-get update -qq && apt-get install -y build-essential libpq-dev nodejs

RUN mkdir /beeper-admin
WORKDIR /beeper-admin

COPY Gemfile /beeper-admin/Gemfile
COPY Gemfile.lock /beeper-admin/Gemfile.lock

# Install exactly what the committed Gemfile.lock pins. BUNDLE_FROZEN makes the
# build fail if Gemfile and Gemfile.lock disagree instead of re-resolving to the
# newest gems (an unpinned resolve once pulled json 3.x and broke migrations).
ENV BUNDLE_FROZEN=true
RUN gem install bundler -v 2.4.22 && bundle install

COPY . /beeper-admin

# Re-check the copied app against the lock (frozen: never rewrites Gemfile.lock)
RUN bundle install

EXPOSE 3000
CMD ["bundle", "exec", "rails", "server", "-b", "0.0.0.0"]
