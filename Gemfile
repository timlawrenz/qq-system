# frozen_string_literal: true

source 'https://rubygems.org'
git_source(:github) { |repo| "https://github.com/#{repo}.git" }

ruby '3.4.5'

gem 'aasm'
gem 'alpaca-trade-api'
gem 'bcrypt', '~> 3.1.7'
gem 'bootsnap', require: false
gem 'connection_pool'
gem 'faraday'
gem 'gl_command'
gem 'packs-rails'
gem 'pg'
gem 'puma'
gem 'rails', '~> 8.0.0'
gem 'sentry-rails'
gem 'sentry-ruby'
gem 'solid_queue', '~> 1.2'
gem 'state_machines-activerecord'
gem 'view_component'

group :development, :test do
  gem 'brakeman'
  gem 'dotenv-rails'
  gem 'reek'
  gem 'rspec-rails'
  gem 'rubocop', require: false
  gem 'rubocop-capybara', require: false
  gem 'rubocop-factory_bot', require: false
  gem 'rubocop-performance', require: false
  gem 'rubocop-rails', require: false
  gem 'rubocop-rake', require: false
  gem 'rubocop-rspec', require: false
  gem 'rubocop-rspec_rails', require: false
  gem 'timecop'
end

group :test do
  gem 'capybara'
  gem 'capybara-screenshot'
  gem 'climate_control'
  gem 'database_cleaner'
  gem 'database_cleaner-active_record'
  gem 'factory_bot_rails'
  gem 'launchy'
  gem 'selenium-webdriver'
  gem 'shoulda-matchers'
  gem 'simplecov', require: false
  gem 'vcr'
  gem 'webmock'
end
