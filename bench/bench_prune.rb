# frozen_string_literal: true

require 'bundler/setup'
require 'active_support'
require 'active_support/cache'
require 'active_support/cache/memory_store'
require 'active_support/notifications'
require 'lru_redux_store'

# MemoryStore prunes when a write pushes its estimated byte size over the cap:
# that write runs cleanup (a scan of every entry in the cache) and then deletes
# least recently used entries one at a time until the size is back under 75% of
# the cap, all while holding the monitor every other cache operation needs.
#
# The two stores bound themselves differently (bytes vs entries), so to keep
# the comparison as close as possible the entry cap is calibrated rather than
# assumed: a throwaway MemoryStore runs the same write stream and we record how
# many entries it actually holds when its first prune fires. LruReduxStore gets
# that number as max_size, so both stores reach capacity and start evicting at
# the same write index. The remaining difference is the thing being measured:
# MemoryStore evicts ~25% of the cache in one synchronized burst, LruReduxStore
# evicts one entry per write.

VALUE = 'x' * 100
WRITES = 200_000
MEMORY_STORE_BYTES = 4 * 1024 * 1024

def calibrate_capacity
  probe = ActiveSupport::Cache::MemoryStore.new(size: MEMORY_STORE_BYTES)
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
# durations exclude it. cache_cleanup events are tracked separately or that
# sweep cost would disappear from the numbers.
def report(label, stats, entries_at_end, prunes, cleanups)
  puts label
  puts format('  total %6.2fs   p50 %8.2fus   p99 %8.2fus   max %10.2fus',
              stats[:total], stats[:p50] * 1_000_000, stats[:p99] * 1_000_000, stats[:max] * 1_000_000)
  puts format('  entries at end: %d, evictions: %d', entries_at_end, WRITES - entries_at_end)
  report_events('prune events', prunes, stats[:total])
  report_events('cleanup sweeps', cleanups, stats[:total])
  puts
end

entry_capacity, first_prune_at = calibrate_capacity

puts "** Write latency under sustained eviction pressure (#{WRITES} unique-key writes, no TTL) **"
puts
puts format('calibration: a %dmb MemoryStore holds %d entries of this shape; its first prune fired at write %d.',
            MEMORY_STORE_BYTES / 1024 / 1024, entry_capacity, first_prune_at)
puts format('LruReduxStore gets max_size %d, so its first eviction happens at write %d.',
            entry_capacity, entry_capacity + 1)
puts

prunes = []
cleanups = []
prune_subscriber = ActiveSupport::Notifications.subscribe('cache_prune.active_support') do |_name, started, finished, _id, _payload|
  prunes << (finished - started)
end
cleanup_subscriber = ActiveSupport::Notifications.subscribe('cache_cleanup.active_support') do |_name, started, finished, _id, _payload|
  cleanups << (finished - started)
end

memory_store = ActiveSupport::Cache::MemoryStore.new(size: MEMORY_STORE_BYTES)
stats = measure_writes(memory_store)
entries = memory_store.instance_variable_get(:@data).size
report "ActiveSupport::Cache::MemoryStore (size: #{MEMORY_STORE_BYTES / 1024 / 1024}mb)",
       stats, entries, prunes, cleanups

prunes = []
cleanups = []
lru_redux_store = LruReduxStore::Store.new(max_size: entry_capacity)
stats = measure_writes(lru_redux_store)
entries = lru_redux_store.instance_variable_get(:@data).count
report "LruReduxStore::Store (max_size: #{entry_capacity})", stats, entries, prunes, cleanups

ActiveSupport::Notifications.unsubscribe(prune_subscriber)
ActiveSupport::Notifications.unsubscribe(cleanup_subscriber)
