# frozen_string_literal: true

require 'spec_helper'
require 'active_support/cache/lru_redux_store'

RSpec.describe LruReduxStore::Store do
  let(:store) { described_class.new }

  # Capture ActiveSupport::Notifications events emitted while the block runs.
  def capture_events(pattern = /\Acache_/)
    events = []
    subscriber = ActiveSupport::Notifications.subscribe(pattern) do |name, _start, _finish, _id, payload|
      events << [name, payload]
    end
    yield
    events
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber)
  end

  # Both the store's entries and the backing cache's TTL sweep read Time.now,
  # so stubbing it fast-forwards expiry deterministically.
  def time_travel(to)
    allow(Time).to receive(:now).and_return(to)
  end

  it 'inherits from ActiveSupport::Cache::Store' do
    expect(store).to be_a(ActiveSupport::Cache::Store)
  end

  it 'is aliased as ActiveSupport::Cache::LruReduxStore' do
    expect(ActiveSupport::Cache::LruReduxStore).to be(described_class)
  end

  describe '.supports_cache_versioning?' do
    it 'returns true' do
      expect(described_class.supports_cache_versioning?).to be(true)
    end
  end

  describe '#initialize' do
    it 'defaults to no TTL on the backing cache' do
      expect(store.instance_variable_get(:@data).ttl).to be(:none)
    end

    it 'passes expires_in to the backing cache as a plain Float, not a Duration' do
      backing = described_class.new(expires_in: 5.minutes).instance_variable_get(:@data)
      expect(backing.ttl).to be(300.0)
    end

    it 'honours a numeric expires_in' do
      backing = described_class.new(expires_in: 60).instance_variable_get(:@data)
      expect(backing.ttl).to be(60.0)
    end

    it 'does not embed store-level expiry in entries (the backing cache enforces TTL)' do
      custom = described_class.new(expires_in: 60)
      custom.write('key', 'value')
      entry = custom.instance_variable_get(:@data)['key']
      expect(entry.expires_at).to be_nil
    end

    it 'stores a copy of the value, not a reference' do
      value = +'value'
      store.write('key', value)
      value << ' mutated'
      expect(store.read('key')).to eq('value')
    end

    it 'returns a fresh copy on every read' do
      store.write('key', [1, 2, 3])
      store.read('key') << 4
      expect(store.read('key')).to eq([1, 2, 3])
    end

    it 'stores raw references when coder: nil is passed' do
      raw = described_class.new(coder: nil)
      object = Object.new
      raw.write('key', object)
      expect(raw.read('key')).to equal(object)
    end

    it 'compresses large values when compression is enabled' do
      compressing = described_class.new(compress: true, compress_threshold: 1)
      compressing.write('key', 'x' * 1000)
      expect(compressing.read('key')).to eq('x' * 1000)
    end

    it 'skips compression below the threshold' do
      compressing = described_class.new(compress: true)
      compressing.write('key', 'small')
      expect(compressing.read('key')).to eq('small')
    end

    context 'with a bounded max_size' do
      let(:small) { described_class.new(max_size: 2) }

      before do
        small.write('a', 1)
        small.write('b', 2)
      end

      it 'evicts entries beyond max_size' do
        small.write('c', 3)
        expect(small.read('a')).to be_nil
      end

      it 'evicts the least recently used entry first' do
        small.read('a')
        small.write('c', 3)
        expect(small.read('a')).to eq(1)
      end
    end
  end

  describe '#read' do
    it 'returns the stored value' do
      store.write('key', 'value')
      expect(store.read('key')).to eq('value')
    end

    it 'returns nil for a missing key' do
      expect(store.read('missing')).to be_nil
    end

    it 'returns nil once expires_in has elapsed' do
      expiring = described_class.new(expires_in: 60)
      expiring.write('key', 'value')
      time_travel(Time.now + 61)
      expect(expiring.read('key')).to be_nil
    end

    it 'never expires entries when constructed without expires_in' do
      store.write('key', 'value')
      time_travel(Time.now + (10 * 365 * 24 * 3600))
      expect(store.read('key')).to eq('value')
    end
  end

  describe '#write' do
    it 'returns true' do
      expect(store.write('key', 'value')).to be(true)
    end

    it 'replaces an existing value' do
      store.write('key', 'old')
      store.write('key', 'new')
      expect(store.read('key')).to eq('new')
    end

    it 'tracks an approximate byte size' do
      store.write('key', 'value')
      expect(store.inspect).to match(/size=[1-9]\d*/)
    end

    context 'with unless_exist: true' do
      it 'returns false when the key is present' do
        store.write('key', 'old')
        expect(store.write('key', 'new', unless_exist: true)).to be(false)
      end

      it 'does not replace the existing value' do
        store.write('key', 'old')
        store.write('key', 'new', unless_exist: true)
        expect(store.read('key')).to eq('old')
      end

      it 'writes when the key is absent' do
        store.write('key', 'value', unless_exist: true)
        expect(store.read('key')).to eq('value')
      end
    end
  end

  describe '#fetch' do
    it 'stores and returns the block result on a miss' do
      expect(store.fetch('key') { 'computed' }).to eq('computed')
    end

    it 'returns the cached value without calling the block on a hit' do
      store.fetch('key') { 'first' }
      expect(store.fetch('key') { raise 'block should not run' }).to eq('first')
    end
  end

  describe '#exist?' do
    it 'returns true when the key is present' do
      store.write('key', 'value')
      expect(store.exist?('key')).to be(true)
    end

    it 'returns false when the key is absent' do
      expect(store.exist?('missing')).to be(false)
    end
  end

  describe '#delete' do
    it 'removes the entry and returns true' do
      store.write('key', 'value')
      expect(store.delete('key')).to be(true)
    end

    it 'returns false for a missing key' do
      expect(store.delete('missing')).to be(false)
    end

    it 'leaves the key unreadable' do
      store.write('key', 'value')
      store.delete('key')
      expect(store.read('key')).to be_nil
    end
  end

  describe '#clear' do
    it 'removes all entries' do
      store.write('a', 1)
      store.write('b', 2)
      store.clear
      expect(store.read('a')).to be_nil
    end

    it 'resets the tracked byte size' do
      store.write('a', 1)
      store.clear
      expect(store.inspect).to include('size=0')
    end
  end

  describe '#delete_matched' do
    before do
      store.write('prefix/a', 1)
      store.write('prefix/b', 2)
      store.write('other', 3)
    end

    it 'deletes keys matching the pattern' do
      store.delete_matched(/\Aprefix/)
      expect(store.read_multi('prefix/a', 'prefix/b')).to be_empty
    end

    it 'keeps keys that do not match' do
      store.delete_matched(/\Aprefix/)
      expect(store.read('other')).to eq(3)
    end

    it 'instruments the operation' do
      events = capture_events('cache_delete_matched.active_support') { store.delete_matched(/\Aprefix/) }
      expect(events.map(&:first)).to eq(['cache_delete_matched.active_support'])
    end
  end

  describe '#cleanup' do
    let(:expiring) { described_class.new(expires_in: 60) }
    let(:backing) { expiring.instance_variable_get(:@data) }

    it 'evicts lapsed entries without waiting for the next read' do
      expiring.write('key', 'value')
      time_travel(Time.now + 61)
      expect { expiring.cleanup }.to change(backing, :count).from(1).to(0)
    end

    it 'keeps live entries' do
      expiring.write('key', 'value')
      expiring.cleanup
      expect(expiring.read('key')).to eq('value')
    end

    it 'is a no-op without expires_in' do
      store.write('key', 'value')
      time_travel(Time.now + 61)
      store.cleanup
      expect(store.read('key')).to eq('value')
    end

    it 'instruments the operation with the entry count' do
      store.write('key', 'value')
      events = capture_events('cache_cleanup.active_support') { store.cleanup }
      expect(events.first.last).to include(size: 1)
    end
  end

  describe '#increment' do
    it 'sets a missing key to the amount' do
      expect(store.increment('counter')).to eq(1)
    end

    it 'adds to an existing value' do
      store.write('counter', 5)
      expect(store.increment('counter', 3)).to eq(8)
    end

    it 'stores the updated value' do
      store.increment('counter', 2)
      store.increment('counter', 2)
      expect(store.read('counter')).to eq(4)
    end

    it 'resets an entry with lapsed per-call expiry to the amount' do
      store.write('counter', 5, expires_in: 60)
      time_travel(Time.now + 120)
      expect(store.increment('counter')).to eq(1)
    end

    it 'resets a version-mismatched entry to the amount' do
      store.write('counter', 5, version: 'v1')
      expect(store.increment('counter', 1, version: 'v2')).to eq(1)
    end

    it 'instruments the operation with the amount' do
      events = capture_events('cache_increment.active_support') { store.increment('counter', 7) }
      expect(events.first.last).to include(amount: 7)
    end
  end

  describe '#decrement' do
    it 'sets a missing key to the negated amount' do
      expect(store.decrement('counter')).to eq(-1)
    end

    it 'subtracts from an existing value' do
      store.write('counter', 5)
      expect(store.decrement('counter', 2)).to eq(3)
    end

    it 'instruments the operation with the amount' do
      events = capture_events('cache_decrement.active_support') { store.decrement('counter', 4) }
      expect(events.first.last).to include(amount: 4)
    end
  end

  describe '#synchronize' do
    it 'returns the block result' do
      expect(store.synchronize { :result }).to be(:result)
    end

    it 'is reentrant' do
      expect(store.synchronize { store.synchronize { :nested } }).to be(:nested)
    end
  end

  describe '#inspect' do
    it 'reports the entry count' do
      store.write('key', 'value')
      expect(store.inspect).to include('entries=1')
    end
  end

  describe '#exists?' do
    it 'returns true for a present raw key' do
      store.write('key', 'value')
      expect(store.send(:exists?, 'key')).to be(true)
    end

    it 'returns false for an absent raw key' do
      expect(store.send(:exists?, 'missing')).to be(false)
    end
  end

  describe 'instrumentation parity' do
    def run_operations(cache)
      cache.fetch('k') { 'v' }
      cache.fetch('k') { 'v' }
      cache.write('w', 1)
      cache.read('w')
      cache.exist?('w')
      cache.increment('n')
      cache.decrement('n')
      cache.delete('w')
      cache.delete_matched(/x/)
      cache.cleanup
    end

    it 'emits the same event stream as ActiveSupport::Cache::MemoryStore' do
      expected = capture_events { run_operations(ActiveSupport::Cache::MemoryStore.new(coder: nil)) }
      actual = capture_events { run_operations(store) }
      expect(actual.map(&:first)).to eq(expected.map(&:first))
    end
  end
end
