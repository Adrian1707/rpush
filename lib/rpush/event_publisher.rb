module Rpush
  module EventPublisher
    def self.publish(event_name, data)
      ActiveSupport::Notifications.instrument(event_name, data)
    end
  end
end
