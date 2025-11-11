# frozen_string_literal: true

require 'spec_helper'

RSpec.describe LruReduxStore do
  it 'has a version number' do
    expect(described_class::VERSION).not_to be_nil
  end
end
