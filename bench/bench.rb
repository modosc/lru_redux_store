# frozen_string_literal: true

require 'bundler/setup'
require 'benchmark'
require 'lru_redux'
require 'active_support'
require 'active_support/cache'
require 'active_support/cache/memory_store'
require 'active_support/notifications'
require 'lru_redux_store'

# Raw sin_lru_redux caches, for reference.
redux_thread_safe = LruRedux::ThreadSafeCache.new(1_000)
redux_ttl_disabled = LruRedux::TTL::ThreadSafeCache.new(1_000)

# MemoryStore's 32mb default cap holds the entire rand(2_000) keyspace (~100%
# hit rate), so give LruReduxStore::Store enough slots to do the same; the
# bounded variant shows the cost of a ~50% miss rate.
memory_store = ActiveSupport::Cache::MemoryStore.new
lru_redux_store = LruReduxStore::Store.new(max_size: 2_000)
lru_redux_store_bounded = LruReduxStore::Store.new(max_size: 1_000)

puts '** LRU Benchmarks (no TTL) **'
Benchmark.bmbm do |bm|
  bm.report 'LruRedux::ThreadSafeCache' do
    1_000_000.times { redux_thread_safe.getset(rand(2_000)) { :value } }
  end

  bm.report 'LruRedux::TTL::ThreadSafeCache (TTL disabled)' do
    1_000_000.times { redux_ttl_disabled.getset(rand(2_000)) { :value } }
  end

  bm.report 'ActiveSupport::Cache::MemoryStore' do
    1_000_000.times { memory_store.fetch(rand(2_000)) { :value } }
  end

  bm.report 'LruReduxStore::Store' do
    1_000_000.times { lru_redux_store.fetch(rand(2_000)) { :value } }
  end

  bm.report 'LruReduxStore::Store (1k entries, ~50% miss)' do
    1_000_000.times { lru_redux_store_bounded.fetch(rand(2_000)) { :value } }
  end
end
