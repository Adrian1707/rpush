require "unit_spec_helper"

describe Rapns::Notification do
  it { should validate_numericality_of(:expiry) }
  it { should validate_presence_of(:app) }
end