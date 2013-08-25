require "unit_spec_helper"
require File.dirname(__FILE__) + '/../delivery_handler_shared.rb'

describe Rapns::Daemon::Gcm::DeliveryHandler do
  it_should_behave_like 'an DeliveryHandler subclass'

  let(:notification) { double }
  let(:batch) { double(:notification_processed => nil) }
  let(:queue) { Queue.new }
  let(:app) { double }
  let(:delivery_handler) { Rapns::Daemon::Gcm::DeliveryHandler.new(app) }
  let(:http) { double(:shutdown => nil)}

  before do
    Net::HTTP::Persistent.stub(:new => http)
    Rapns::Daemon::Gcm::Delivery.stub(:perform)
    delivery_handler.queue = queue
    queue.push([notification, batch])
  end

  it 'performs delivery of an notification' do
    Rapns::Daemon::Gcm::Delivery.should_receive(:perform).with(app, http, notification, batch)
    delivery_handler.start
    delivery_handler.stop
  end

  it 'initiates a persistent connection object' do
    Net::HTTP::Persistent.should_receive(:new).with('rapns')
    Rapns::Daemon::Gcm::DeliveryHandler.new(app)
  end

  it 'shuts down the http connection stopped' do
    http.should_receive(:shutdown)
    delivery_handler.start
    delivery_handler.stop
        delivery_handler.wakeup
    delivery_handler.wait
  end
end
