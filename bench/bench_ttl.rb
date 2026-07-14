# frozen_string_literal: true

require 'bundler/setup'
require 'benchmark'
require 'lru_redux'
require 'active_support'
require 'active_support/cache'
require 'active_support/cache/memory_store'
require 'active_support/notifications'
require 'lru_redux_store'

TTL = 5 * 60

# Raw sin_lru_redux TTL cache, for reference.
redux_ttl_thread_safe = LruRedux::TTL::ThreadSafeCache.new(1_000, TTL)

# Same keyspace/capacity reasoning as bench.rb: 2k slots for the head-to-head
# with MemoryStore, 1k for the bounded ~50% miss variant.
memory_store = ActiveSupport::Cache::MemoryStore.new(expires_in: TTL)
lru_redux_store = LruReduxStore::Store.new(max_size: 2_000, expires_in: TTL)
lru_redux_store_bounded = LruReduxStore::Store.new(max_size: 1_000, expires_in: TTL)

puts '** TTL Benchmarks **'
Benchmark.bmbm do |bm|
  bm.report 'LruRedux::TTL::ThreadSafeCache' do
    1_000_000.times { redux_ttl_thread_safe.getset(rand(2_000)) { :value } }
  end

  bm.report 'ActiveSupport::Cache::MemoryStore (TTL enabled)' do
    1_000_000.times { memory_store.fetch(rand(2_000)) { :value } }
  end

  bm.report 'LruReduxStore::Store (TTL enabled)' do
    1_000_000.times { lru_redux_store.fetch(rand(2_000)) { :value } }
  end

  bm.report 'LruReduxStore::Store (TTL, 1k entries, ~50% miss)' do
    1_000_000.times { lru_redux_store_bounded.fetch(rand(2_000)) { :value } }
  end
end
