# frozen_string_literal: true

require 'zeitwerk'
loader = Zeitwerk::Loader.for_gem
loader.ignore("#{__dir__}/active_support")
loader.setup

require 'active_support/cache'

module LruReduxStore
end

loader.eager_load
