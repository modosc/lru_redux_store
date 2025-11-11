# frozen_string_literal: true

require 'spec_helper'

RSpec.describe LruReduxStore::Store do
  subject { described_class.new }

  it 'inherits from ActiveSupport::Cache::Store' do
    expect(subject).to be_a(ActiveSupport::Cache::Store)
  end
end
