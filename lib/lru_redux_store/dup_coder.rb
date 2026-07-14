# frozen_string_literal: true

module LruReduxStore
  # Vendored copy of ActiveSupport::Cache::MemoryStore::DupCoder (activesupport
  # 8.1.3, MIT license). DupCoder is :nodoc: internal API, so we carry our own
  # copy rather than referencing it:
  # https://github.com/rails/rails/blob/v8.1.3/activesupport/lib/active_support/cache/memory_store.rb
  #
  # Dups string values and marshals everything else so the cache never shares
  # object references with callers. A write stores a private copy and every
  # read returns a fresh one.
  module DupCoder # :nodoc:
    extend self

    MARSHAL_SIGNATURE = "\x04\x08".b.freeze

    def dump(entry)
      if entry.value && entry.value != true && !entry.value.is_a?(Numeric)
        ActiveSupport::Cache::Entry.new(dump_value(entry.value), expires_at: entry.expires_at, version: entry.version)
      else
        entry
      end
    end

    def dump_compressed(entry, threshold)
      compressed_entry = entry.compressed(threshold)
      compressed_entry.compressed? ? compressed_entry : dump(entry)
    end

    def load(entry)
      if !entry.compressed? && entry.value.is_a?(String)
        ActiveSupport::Cache::Entry.new(load_value(entry.value), expires_at: entry.expires_at, version: entry.version)
      else
        entry
      end
    end

    private

    def dump_value(value)
      if value.is_a?(String) && !value.start_with?(MARSHAL_SIGNATURE)
        value.dup
      else
        Marshal.dump(value)
      end
    end

    def load_value(string)
      if string.start_with?(MARSHAL_SIGNATURE)
        # only strings produced by dump_value above carry the marshal
        # signature, so this never loads untrusted external data
        Marshal.load(string) # rubocop:disable Security/MarshalLoad
      else
        string.dup
      end
    end
  end
end
