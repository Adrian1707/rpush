module Rapns
  module Daemon
    module Gcm
      # http://developer.android.com/guide/google/gcm/gcm.html#response
      class Delivery < Rapns::Daemon::Delivery
        include Rapns::MultiJsonHelper

        GCM_URI = URI.parse('https://android.googleapis.com/gcm/send')
        UNAVAILABLE_STATES = ['Unavailable', 'InternalServerError']
        INVALID_REGISTRATION_ID_STATES = ['InvalidRegistration', 'MismatchSenderId', 'NotRegistered', 'InvalidPackageName']

        def initialize(app, http, notification, batch)
          @app = app
          @http = http
          @notification = notification
          @batch = batch
        end

        def perform
          begin
            handle_response(do_post)
          rescue Rapns::DeliveryError => error
            mark_failed(error.code, error.description)
            raise
          end
        end

        protected

        def handle_response(response)
          case response.code.to_i
          when 200
            ok(response)
          when 400
            bad_request
          when 401
            unauthorized
          when 500
            internal_server_error(response)
          when 503
            service_unavailable(response)
          else
            raise Rapns::DeliveryError.new(response.code, @notification.id, HTTP_STATUS_CODES[response.code.to_i])
          end
        end

        def ok(response)
          body = multi_json_load(response.body)

          results = Results.new(body['results'], @notification.registration_ids)
          results.process(invalid: INVALID_REGISTRATION_ID_STATES, unavailable: UNAVAILABLE_STATES)

          handle_successes(results.successes)

          if results.failures[:unavailable].count == @notification.registration_ids.count
            Rapns.logger.warn("All recipients unavailable. #{retry_message}")
            retry_delivery(@notification, response)
          elsif results.failures.any?
            handle_failures(results.failures, response)
            raise Rapns::DeliveryError.new(nil, @notification.id, results.failures.description)
          else
            mark_delivered
            Rapns.logger.info("[#{@app.name}] #{@notification.id} sent to #{@notification.registration_ids.join(', ')}")
          end
        end

        def handle_successes(successes)
          successes.each do |result|
            reflect(:gcm_delivered_to_recipient, @notification, result[:registration_id])
            if result.has_key?(:canonical_id)
              reflect(:gcm_canonical_id, result[:registration_id], result[:canonical_id])
            end
          end
        end

        def handle_failures(failures, response)
          failures.each do |result|
            reflect(:gcm_failed_to_recipient, @notification, result[:error], result[:registration_id])
          end

          failures[:invalid].each do |result|
            reflect(:gcm_invalid_registration_id, @app, result[:error], result[:registration_id])
          end

          if failures[:unavailable].any?
            unavailable_idxs = failures[:unavailable].map { |result| result[:index] }
            new_notification = create_new_notification(response, unavailable_idxs)
            failures.description += " #{unavailable_idxs.join(', ')} will be retried as notification #{new_notification.id}."
          end
        end

        def create_new_notification(response, unavailable_idxs)
          attrs = @notification.attributes.slice('app_id', 'collapse_key', 'delay_while_idle')
          registration_ids = @notification.registration_ids.values_at(*unavailable_idxs)
          Rapns::Daemon.store.create_gcm_notification(attrs, @notification.data,
            registration_ids, deliver_after_header(response), @notification.app)
        end

        def bad_request
          raise Rapns::DeliveryError.new(400, @notification.id, 'GCM failed to parse the JSON request. Possibly an rapns bug, please open an issue.')
        end

        def unauthorized
          raise Rapns::DeliveryError.new(401, @notification.id, 'Unauthorized, check your App auth_key.')
        end

        def internal_server_error(response)
          retry_delivery(@notification, response)
          Rapns.logger.warn("GCM responded with an Internal Error. " + retry_message)
        end

        def service_unavailable(response)
          retry_delivery(@notification, response)
          Rapns.logger.warn("GCM responded with an Service Unavailable Error. " + retry_message)
        end

        def deliver_after_header(response)
          if response.header['retry-after']
            if response.header['retry-after'].to_s =~ /^[0-9]+$/
              Time.now + response.header['retry-after'].to_i
            else
              Time.httpdate(response.header['retry-after'])
            end
          end
        end

        def retry_delivery(notification, response)
          if time = deliver_after_header(response)
            mark_retryable(notification, time)
          else
            mark_retryable_exponential(notification)
          end
        end

        def retry_message
          "Notification #{@notification.id} will be retried after #{@notification.deliver_after.strftime("%Y-%m-%d %H:%M:%S")} (retry #{@notification.retries})."
        end

        def do_post
          post = Net::HTTP::Post.new(GCM_URI.path, initheader = {'Content-Type'  => 'application/json',
                                                                 'Authorization' => "key=#{@notification.app.auth_key}"})
          post.body = @notification.as_json.to_json
          @http.request(GCM_URI, post)
        end

        HTTP_STATUS_CODES = {
          100  => 'Continue',
          101  => 'Switching Protocols',
          102  => 'Processing',
          200  => 'OK',
          201  => 'Created',
          202  => 'Accepted',
          203  => 'Non-Authoritative Information',
          204  => 'No Content',
          205  => 'Reset Content',
          206  => 'Partial Content',
          207  => 'Multi-Status',
          226  => 'IM Used',
          300  => 'Multiple Choices',
          301  => 'Moved Permanently',
          302  => 'Found',
          303  => 'See Other',
          304  => 'Not Modified',
          305  => 'Use Proxy',
          306  => 'Reserved',
          307  => 'Temporary Redirect',
          400  => 'Bad Request',
          401  => 'Unauthorized',
          402  => 'Payment Required',
          403  => 'Forbidden',
          404  => 'Not Found',
          405  => 'Method Not Allowed',
          406  => 'Not Acceptable',
          407  => 'Proxy Authentication Required',
          408  => 'Request Timeout',
          409  => 'Conflict',
          410  => 'Gone',
          411  => 'Length Required',
          412  => 'Precondition Failed',
          413  => 'Request Entity Too Large',
          414  => 'Request-URI Too Long',
          415  => 'Unsupported Media Type',
          416  => 'Requested Range Not Satisfiable',
          417  => 'Expectation Failed',
          418  => "I'm a Teapot",
          422  => 'Unprocessable Entity',
          423  => 'Locked',
          424  => 'Failed Dependency',
          426  => 'Upgrade Required',
          500  => 'Internal Server Error',
          501  => 'Not Implemented',
          502  => 'Bad Gateway',
          503  => 'Service Unavailable',
          504  => 'Gateway Timeout',
          505  => 'HTTP Version Not Supported',
          506  => 'Variant Also Negotiates',
          507  => 'Insufficient Storage',
          510  => 'Not Extended',
        }
      end

      class Results
        attr_reader :successes, :failures

        def initialize(results_data, registration_ids)
          @results_data = results_data
          @registration_ids = registration_ids
        end

        def process(failure_partitions = {})
          @successes = []
          @failures = Failures.new
          failure_partitions.each_key do |category|
            failures[category] = []
          end

          @results_data.zip(@registration_ids).each_with_index do |(result, registration_id), index|
            entry = {
              registration_id: registration_id,
              index: index
            }
            if result['message_id']
              entry[:canonical_id] = result['registration_id'] if result['registration_id'].present?
              successes << entry
            elsif result['error']
              entry[:error] = result['error']
              failures << entry
              failure_partitions.each do |category, error_states|
                failures[category] << entry if error_states.include?(result['error'])
              end
            end
          end
          failures.total_fail = failures.count == @registration_ids.count
        end
      end

      class Failures < Hash
        include Enumerable
        attr_writer :total_fail, :description

        def initialize
          super[:all] = []
        end

        def each
          self[:all].each { |x| yield x }
        end

        def <<(item)
          self[:all] << item
        end

        def description
          @description ||= describe
        end

        private

        def describe
          if @total_fail
            error_description = "Failed to deliver to all recipients."
          else
            index_list = map { |item| item[:index] }
            error_description = "Failed to deliver to recipients #{index_list.join(', ')}."
          end

          error_list = map { |item| item[:error] }
          error_description + " Errors: #{error_list.join(', ')}."
        end
      end
    end
  end
end
