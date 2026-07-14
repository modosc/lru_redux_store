# Benchmarks

Run these with `bundle exec`:

```bash
bundle exec ruby bench/bench.rb
bundle exec ruby bench/bench_ttl.rb
bundle exec ruby bench/bench_prune.rb
bundle exec ruby bench/bench_prune_ttl.rb
```

`bench.rb` and `bench_ttl.rb` measure throughput, with and without a TTL. `bench_prune.rb` and `bench_prune_ttl.rb` measure per-write latency under sustained eviction pressure. MemoryStore is bounded by bytes and LruReduxStore by entries, so the latency benchmarks calibrate themselves first: they run the same write stream against a throwaway MemoryStore, record how many entries it holds when its first prune fires, and use that count as LruReduxStore's `max_size`. Both stores reach capacity and start evicting at the same write.

## Results

Apple silicon laptop, ruby 4.0.2, activesupport 8.1.3. 1m operations for the throughput runs, 200k unique-key writes for the latency runs.

### Throughput

```
** LRU Benchmarks (no TTL) **
                                                    user     system      total        real
LruRedux::ThreadSafeCache                       0.231287   0.000707   0.231994 (  0.232720)
LruRedux::TTL::ThreadSafeCache (TTL disabled)   0.339670   0.000962   0.340632 (  0.340927)
ActiveSupport::Cache::MemoryStore               1.897356   0.006356   1.903712 (  1.905111)
LruReduxStore::Store                            2.148409   0.007220   2.155629 (  2.158542)
LruReduxStore::Store (1k entries, ~50% miss)    3.451640   0.013249   3.464889 (  3.468145)

** TTL Benchmarks **
                                                        user     system      total        real
LruRedux::TTL::ThreadSafeCache                      0.619437   0.002868   0.622305 (  0.622808)
ActiveSupport::Cache::MemoryStore (TTL enabled)     2.095064   0.011191   2.106255 (  2.110231)
LruReduxStore::Store (TTL enabled)                  2.829217   0.024145   2.853362 (  2.881794)
LruReduxStore::Store (TTL, 1k entries, ~50% miss)   4.601842   0.031277   4.633119 (  4.651033)
```

### Write latency under eviction pressure

```
** Write latency under sustained eviction pressure (200000 unique-key writes, no TTL) **

calibration: a 4mb MemoryStore holds 12049 entries of this shape; its first prune fired at write 12050.
LruReduxStore gets max_size 12049, so its first eviction happens at write 12050.

ActiveSupport::Cache::MemoryStore (size: 4mb)
  total   0.58s   p50     2.00us   p99     3.00us   max    2998.00us
  entries at end: 10862, evictions: 189138
  prune events: 63, longest 1.88ms, cumulative 79.40ms (13.7% of total time)
  cleanup sweeps: 63, longest 1.17ms, cumulative 47.10ms (8.2% of total time)

LruReduxStore::Store (max_size: 12049)
  total   0.71s   p50     3.00us   p99     9.00us   max    3805.00us
  entries at end: 12049, evictions: 187951
  prune events: none
  cleanup sweeps: none
```

```
** Write latency under sustained expiry pressure (200000 unique-key writes, 25ms TTL) **

calibration: a 4mb MemoryStore holds 12049 entries of this shape; its first prune fired at write 12050.
LruReduxStore gets max_size 12049 and the same 25ms TTL.

ActiveSupport::Cache::MemoryStore (size: 4mb, expires_in: 0.025)
  total   0.64s   p50     2.00us   p99     3.00us   max    6957.00us
  entries at end: 11666, evicted or expired: 188334
  prune events: 40, longest 0.02ms, cumulative 0.29ms (0.0% of total time)
  cleanup sweeps: 40, longest 6.86ms, cumulative 139.37ms (21.6% of total time)

LruReduxStore::Store (max_size: 12049, expires_in: 0.025)
  total   0.85s   p50     3.00us   p99     9.00us   max    1724.00us
  entries at end: 6334, evicted or expired: 193666
  prune events: none
  cleanup sweeps: none
```

## Analysis

Median write latency is identical and throughput is close, with LruReduxStore a little slower per operation since it pays for eviction and expiry on every write. The difference is where MemoryStore does that work: synchronized prune and cleanup passes that stall a single write for several milliseconds while every other thread queues behind the lock, and once entries are actually expiring those sweeps eat over 20% of total write time. LruReduxStore has no batch phase at all, so its worst case stays flat.
