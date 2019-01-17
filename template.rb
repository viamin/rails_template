# frozen_string_literal: true

gem 'devise'
gem 'devise-jwt'
gem 'pundit'
gem 'rolify'
gem 'strong_migrations'

gem_group :development, :test do
  gem 'annotate'
  gem 'database_cleaner'
  gem 'guard', '~> 2'
  gem 'guard-brakeman'
  gem 'guard-fasterer'
  gem 'guard-foreman'
  gem 'guard-rspec'
  gem 'guard-rubocop'
  gem 'factory_bot_rails'
  gem 'faker'
  gem 'fuubar'
  gem 'rails_logtruncate'
  gem 'rspec-rails'
  gem 'rubocop-rspec'
  gem 'terminal-notifier'
  gem 'terminal-notifier-guard'
end

gem_group :development do
  gem 'foreman'
  gem 'rails_dev_ssl'
end

gem_group :test do
  gem 'pundit-matchers'
  gem 'simplecov'
end

puma_port = ask('What port do you want to use for your app server? [3000]')
puma_port = 3000 if puma_port =~ /\s*/
file 'Procfile.dev', <<~CODE
  web:          bundle exec puma -C config/puma.rb -b 'ssl://127.0.0.1:#{puma_port}?key=./ssl/server.key&cert=./ssl/server.crt'
  db:           postgres -D /usr/local/var/postgres
  redis:        redis-server /usr/local/etc/redis.conf
  # mailcatcher:  bundle exec subcontract -- mailcatcher --foreground
CODE

file '.rubocop.yml', <<~CODE
  inherit_from: ./config/rubocop.yml
  require: rubocop-rspec

  AllCops:
    Exclude:
      - bin/*
      - db/**/*
      - script/**/*
      - vendor/bundle/**/*
CODE

file 'config/rubocop.yml', <<~CODE
  Layout/AlignHash:
    Exclude:
      - lib/tasks/auto_annotate_models.rake
  Metrics/BlockLength:
    Exclude:
      - Guardfile
      - lib/tasks/*
  Metrics/LineLength:
    Max: 92
    Exclude:
      - Gemfile
      - Guardfile
      - Rakefile
      - config/environments/*
      - config/initializers/*
  Naming/FileName:
    Exclude:
      - Guardfile
      - Gemfile
  Rails:
    Enabled: true
  Rails/TimeZone:
    EnforcedStyle: strict
  Rails/Date:
    EnforcedStyle: strict
  Style/BlockComments:
    Exclude:
      - spec/spec_helper.rb
  Style/ClassAndModuleChildren:
    Enabled: false
  Style/Documentation:
    Exclude:
      - app/helpers/*
      - app/mailers/application_mailer.rb
      - app/models/application_record.rb
      - config/**/*
CODE

file 'Guardfile', <<~CODE
  directories(%w[app lib config spec].select { |d| Dir.exist?(d) ? d : UI.warning(format('Directory %<dir>s does not exist', dir: d)) })
  ignore %r{^lib/templates/}

  guard 'brakeman', run_on_start: true do
    watch(%r{^app/.+.(erb|haml|rhtml|rb)$})
    watch(%r{^config/.+.rb$})
    watch(%r{^lib/.+.rb$})
    watch('Gemfile')
  end

  guard 'fasterer' do
    watch(%r{^app/.*.rb})
  end

  guard :foreman, procfile: 'Procfile.dev' do
    watch(%r{^app/(controllers|models|helpers)/.+.rb$})
    watch(%r{^lib/.+.rb$})
    watch(%r{^config/*})
  end

  guard :rspec, cmd: 'bin/rspec' do
    require 'guard/rspec/dsl'
    dsl = Guard::RSpec::Dsl.new(self)

    # RSpec files
    rspec = dsl.rspec
    watch(rspec.spec_helper) { rspec.spec_dir }
    watch(rspec.spec_support) { rspec.spec_dir }
    watch(rspec.spec_files)

    # Ruby files
    ruby = dsl.ruby
    dsl.watch_spec_files_for(ruby.lib_files)

    # Rails files
    rails = dsl.rails(view_extensions: %w[erb haml slim])
    dsl.watch_spec_files_for(rails.app_files)
    dsl.watch_spec_files_for(rails.views)

    watch(rails.controllers) do |controller|
      [
        rspec.spec.call(format('routing/%<controller>s_routing', controller: controller[1])),
        rspec.spec.call(format('controllers/%<controller>s_controller', controller: controller[1])),
        rspec.spec.call(format('acceptance/%<controller>s', controller: controller[1]))
      ]
    end

    # Rails config changes
    watch(rails.spec_helper)     { rspec.spec_dir }
    watch(rails.routes)          { format('%<controller>s/routing', controller: rspec.spec_dir) }
    watch(rails.app_controller)  { format('%<controller>s/controllers', controller: rspec.spec_dir) }

    # Capybara features specs
    watch(rails.view_dirs)     { |view| rspec.spec.call(format('features/%<view>', view: view[1])) }
    watch(rails.layouts)       { |layout| rspec.spec.call(format('features/%<layout>s', layout: layout[1])) }

    # Turnip features and steps
    watch(%r{^spec/acceptance/(.+).feature$})
    watch(%r{^spec/acceptance/steps/(.+)_steps.rb$}) do |model|
      Dir[File.join(format('**/%<model>s.feature', model: model[1]))][0] || 'spec/acceptance'
    end
  end

  guard :rubocop, cli: ['--rails', '--format', 'fuubar', '--display-cop-names', '--auto-correct'] do
    watch(/.+.rb$/)
    watch(%r{(?:.+/)?.rubocop(?:_todo)?.yml$}) { |m| File.dirname(m[0]) }
  end
CODE

after_bundle do
  generate('rspec:install')
  run 'bundle exec guard init'
  run 'bundle exec guard init rspec'
  run 'bundle exec guard init rubocop'
  run 'bundle exec guard init fasterer'
  run 'bundle exec guard init brakeman'
  run 'bundle exec guard init foreman'
  run 'bundle exec rails_dev_ssl generate_certificates'
  run 'rm -rf test/'
  rails_command 'app:update:bin'
  run 'bundle exec spring binstub --all'

  generate('annotate:install')
  generate('devise:install')

  devise_user = ask('What is your Devise User model? [User]')
  devise_user = 'user' if devise_user =~ /\s*/
  generate("devise #{devise_user}")

  file '.rspec', <<~CODE
    --color
    --require rails_helper
    --format Fuubar
  CODE

  run 'bundle exec rubocop -a'

  run 'bundle exec rails_dev_ssl add_ca_to_keychain' if yes?('Add generated rootCA to macOS keychain?')
end
