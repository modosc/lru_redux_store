# LruReduxStore

This gem provides an [`ActiveSupport::Cache::Store`](https://api.rubyonrails.org/classes/ActiveSupport/Cache/Store.html) implementation backed by [`sin_lru_redux`](https://github.com/cadenza-tech/sin_lru_redux), an "efficient and thread-safe LRU cache". It's a drop-in alternative to `ActiveSupport::Cache::MemoryStore` that's bounded by entry count instead of estimated byte size.

## Requirements

This gem requires `activesupport` >= `7.2` and `ruby` >= `3.3`.

## Installation

Install the gem and add to the application's Gemfile by executing:

```bash
bundle add lru_redux_store
```

If bundler is not being used to manage dependencies, install the gem by executing:

```bash
gem install lru_redux_store
```

## Problem

`ActiveSupport::Cache::MemoryStore` does its housekeeping in batches. Expired entries pile up until a write pushes the cache over its size cap, and that write then sweeps the whole cache: it scans every entry for expired ones and deletes least recently used entries until enough space is free. The sweep runs while holding the lock every other cache operation needs, so one unlucky request stalls for the whole thing and every concurrent request queues behind it.

This gem does the same housekeeping incrementally. Each access evicts whatever has already expired, and a write that overflows `max_size` evicts a single entry, so the work is spread across every operation instead of concentrated in occasional pauses.

## How it works

The store keeps its data in a `LruRedux::TTL::ThreadSafeCache`. `max_size` caps the number of entries. When a write would exceed it, the least recently used entry is evicted.

If you pass `expires_in` the backing cache enforces it as a Time To Live eviction strategy. TTL eviction occurs on every access and takes precedence over LRU eviction, meaning a 'live' value will never be evicted over an expired one. `cleanup` triggers a TTL eviction manually. Without `expires_in` the behavior is identical to a plain LRU cache: nothing ever expires and entries only leave through LRU eviction, `delete`, `delete_matched`, or `clear`.

Values are copied on the way in and out, matching `MemoryStore`. The coder is a vendored copy of `MemoryStore`'s `DupCoder`: strings are duplicated and everything else takes a `Marshal` round-trip, so a write stores a private copy and every read returns a fresh one. Mutating a value you got from `fetch` never affects other readers.

Like `MemoryStore` this cache is per-process. Each process gets its own copy and they don't talk to each other, so don't use it for anything that needs to be consistent across processes.

`increment`, `decrement`, `delete_matched`, and `cleanup` are all supported and emit the same `cache_*` instrumentation events as `MemoryStore`, so `ActiveSupport::Notifications` subscribers and log subscribers work unchanged.

## Usage

```ruby
config.cache_store = :lru_redux_store, { max_size: 10_000, expires_in: 1.hour }
```

Both options are optional. `max_size` defaults to `1000`. Leave `expires_in` off and entries never expire, they just age out of the LRU.

You can also use the store directly:

```ruby
cache = LruReduxStore::Store.new(max_size: 10_000)
cache.fetch('some-key') { expensive_computation }
```

`expires_in` passed to an individual `write` or `fetch` call is honored the same way it is with any other cache store.

## Benchmarks

tl;dr - this gem trades a little per-operation speed for the absence of large pauses

See [bench/README.md](bench/README.md) for the setup and full numbers. Reads and writes are slightly slower than `MemoryStore` because eviction and expiry work happens on every operation, but there's never a full-cache sweep, so worst-case latency stays flat where `MemoryStore` stalls for several milliseconds at a time (in the TTL benchmark those sweeps eat over 20% of total write time).

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/modosc/lru_redux_store.
