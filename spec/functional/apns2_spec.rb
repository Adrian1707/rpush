require 'functional_spec_helper'
require 'byebug'

describe 'APNs http2 adapter' do
  let(:fake_client) { double(call: fake_http_response) }
  let(:app) { create_app }
  let(:fake_device_token) { 'a' * 64 }
  let(:fake_http_resp_headers) {
    {
      ":status" => "200",
      "apns-id"=>"C6D65840-5E3F-785A-4D91-B97D305C12F6"
    }
  }
  let(:fake_http_resp_body) { '' }
  let(:fake_http_response) {
    double(headers: fake_http_resp_headers, body: fake_http_resp_body)
  }

  before do
    Rpush.config.push_poll = 0.5
    allow(NetHttp2::Client).
      to receive(:new).and_return(fake_client)
  end

  def create_app
    app = Rpush::Apns2::App.new
    app.certificate = TEST_CERT
    app.name = 'test'
    app.environment = 'development'
    app.save!
    app
  end

  def create_notification
    notification = Rpush::Apns2::Notification.new
    notification.app = app
    notification.alert = 'test'
    notification.device_token = fake_device_token
    notification.save!
    notification
  end

  it 'delivers a notification successfully' do
    notification = create_notification

    expect(fake_client)
      .to receive(:call)
      .with(
        :post,
        "/3/device/#{fake_device_token}",
        { body: "{\"aps\":{\"alert\":\"test\",\"sound\":\"default\"}}",
          headers: {} }
      )
      .and_return(fake_http_response)
    expect do
      Rpush.push
      notification.reload
    end.to change(notification, :delivered).to(true)
  end

  describe 'delivery failures' do
    context 'when response is about incorrect request' do
      let(:fake_http_resp_headers) {
        {
          ":status" => "404",
          "apns-id"=>"C6D65840-5E3F-785A-4D91-B97D305C12F6"
        }
      }

      it 'fails to deliver a notification' do
        notification = create_notification
        expect do
          Rpush.push
          notification.reload
        end.to change(notification, :failed).to(true)
      end

      it 'reflects :notification_id_failed' do
        reflector = double
        expect(reflector).to receive(:accept)

        Rpush.reflect do |on|
          on.notification_id_failed do |app, id, code, descr|
            expect(app).to be_kind_of(Rpush::Client::ActiveRecord::Apns2::App)
            expect(id).to eq 1
            expect(code).to eq 404
            expect(descr).to be_nil
           reflector.accept
          end
        end

        notification = create_notification
        Rpush.push
      end
    end

    context 'when response returns 500 error for APNs maintenance' do
      let(:fake_http_resp_headers) {
        {
          ":status" => "500",
          "apns-id"=>"C6D65840-5E3F-785A-4D91-B97D305C12F6"
        }
      }

      it 'fails but retries delivery several times' do
        notification = create_notification
        expect do
          Rpush.push
          notification.reload
        end.to change(notification, :retries).to eq(1)
      end
    end

    context 'shit' do
      let(:fake_http_resp_headers) {
        {
          ":status" => "500",
          "apns-id"=>"C6D65840-5E3F-785A-4D91-B97D305C12F6"
        }
      }

      it 'reflects :notification_id_will_retry' do
        Rpush.reflect do |on|
          on.notification_id_will_retry do |app, id, timer|
            expect(app).to be_kind_of(Rpush::Client::ActiveRecord::Apns2::App)
            expect(id).to eq 1
          end
        end

        notification = create_notification
        Rpush.push
      end
    end

    context 'when there is SocketError' do
      let(:fake_client) { double }

      before(:each) do
        expect(fake_client).to receive(:call) { raise(SocketError) }
      end

      it 'fails but retries delivery several times' do
        notification = create_notification
        expect do
          Rpush.push
          notification.reload
        end.to change(notification, :retries).to eq(1)
      end

      it 'reflects :notification_id_will_retry' do
        Rpush.reflect do |on|
          on.notification_id_will_retry do |app, id, timer|
            expect(app).to be_kind_of(Rpush::Client::ActiveRecord::Apns2::App)
            expect(id).to eq 1
            expect(timer).to be_kind_of(Time)
          end
        end

        notification = create_notification
        Rpush.push
      end
    end

    context 'when any StandardError occurs' do
      let(:fake_client) { double }

      before(:each) do
        expect(fake_client).to receive(:call) { raise(StandardError) }
      end

      it 'marks notification failed' do
        notification = create_notification
        expect do
          Rpush.push
          notification.reload
        end.to change(notification, :failed).to(true)
      end

      it 'reflects :error' do
        Rpush.reflect do |on|
          on.error do |error|
            expect(error).to be_kind_of(StandardError)
           reflector.accept
          end
        end

        notification = create_notification
        Rpush.push
      end
    end
  end
end
