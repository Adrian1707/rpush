module Rapns
  module Daemon
    module Apns
      class DeliveryHandler < Rapns::Daemon::DeliveryHandler
        HOSTS = {
          :production  => ['gateway.push.apple.com', 2195],
          :development => ['gateway.sandbox.push.apple.com', 2195], # deprecated
          :sandbox     => ['gateway.sandbox.push.apple.com', 2195]
        }

        def initialize(app)
          @app = app
          @host, @port = HOSTS[@app.environment.to_sym]
        end

        def deliver(notification)
          Rapns::Daemon::Apns::Delivery.perform(@app, connection, notification)
        end

        def stopped
          connection.close if @connection
        end

        protected

        def connection
          return @connection if defined? @connection
          @connection = Connection.new(@app, @host, @port)
          @connection.connect
          @connection
        end
      end
    end
  end
end
