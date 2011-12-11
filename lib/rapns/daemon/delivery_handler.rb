module Rapns
  module Daemon
    class DeliveryHandler
      STOP = 0x666
      SELECT_TIMEOUT = 0.5
      ERROR_TUPLE_BYTES = 6
      APN_ERRORS = {
        1 => "Processing error",
        2 => "Missing device token",
        3 => "Missing topic",
        4 => "Missing payload",
        5 => "Missing token size",
        6 => "Missing topic size",
        7 => "Missing payload size",
        8 => "Invalid token",
        255 => "None (unknown error)"
      }

      def initialize(i)
        @name = "DeliveryHandler #{i}"
        host = Rapns::Daemon.configuration.push.host
        port = Rapns::Daemon.configuration.push.port
        @connection = Connection.new(@name, host, port)
      end

      def start
        @connection.connect

        Thread.new do
          loop do
            break if @stop
            handle_next_notification
          end
        end
      end

      def stop
        @stop = true
        Rapns::Daemon.delivery_queue.push(STOP)
      end

      protected

      def deliver(notification)
        begin
          @connection.write(notification.to_binary)
          check_for_error

          notification.delivered = true
          notification.delivered_at = Time.now
          notification.save!(:validate => false)

          Rapns::Daemon.logger.info("Notification #{notification.id} delivered to #{notification.device_token}")
        rescue Rapns::DeliveryError => error
          handle_delivery_error(notification, error)
          raise
        end
      end

      def handle_delivery_error(notification, error)
        notification.delivered = false
        notification.delivered_at = nil
        notification.failed = true
        notification.failed_at = Time.now
        notification.error_code = error.code
        notification.error_description = error.description
        notification.save!(:validate => false)
      end

      def check_for_error
        if @connection.select(SELECT_TIMEOUT)
          error = nil

          if tuple = @connection.read(ERROR_TUPLE_BYTES)
            cmd, status, notification_id = tuple.unpack("ccN")

            description = APN_ERRORS[status] || "Unknown error. Possible rapns bug?"
            error = Rapns::DeliveryError.new(status, description, notification_id)
          else
            description = "The APNs disconnected without returning an error. This may indicate you are using an invalid certificate for the host."
            error = Rapns::DeliveryError.new(nil, description, nil)
          end

          begin
            Rapns::Daemon.logger.error("[#{@name}] Error received, reconnecting...")
            @connection.reconnect
          ensure
            raise error if error
          end
        end
      end

      def handle_next_notification
        notification = Rapns::Daemon.delivery_queue.pop

        if notification == STOP
          @connection.close
          return
        end

        begin
          deliver(notification)
        rescue StandardError => e
          Rapns::Daemon.logger.error(e)
        ensure
          Rapns::Daemon.delivery_queue.notification_processed
        end
      end
    end
  end
end