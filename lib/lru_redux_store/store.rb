# frozen_string_literal: true

require 'active_support/cache'
require 'active_support/core_ext/integer/time'
require 'sin_lru_redux'

module LruReduxStore
  class Store < ActiveSupport::Cache::Store
    def initialize(options = nil)
      options ||= {}
      # no coder supported since we want to store raw values
      options[:coder] = nil
      # Disable compression
      options[:compress] = false
      super
      @max_size = options[:max_size] || 1000
      @expires_in = options[:expires_in] || 5.minutes
      @data = LruRedux::TTL::ThreadSafeCache.new @max_size, @expires_in.seconds

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
        @data.each_key do |key, _|
          delete_entry(key, **options) if key.match matcher
        end
      end
    end

    def inspect # :nodoc:
      "#<#{self.class.name} entries=#{@data.count}, size=#{@cache_size}, options=#{@options.inspect}>"
    end

    private

    PER_ENTRY_OVERHEAD = 240

    def cached_size(key, payload)
      ObjectSpace.memsize_of(key.to_s) + ObjectSpace.memsize_of(payload) + PER_ENTRY_OVERHEAD
    end

    def read_entry(key, **_options)
      @data[key]
    end

    def exists?(key, **_options)
      @data.key? key
    end

    def write_entry(key, entry, **options)
      return false if options[:unless_exist] && exist?(key, namespace: nil)

      payload = entry
      old_payload = @data[key]
      if old_payload
        @cache_size -= (ObjectSpace.memsize_of(old_payload) - ObjectSpace.memsize_of(payload))
      else
        @cache_size += cached_size(key, payload)
      end
      @data[key] = payload
    end

    def delete_entry(key, **_options)
      payload = @data.delete key
      @cache_size -= cached_size(key, payload) if payload
      !!payload
    end
  end
end
