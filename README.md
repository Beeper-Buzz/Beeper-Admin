# Material Instinct LLC - DNA Boilerplate for Admin UI

Running the app locally (w/o Docker):

Requirements: ruby 2.6.2, rails 5.2.2, Postgres

1. Clone this repo
1. Copy `.env.example` to `.env.development`
1. Copy app secrets from shared Dashlane.app secure note into `.env.development`
1. Create a local postgres database
1. Grant all privileges to the database
1. Make sure the database creds match those in `.env.development`
1. Run `bundle install`
1. Run `rails g spree:install --user_class=Spree::User` (say "no" to all overwrites)
1. Run `rails g spree:auth:install` (say "no" to all overwrites)
1. Run `rails g spree_gateway:install`
1. Run `rails g spree_i18n:install` (Optional)
1. Run `rails s`

---

Other things we may need to cover:

* Ruby version

* System dependencies

* Configuration

* Database creation

* Database initialization

* How to run the test suite

* Services (job queues, cache servers, search engines, etc.)

* Deployment instructions

* ...
