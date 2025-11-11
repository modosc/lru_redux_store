# frozen_string_literal: true

require 'lru_redux_store'

module ActiveSupport
  module Cache
    LruReduxStore = LruReduxStore::Store
  end
end
