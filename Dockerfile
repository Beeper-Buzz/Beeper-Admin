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

# Compile Sprockets assets into public/assets here, at image build time, so a
# booting web dyno never runs the precompile (it used to, on every boot, and
# pushed a 512 MB dyno to ~950 MB with R14s and H12s until it finished).
# Heroku docker builds don't see the app's config vars: nothing here may need a
# database, AWS, Sentry, SMTP or Redis. These variables apply to this RUN only.
# The DATABASE_URL points at a dead port so any boot-time query fails the build
# instead of passing silently; ASSETS_PRECOMPILE=1 turns off Spree's database
# backed preferences for this process (config/initializers/spree.rb). Removing
# tmp/cache keeps the Sprockets and Rails.cache files out of the image.
RUN ASSETS_PRECOMPILE=1 \
    SECRET_KEY_BASE=precompile-dummy \
    DATABASE_URL=postgres://precompile@127.0.0.1:1/precompile \
    RAILS_ENV=production \
    bundle exec rake assets:precompile \
    && rm -rf tmp/cache

# Caps glibc malloc arenas: Ruby's threads otherwise each grow their own arena
# and RSS bloats well past what the heap needs.
ENV MALLOC_ARENA_MAX=2

EXPOSE 3000
CMD ["bundle", "exec", "rails", "server", "-b", "0.0.0.0"]
