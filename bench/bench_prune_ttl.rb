# frozen_string_literal: true

require 'bundler/setup'
require 'active_support'
require 'active_support/cache'
require 'active_support/cache/memory_store'
require 'active_support/notifications'
require 'lru_redux_store'

# TTL variant of bench_prune.rb. The TTL is short enough that entries expire
# while the benchmark is still running, which is where the two stores differ
# most. MemoryStore never removes an entry at expiry: expired entries keep
# counting toward the byte cap until a read touches them or a prune's cleanup
# phase sweeps the whole cache, so expiration work arrives in the same
# synchronized bursts as eviction work. LruReduxStore's backing cache pops
# expired entries incrementally on every access instead.
#
# Capacity is calibrated the same way as bench_prune.rb: a throwaway
# MemoryStore runs the same write stream and we record how many entries it
# holds when its first prune fires, then LruReduxStore gets that number as
# max_size. Both stores also get the same TTL.

VALUE = 'x' * 100
WRITES = 200_000
MEMORY_STORE_BYTES = 4 * 1024 * 1024

# ~25ms: shorter than the time it takes either store to fill to capacity, so
# expiry is the dominant force rather than LRU eviction.
TTL = 0.025

def calibrate_capacity
  probe = ActiveSupport::Cache::MemoryStore.new(size: MEMORY_STORE_BYTES, expires_in: TTL)
  data = probe.instance_variable_get(:@data)
  pruned = false
  subscriber = ActiveSupport::Notifications.subscribe('cache_prune.active_support') { pruned = true }
  peak = 0
  writes = 0
  until pruned
    probe.write("key-#{writes}", VALUE)
    writes += 1
    peak = data.size if data.size > peak
    raise 'MemoryStore never pruned during calibration' if writes >= WRITES
  end
  [peak, writes]
ensure
  ActiveSupport::Notifications.unsubscribe(subscriber)
end

def measure_writes(store)
  latencies = Array.new(WRITES)
  WRITES.times do |i|
    key = "key-#{i}"
    t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    store.write(key, VALUE)
    latencies[i] = Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0
  end
  latencies.sort!
  {
    total: latencies.sum,
    p50: latencies[WRITES / 2],
    p99: latencies[(WRITES * 0.99).floor],
    max: latencies.last
  }
end

def report_events(name, durations, total)
  if durations.empty?
    puts "  #{name}: none"
  else
    puts format('  %s: %d, longest %.2fms, cumulative %.2fms (%.1f%% of total time)',
                name, durations.size, durations.max * 1_000, durations.sum * 1_000, (durations.sum / total) * 100)
  end
end

# MemoryStore#prune runs its cleanup pass (the expired-entry sweep of the
# whole cache) before its instrument(:prune) block starts, so prune event
# durations exclude it. cache_cleanup events are tracked separately or the
# expiry sweep cost would disappear from the numbers.
def report(label, stats, entries_at_end, prunes, cleanups)
  puts label
  puts format('  total %6.2fs   p50 %8.2fus   p99 %8.2fus   max %10.2fus',
              stats[:total], stats[:p50] * 1_000_000, stats[:p99] * 1_000_000, stats[:max] * 1_000_000)
  puts format('  entries at end: %d, evicted or expired: %d', entries_at_end, WRITES - entries_at_end)
  report_events('prune events', prunes, stats[:total])
  report_events('cleanup sweeps', cleanups, stats[:total])
  puts
end

entry_capacity, first_prune_at = calibrate_capacity

puts "** Write latency under sustained expiry pressure (#{WRITES} unique-key writes, #{(TTL * 1000).to_i}ms TTL) **"
puts
puts format('calibration: a %dmb MemoryStore holds %d entries of this shape; its first prune fired at write %d.',
            MEMORY_STORE_BYTES / 1024 / 1024, entry_capacity, first_prune_at)
puts format('LruReduxStore gets max_size %d and the same %dms TTL.', entry_capacity, (TTL * 1000).to_i)
puts

prunes = []
cleanups = []
prune_subscriber = ActiveSupport::Notifications.subscribe('cache_prune.active_support') do |_name, started, finished, _id, _payload|
  prunes << (finished - started)
end
cleanup_subscriber = ActiveSupport::Notifications.subscribe('cache_cleanup.active_support') do |_name, started, finished, _id, _payload|
  cleanups << (finished - started)
end

memory_store = ActiveSupport::Cache::MemoryStore.new(size: MEMORY_STORE_BYTES, expires_in: TTL)
stats = measure_writes(memory_store)
entries = memory_store.instance_variable_get(:@data).size
report "ActiveSupport::Cache::MemoryStore (size: #{MEMORY_STORE_BYTES / 1024 / 1024}mb, expires_in: #{TTL})",
       stats, entries, prunes, cleanups

prunes = []
cleanups = []
lru_redux_store = LruReduxStore::Store.new(max_size: entry_capacity, expires_in: TTL)
stats = measure_writes(lru_redux_store)
entries = lru_redux_store.instance_variable_get(:@data).count
report "LruReduxStore::Store (max_size: #{entry_capacity}, expires_in: #{TTL})", stats, entries, prunes, cleanups

ActiveSupport::Notifications.unsubscribe(prune_subscriber)
ActiveSupport::Notifications.unsubscribe(cleanup_subscriber)
