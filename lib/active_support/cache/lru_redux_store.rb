# frozen_string_literal: true

require 'lru_redux_store'

module ActiveSupport # :nodoc:
  module Cache # :nodoc:
    # Registers the store under the name ActiveSupport::Cache expects, so
    # <tt>config.cache_store = :lru_redux_store</tt> resolves to
    # LruReduxStore::Store.
    LruReduxStore = LruReduxStore::Store
  end
end
