require 'unit_spec_helper'
require File.dirname(__FILE__) + '/../delivery_handler_shared.rb'

describe Rapns::Daemon::Apns::DeliveryHandler do
  it_should_behave_like 'an DeliveryHandler subclass'

  let(:host) { 'localhost' }
  let(:port) { 2195 }
  let(:certificate) { stub }
  let(:password) { stub }
  let(:app) { stub(:password => password, :certificate => certificate, :name => 'MyApp')}
  let(:delivery_handler) { Rapns::Daemon::Apns::DeliveryHandler.new(app, host, port) }
  let(:connection) { stub('Connection', :select => false, :write => nil, :reconnect => nil, :close => nil, :connect => nil) }
  let(:notification) { stub }
  let(:http) { stub(:shutdown => nil)}
  let(:queue) { Rapns::Daemon::DeliveryQueue.new }

  before do
    Rapns::Daemon::Apns::Connection.stub(:new => connection)
    Rapns::Daemon::Apns::Delivery.stub(:perform)
    delivery_handler.queue = queue
    queue.push(notification)
  end

  it "instantiates a new connection" do
    Rapns::Daemon::Apns::Connection.should_receive(:new).with(app, host, port)
    Rapns::Daemon::Apns::DeliveryHandler.new(app, host, port)
  end

  it 'performs delivery of an notification' do
    Rapns::Daemon::Apns::Delivery.should_receive(:perform).with(app, connection, notification)
    delivery_handler.start
    delivery_handler.stop
  end

  it "connects the socket when instantiated" do
    connection.should_receive(:connect)
    Rapns::Daemon::Apns::DeliveryHandler.new(app, host, port)
    delivery_handler.start
    delivery_handler.stop
  end

  it 'closes the connection stopped' do
    connection.should_receive(:close)
    delivery_handler.start
    delivery_handler.stop
  end
end
