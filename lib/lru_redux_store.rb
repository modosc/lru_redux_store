# frozen_string_literal: true

require 'zeitwerk'
loader = Zeitwerk::Loader.for_gem
loader.ignore("#{__dir__}/active_support")
loader.setup

require 'active_support/cache'

# An ActiveSupport::Cache::Store implementation backed by sin_lru_redux, an
# efficient and thread-safe LRU cache. See LruReduxStore::Store.
module LruReduxStore
end

loader.eager_load
