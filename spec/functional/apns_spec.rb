require 'functional_spec_helper'

describe 'APNs' do
  let(:app) { create_app }
  let(:tcp_socket) { double(TCPSocket, setsockopt: nil, close: nil) }
  let(:ssl_socket) { double(OpenSSL::SSL::SSLSocket, :sync= => nil, connect: nil, write: nil, flush: nil, read: nil, close: nil) }
  let(:io_double) { double(select: nil) }
  let(:delivered_ids) { [] }
  let(:failed_ids) { [] }
  let(:retry_ids) { [] }

  before do
    Rpush.config.push_poll = 0.5
    stub_tcp_connection
  end

  def create_app
    app = Rpush::Apns::App.new
    app.certificate = TEST_CERT
    app.name = 'test'
    app.environment = 'sandbox'
    app.save!
    app
  end

  def create_notification
    notification = Rpush::Apns::Notification.new
    notification.app = app
    notification.alert = 'test'
    notification.device_token = 'a' * 64
    notification.save!
    notification
  end

  def stub_tcp_connection
    Rpush::Daemon::TcpConnection.any_instance.stub(connect_socket: [tcp_socket, ssl_socket])
    Rpush::Daemon::TcpConnection.any_instance.stub(setup_ssl_context: double.as_null_object)
    stub_const('Rpush::Daemon::TcpConnection::IO', io_double)
  end

  def wait
    sleep 0.1
  end

  def wait_for_notification_to_deliver(notification)
    timeout { wait until delivered_ids.include?(notification.id) }
  end

  def wait_for_notification_to_fail(notification)
    timeout { wait until failed_ids.include?(notification.id) }
  end

  def wait_for_notification_to_retry(notification)
    timeout { wait until retry_ids.include?(notification.id) }
  end

  def fail_notification(notification)
    ssl_socket.stub(read: [8, 4, notification.id].pack('ccN'))
    enable_io_select
  end

  def enable_io_select
    called = false
    io_double.stub(:select) do
      if called
        nil
      else
        called = true
      end
    end
  end

  def timeout(&blk)
    Timeout.timeout(10, &blk)
  end

  it 'delivers a notification successfully' do
    notification = create_notification
    expect do
      Rpush.push
      notification.reload
    end.to change(notification, :delivered).to(true)
  end

  it 'receives feedback' do
    app
    tuple = "N\xE3\x84\r\x00 \x83OxfU\xEB\x9F\x84aJ\x05\xAD}\x00\xAF1\xE5\xCF\xE9:\xC3\xEA\a\x8F\x1D\xA4M*N\xB0\xCE\x17"
    allow(ssl_socket).to receive(:read).and_return(tuple, nil)
    Rpush.apns_feedback
    feedback = Rpush::Apns::Feedback.all.first
    feedback.should_not be_nil
    feedback.app_id.should eq(app.id)
    feedback.device_token.should eq('834f786655eb9f84614a05ad7d00af31e5cfe93ac3ea078f1da44d2a4eb0ce17')
  end

  describe 'delivery failures' do
    before do
      Rpush.reflect do |on|
        on.notification_delivered do |n|
          delivered_ids << n.id
        end

        on.notification_id_failed do |_, n_id|
          failed_ids << n_id
        end

        on.notification_id_will_retry do |_, n_id|
          retry_ids << n_id
        end
      end

      Rpush.embed
    end

    after do
      Rpush.reflection_stack.clear
      Rpush.reflection_stack.push(Rpush::ReflectionCollection.new)

      timeout { Rpush.shutdown }
    end

    it 'fails to deliver a notification' do
      notification = create_notification
      wait_for_notification_to_deliver(notification)
      fail_notification(notification)
      wait_for_notification_to_fail(notification)
    end

    describe 'with multiple notifications' do
      let(:notification1) { create_notification }
      let(:notification2) { create_notification }
      let(:notification3) { create_notification }
      let(:notification4) { create_notification }
      let(:notifications) { [notification1, notification2, notification3, notification4] }

      it 'marks the correct notification as failed' do
        notifications.each { |n| wait_for_notification_to_deliver(n) }
        fail_notification(notification2)
        wait_for_notification_to_fail(notification2)
      end

      it 'does not mark prior notifications as failed' do
        notifications.each { |n| wait_for_notification_to_deliver(n) }
        fail_notification(notification2)
        wait_for_notification_to_fail(notification2)

        expect(failed_ids).to_not include(notification1.id)
        notification1.reload
        notification1.delivered.should be_true
      end

      it 'marks notifications following the failed one as retryable' do
        notifications.each { |n| wait_for_notification_to_deliver(n) }
        fail_notification(notification2)
        [notification3, notification4].each { |n| wait_for_notification_to_retry(n) }
      end

      describe 'without an error response' do
        it 'marks all notifications as failed' do
          notifications.each { |n| wait_for_notification_to_deliver(n) }
          ssl_socket.stub(read: nil)
          enable_io_select
          notifications.each { |n| wait_for_notification_to_fail(n) }
        end
      end
    end
  end
end
