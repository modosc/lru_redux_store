# frozen_string_literal: true

require 'active_support'
require 'active_support/cache'
require 'active_support/core_ext/integer/time'
require 'objspace'
require 'sin_lru_redux'

module LruReduxStore
  # A thread-safe cache store implementation which stores everything in memory
  # in the same process, backed by LruRedux::TTL::ThreadSafeCache. Unlike
  # ActiveSupport::Cache::MemoryStore it is bounded by entry count rather than
  # estimated byte size, and eviction and expiry happen incrementally on each
  # access instead of in periodic full-cache pruning passes.
  class Store < ActiveSupport::Cache::Store
    # Creates a new store. Accepts the standard ActiveSupport::Cache::Store
    # options plus:
    #
    # * +max_size+ - the maximum number of entries (default 1000). The least
    #   recently used entry is evicted when a write would exceed it.
    # * +expires_in+ - optional TTL enforced by the backing cache. Without it
    #   entries never expire and only leave through LRU eviction.
    def initialize(options = nil)
      options ||= {}
      # dup/marshal values so the cache never shares object references with
      # callers, matching MemoryStore. pass coder: nil to store raw values
      options[:coder] = DupCoder unless options.key?(:coder) || options.key?(:serializer)
      # Disable compression by default.
      options[:compress] ||= false
      # store-level expiry is enforced solely by the backing TTL cache; keep
      # expires_in out of @options so the base class never embeds it in entries
      @expires_in = options.delete(:expires_in)
      super
      @max_size = options[:max_size] || 1000
      @data = build_data_cache

      @cache_size = 0
    end

    # Advertise cache versioning support.
    def self.supports_cache_versioning?
      true
    end

    # Delete all data stored in a given cache store.
    def clear(_options = nil)
      @data.clear
      @cache_size = 0
    end

    # Deletes cache entries if the cache key matches a given pattern.
    def delete_matched(matcher, options = nil)
      options = merged_options options
      matcher = key_matcher matcher, options

      instrument :delete_matched, matcher.inspect do
        keys = @data.to_a.map(&:first)
        keys.each do |key|
          delete_entry(key, **options) if key.match matcher
        end
      end
    end

    # Preemptively iterates through all stored keys and removes the ones which have expired.
    def cleanup(_options = nil)
      _instrument(:cleanup, size: @data.count) do
        synchronize { @data.expire }
      end
    end

    # Increment a cached integer value. Returns the updated value.
    #
    # If the key is unset, it will be set to +amount+:
    #
    #   cache.increment("foo") # => 1
    #   cache.increment("bar", 100) # => 100
    #
    # To set a specific value, call #write:
    #
    #   cache.write("baz", 5)
    #   cache.increment("baz") # => 6
    #
    def increment(name, amount = 1, **options)
      instrument(:increment, name, amount: amount) do
        modify_value(name, amount, **options)
      end
    end

    # Decrement a cached integer value. Returns the updated value.
    #
    # If the key is unset or has expired, it will be set to +-amount+.
    #
    #   cache.decrement("foo") # => -1
    #
    # To set a specific value, call #write:
    #
    #   cache.write("baz", 5)
    #   cache.decrement("baz") # => 4
    #
    def decrement(name, amount = 1, **options)
      instrument(:decrement, name, amount: amount) do
        modify_value(name, -amount, **options)
      end
    end

    # Synchronize calls to the cache. This should be called wherever the underlying cache implementation
    # is not thread safe.
    def synchronize(&) # :nodoc:
      @data.synchronize(&)
    end

    def inspect # :nodoc:
      "#<#{self.class.name} entries=#{@data.count}, size=#{@cache_size}, options=#{@options.inspect}>"
    end

    # Fixed per-entry bookkeeping cost in bytes, counted toward the reported
    # cache size on top of each key and payload. Matches MemoryStore.
    PER_ENTRY_OVERHEAD = 240

    private

    def build_data_cache
      if @expires_in
        LruRedux::TTL::ThreadSafeCache.new @max_size, @expires_in.to_f
      else
        # the TTL argument defaults to :none, and the behavior of a TTL cache
        # with the TTL set to :none is identical to the LRU cache
        LruRedux::TTL::ThreadSafeCache.new @max_size
      end
    end

    def cached_size(key, payload)
      ObjectSpace.memsize_of(key.to_s) + ObjectSpace.memsize_of(payload) + PER_ENTRY_OVERHEAD
    end

    def read_entry(key, **_options)
      deserialize_entry(@data[key])
    end

    def exists?(key, **_options)
      @data.key? key
    end

    def write_entry(key, entry, **options) # rubocop:disable Naming/PredicateMethod
      return false if options[:unless_exist] && exist?(key, namespace: nil)

      payload = serialize_entry(entry, **options)
      old_payload = @data[key]
      if old_payload
        @cache_size -= (ObjectSpace.memsize_of(old_payload) - ObjectSpace.memsize_of(payload))
      else
        @cache_size += cached_size(key, payload)
      end
      @data[key] = payload
      true
    end

    def delete_entry(key, **_options) # rubocop:disable Naming/PredicateMethod
      payload = @data.delete key
      @cache_size -= cached_size(key, payload) if payload
      !!payload
    end

    # Modifies the amount of an integer value that is stored in the cache.
    # If the key is not found it is created and set to +amount+.
    def modify_value(name, amount, **options) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
      options = merged_options options
      key     = normalize_key name, options
      version = normalize_version name, options

      synchronize do
        entry = read_entry(key, **options)

        if !entry || entry.expired? || entry.mismatched?(version)
          write(name, Integer(amount), options)
          amount
        else
          num = entry.value.to_i + amount
          entry = ActiveSupport::Cache::Entry.new(num, version: entry.version)
          write_entry(key, entry)
          num
        end
      end
    end
  end
end
