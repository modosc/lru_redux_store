# frozen_string_literal: true

lib = File.expand_path('lib', __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'lru_redux_store/version'

Gem::Specification.new do |spec|
  spec.name = 'lru_redux_store'
  spec.version = LruReduxStore::VERSION
  spec.authors = ['jonathan schatz']
  spec.email = ['modosc@users.noreply.github.com']

  spec.summary = 'An ActiveSupport::Cache::Store backed by sin_lru_redux.'
  spec.description = 'A bounded, thread-safe, in-memory cache store for Rails. ' \
                     'Backed by sin_lru_redux for O(1) LRU eviction with optional TTL, ' \
                     'it stores raw values with no serialization and emits the same ' \
                     'interface as ActiveSupport::Cache::Store.'
  spec.homepage = 'https://github.com/modosc/lru_redux_store'
  spec.required_ruby_version = '>= 3.3.0'

  spec.metadata['allowed_push_host'] = 'https://rubygems.org'
  spec.metadata['homepage_uri'] = spec.homepage
  spec.metadata['source_code_uri'] = 'https://github.com/modosc/lru_redux_store'
  spec.metadata['rubygems_mfa_required'] = 'true'

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  File.basename(__FILE__)
  spec.files = `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  spec.bindir = 'exe'
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ['lib']
  spec.add_development_dependency 'appraisal', '~> 2.5.0'
  spec.add_development_dependency 'benchmark'
  spec.add_development_dependency 'bundler', '>= 2.4.18'
  spec.add_development_dependency 'pry-byebug'
  spec.add_development_dependency 'rake', '~> 13.4.0'
  spec.add_development_dependency 'rspec', '~> 3.13.0'
  spec.add_development_dependency 'rspec-rails', '~> 8.0.2'
  spec.add_development_dependency 'rubocop', '~> 1.88.2'
  spec.add_development_dependency 'rubocop-performance', '~> 1.26.0'
  spec.add_development_dependency 'rubocop-rails', '~> 2.35.5'
  spec.add_development_dependency 'rubocop-rspec', '~> 3.10.2'
  spec.add_dependency 'activesupport', '>= 7.2.0'
  spec.add_dependency 'sin_lru_redux', '>= 2.5.2'
  spec.add_dependency 'zeitwerk', '>= 2.5.0'
  # Uncomment to register a new dependency of your gem
  # spec.add_dependency "example-gem", "~> 1.0"

  # For more information and examples about making a new gem, check out our
  # guide at: https://bundler.io/guides/creating_gem.html
end
