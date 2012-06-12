require "spec_helper"

describe Rapns::Daemon::Feeder do
  let(:poll) { 2 }
  let(:notification) { Rapns::Notification.create!(:device_token => "a" * 64, :app => 'my_app') }
  let(:logger) { stub }
  let(:queue) { stub(:push => nil, :notifications_processed? => true) }

  before do
    Rapns::Daemon.stub(:queues => { 'my_app' => queue })
    Rapns::Daemon::Feeder.stub(:sleep)
    Rapns::Daemon::Feeder.stub(:interruptible_sleep)
    Rapns::Daemon.stub(:logger).and_return(logger)
    Rapns::Daemon::Feeder.instance_variable_set("@stop", false)
  end

  it "checks for new notifications with the ability to reconnect the database" do
    Rapns::Daemon::Feeder.should_receive(:with_database_reconnect_and_retry)
    Rapns::Daemon::Feeder.enqueue_notifications
  end

  it "enqueues an undelivered notification" do
    notification.update_attributes!(:delivered => false)
    queue.should_receive(:push).with(notification)
    Rapns::Daemon::Feeder.enqueue_notifications
  end

  it "enqueues an undelivered notification without deliver_after set" do
    notification.update_attributes!(:delivered => false, :deliver_after => nil)
    queue.should_receive(:push).with(notification)
    Rapns::Daemon::Feeder.enqueue_notifications
  end

  it "enqueues a notification with a deliver_after time in the past" do
    notification.update_attributes!(:delivered => false, :deliver_after => 1.hour.ago)
    queue.should_receive(:push).with(notification)
    Rapns::Daemon::Feeder.enqueue_notifications
  end

  it "does not enqueue a notification with a deliver_after time in the future" do
    notification.update_attributes!(:delivered => false, :deliver_after => 1.hour.from_now)
    queue.should_not_receive(:push)
    Rapns::Daemon::Feeder.enqueue_notifications
  end

  it "does not enqueue a previously delivered notification" do
    notification.update_attributes!(:delivered => true, :delivered_at => Time.now)
    queue.should_not_receive(:push)
    Rapns::Daemon::Feeder.enqueue_notifications
  end

  it "does not enqueue a notification that has previously failed delivery" do
    notification.update_attributes!(:delivered => false, :failed => true)
    queue.should_not_receive(:push)
    Rapns::Daemon::Feeder.enqueue_notifications
  end

  it "does not enqueue more notifications if others are still being processed" do
    queue.stub(:notifications_processed? => false)
    queue.should_not_receive(:push)
    Rapns::Daemon::Feeder.enqueue_notifications
  end

  it "logs errors" do
    e = StandardError.new("bork")
    Rapns::Notification.stub(:ready_for_delivery).and_raise(e)
    Rapns::Daemon.logger.should_receive(:error).with(e)
    Rapns::Daemon::Feeder.enqueue_notifications
  end

  it "interrupts sleep when stopped" do
    Rapns::Daemon::Feeder.should_receive(:interrupt_sleep)
    Rapns::Daemon::Feeder.stop
  end

  it "enqueues notifications when started" do
    Rapns::Daemon::Feeder.should_receive(:enqueue_notifications).at_least(:once)
    Rapns::Daemon::Feeder.stub(:loop).and_yield
    Rapns::Daemon::Feeder.start(poll)
  end

  it "sleeps for the given period" do
    Rapns::Daemon::Feeder.should_receive(:interruptible_sleep).with(poll)
    Rapns::Daemon::Feeder.stub(:loop).and_yield
    Rapns::Daemon::Feeder.start(poll)
  end

  it 'logs and error if the notifcation app is not configured' do
    notification.update_attributes!(:app => 'unknown')
    notification.stub(:id => 1)
    logger.should_receive(:error).with("No such app 'unknown' for notification 1.")
    Rapns::Daemon::Feeder.enqueue_notifications
  end
end