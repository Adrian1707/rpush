require "unit_spec_helper"

describe Rapns::Daemon::DeliveryQueue do
  let(:queue) { Rapns::Daemon::DeliveryQueue.new }

  it 'behaves likes a normal qeue' do
    obj = double
    queue.push obj
    queue.pop.should == obj
  end

  it 'returns false if notifications have not all been processed' do
    queue.push double
    queue.notifications_processed?.should be_false
  end

  it 'returns false if the queue is empty but notifications have not all been processed' do
    queue.push double
    queue.pop
    queue.notifications_processed?.should be_false
  end

  it 'returns true if all notifications have been processed' do
    queue.push double
    queue.pop
    queue.notification_processed
    queue.notifications_processed?.should be_true
  end
end
