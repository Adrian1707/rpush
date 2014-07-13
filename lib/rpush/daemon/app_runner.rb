module Rpush
  module Daemon
    class AppRunner
      extend Reflectable
      include Reflectable
      include Loggable

      class << self
        attr_reader :runners
      end

      @runners = {}

      def self.enqueue(notifications)
        notifications.group_by(&:app_id).each do |app_id, group|
          sync_app_with_id(app_id) unless runners[app_id]
          runners[app_id].enqueue(group) if runners[app_id]
        end
        ProcTitle.update
      end

      def self.sync
        apps = Rpush::Daemon.store.all_apps
        apps.each { |app| sync_app(app) }
        removed = runners.keys - apps.map(&:id)
        removed.each { |app_id| runners.delete(app_id).stop }
        ProcTitle.update
      end

      def self.sync_app(app)
        if runners[app.id]
          runners[app.id].sync(app)
        else
          runner = new(app)
          begin
            runners[app.id] = runner
            runner.start
          rescue StandardError => e
            Rpush.logger.error("[#{app.name}] Exception raised during startup. Notifications will not be delivered for this app.")
            Rpush.logger.error(e)
            reflect(:error, e)
          end
        end
      end

      def self.sync_app_with_id(app_id)
        sync_app(Rpush::Daemon.store.app(app_id))
      end

      def self.stop
        runners.values.map(&:stop)
        runners.clear
      end

      def self.num_dispatchers
        runners.values.sum(&:num_dispatcher_loops)
      end

      def self.num_queued
        runners.values.sum(&:queue_size)
      end

      def self.debug
        runners.values.map(&:debug)
      end

      attr_reader :app

      def initialize(app)
        @app = app
        @loops = []
      end

      def start
        app.connections.times { dispatcher_loops.push(new_dispatcher_loop) }
        start_loops
        log_info("Started, #{dispatchers_str}.")
      end

      def stop
        wait_until_idle
        stop_dispatcher_loops
        stop_loops
      end

      def wait_until_idle
        sleep 0.5 while queue.size > 0
      end

      def enqueue(notifications)
        if service.batch_deliveries?
          batch_size = (notifications.size / num_dispatcher_loops).ceil
          notifications.in_groups_of(batch_size, false).each do |batch_notifications|
            batch = Batch.new(batch_notifications)
            queue.push(QueuePayload.new(batch))
          end
        else
          batch = Batch.new(notifications)
          notifications.each do |notification|
            queue.push(QueuePayload.new(batch, notification))
            reflect(:notification_enqueued, notification)
          end
        end
      end

      def sync(app)
        @app = app
        diff = dispatcher_loops.size - app.connections
        return if diff == 0
        if diff > 0
          decrement_dispatchers(diff)
          log_info("Stopped #{dispatchers_str(diff)}. #{dispatchers_str} running.")
        else
          increment_dispatchers(diff.abs)
          log_info("Started #{dispatchers_str(diff)}. #{dispatchers_str} running.")
        end
      end

      def decrement_dispatchers(num)
        num.times { dispatcher_loops.pop }
      end

      def increment_dispatchers(num)
        num.times { dispatcher_loops.push(new_dispatcher_loop) }
      end

      def debug
        dispatcher_details = {}

        dispatcher_loops.loops.each_with_index do |dispatcher_loop, i|
          dispatcher_details[i] = {
            started_at: dispatcher_loop.started_at.iso8601,
            dispatched: dispatcher_loop.dispatch_count,
            thread_status: dispatcher_loop.thread_status
          }
        end

        runner_details = { dispatchers: dispatcher_details, queued: queue_size }
        log_info(JSON.pretty_generate(runner_details))
      end

      def queue_size
        queue.size
      end

      def num_dispatcher_loops
        dispatcher_loops.size
      end

      private

      def start_loops
        @loops = service.loop_instances(@app)
        @loops.map(&:start)
      end

      def stop_loops
        @loops.map(&:stop)
        @loops = []
      end

      def stop_dispatcher_loops
        dispatcher_loops.stop
        @dispatcher_loops = nil
      end

      def new_dispatcher_loop
        dispatcher = service.new_dispatcher(@app)
        dispatcher_loop = Rpush::Daemon::DispatcherLoop.new(queue, dispatcher)
        dispatcher_loop.start
        dispatcher_loop
      end

      def service
        return @service if defined? @service
        @service = "Rpush::Daemon::#{@app.service_name.camelize}".constantize
      end

      def queue
        @queue ||= Queue.new
      end

      def dispatcher_loops
        @dispatcher_loops ||= Rpush::Daemon::DispatcherLoopCollection.new
      end

      def dispatchers_str(count = num_dispatcher_loops)
        count = count.abs
        str = count == 1 ? 'dispatcher' : 'dispatchers'
        "#{count} #{str}"
      end
    end
  end
end
