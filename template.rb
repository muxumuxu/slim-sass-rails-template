def source_paths
  Array(super) + [File.expand_path(File.dirname(__FILE__))]
end

# Configure Gemfile
remove_file "Gemfile"
run "touch Gemfile"
add_source "https://rubygems.org"

gem "rails"
gem "pg"
gem "puma"
gem "rollbar"
gem "uglifier"
gem "turbolinks"
gem "jbuilder"
gem "sass-rails"
gem "slim-rails"
gem "tzinfo-data", platforms: [:mingw, :mswin, :x64_mingw, :jruby]

gem_group :development, :test do
  gem "byebug", platforms: [:mri, :mingw, :x64_mingw]
  gem "capybara"
  gem "selenium-webdriver"
  gem "pry-rails"
  gem "pry-rescue"
  gem "rubocop"
end

gem_group :development do
  gem "web-console"
  gem "better_errors"
  gem "listen"
  gem "spring"
  gem "spring-watcher-listen"
  gem "guard"
  gem "guard-minitest"
  gem "better_errors"
  gem "rails_layout"
end

gem_group :test do
  gem "minitest-reporters"
  gem "minitest-rails"
  gem "shoulda"
  gem "factory_girl_rails"
  gem "faker"
  gem "vcr"
  gem "webmock"
  gem "rails-controller-testing"
end

# Configure Docker
create_file "Dockerfile" do <<-EOF
FROM ruby:2.4.0

RUN apt-get update -qq && apt-get install -y build-essential libpq-dev nodejs

ENV APP_HOME /#{app_name}
RUN mkdir $APP_HOME
WORKDIR $APP_HOME

ADD . $APP_HOME
ENV BUNDLE_GEMFILE=$APP_HOME/Gemfile \
  BUNDLE_JOBS=2 \
  BUNDLE_PATH=/bundle
RUN bundle install

CMD bundle exec rails s -p ${PORT:-3000} -b "0.0.0.0"
EOF
end

create_file "docker-compose.yml" do <<-EOF
version: "2"
services:
  db:
    image: postgres
  web:
    build: .
    command: bundle exec rails s -p 3000 -b "0.0.0.0"
    env_file:
      - .env
    volumes:
      - .:/#{app_name}
    ports:
      - "3000:3000"
    depends_on:
      - db
EOF
end

# Configure database
inside "config" do
  remove_file "database.yml"
  create_file "database.yml" do <<-EOF
default: &default
  adapter: postgresql
  encoding: unicode
  pool: <%= ENV.fetch("RAILS_MAX_THREADS") { 5 } %>
  database: postgres
  username: postgres
  password:
  host: db

development:
  <<: *default
  database: #{app_name}_development

staging:
  <<: *default
  database: #{app_name}_staging

test:
  <<: *default
  database: #{app_name}_test
EOF
  end
end

# Configure devise
if yes?("Would you like to install Devise?")
  gem "devise"
  generate "devise:install"
  model_name = ask("What would you like the user model to be called? [user]")
  model_name = "user" if model_name.blank?
  generate "devise", model_name
end

# Add initializers
inside "config/initializers" do
  copy_file "rollbar.rb"
end

# Create .env file
create_file ".env" do <<-EOF
ROLLBAR_ACCESS_TOKEN=
EOF
end

# Replace .erb files to use .slim
inside "app/views/layouts" do
  copy_file "application.html.slim"
  copy_file "mailer.html.slim"
  remove_file "application.html.erb"
  remove_file "mailer.html.erb"
end
inside "public" do
  remove_file "404.html"
  remove_file "422.html"
  remove_file "500.html"
  copy_file "404.html.slim"
  copy_file "422.html.slim"
  copy_file "500.html.slim"
end

after_bundle do
  git :init
  git add: "."
  git commit: %Q{ -m "Initial Rails app" }

  run "heroku apps:create #{app_name}"
  run "heroku addons:create heroku-postgresql"
  run "heroku addons:create rollbar"
  run "heroku container:login"
  run "heroku container:push web"

  run "docker-compose run web bundle exec rails db:create"
  run "docker-compose up"
end