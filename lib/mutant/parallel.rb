# frozen_string_literal: true

module Mutant
  # Parallel execution engine of arbitrary payloads
  module Parallel

    # Driver for parallelized execution
    class Driver
      include Adamantium::Flat, Anima.new(
        :threads,
        :var_active_jobs,
        :var_final,
        :var_sink
      )

      private(*anima.attribute_names)

      # Wait for computaion to finish, with timeout
      #
      # @param [Float] timeout
      #
      # @return [Sink#status]
      #   current status
      def wait_timeout(timeout)
        var_final.take_timeout(timeout)

        finalize(status)
      end

    private

      # Possibly finalize the exeuction
      #
      # @param [Status]
      #
      # @return [Status]
      def finalize(status)
        status.tap do
          threads.each(&:join) if status.done?
        end
      end

      # Get status
      #
      # @return [Status]
      def status
        var_active_jobs.with do |active_jobs|
          var_sink.with do |sink|
            Status.new(
              active_jobs: active_jobs.dup,
              done:        threads.all? { |thread| !thread.alive? },
              payload:     sink.status
            )
          end
        end
      end
    end # Driver

    # Run async computation returning driver
    #
    # @param [Config] config
    #
    # @return [Driver]
    def self.async(config)
      var_active_jobs = Variable::IVar.new(Set.new)
      var_final       = Variable::IVar.new
      var_sink        = Variable::IVar.new(config.sink)
      var_source      = Variable::IVar.new(config.source)
      var_running     = Variable::MVar.new(config.jobs)

      threads = Array.new(config.jobs) do |index|
        Worker.run(
          index:           index,
          processor:       config.processor,
          var_active_jobs: var_active_jobs,
          var_final:       var_final,
          var_running:     var_running,
          var_sink:        var_sink,
          var_source:      var_source,
        )
      end

      Driver.new(
        threads:         threads,
        var_active_jobs: var_active_jobs,
        var_sink:        var_sink,
        var_final:       var_final
      )
    end

    class Worker
      include Adamantium::Flat, Anima.new(
        :index,
        :processor,
        :var_active_jobs,
        :var_final,
        :var_running,
        :var_sink,
        :var_source
      )

      private(*anima.attribute_names)

      # Start new worker
      #
      # @param [Hash{Symbol => Object}] attributes
      #
      # @return [Thread]
      def self.run(**attributes)
        Thread.new do
          new(**attributes).call
        end
      end

      # Run worker payload
      #
      # @return [undefined]
      def call
        loop do
          job = next_job or break

          job_start(job)

          result = processor.call(job.payload)

          job_done(job)

          var_sink.with { |sink| sink.result(result) }
        end

        finalize
      end

      # Next job, if any
      #
      # @return [Job, nil]
      def next_job
        var_source.with do |source|
          source.next if source.next?
        end
      end

      # Register job to be started
      #
      # @param [Job] job
      def job_start(job)
        var_active_jobs.with do |active_jobs|
          active_jobs << job
        end
      end

      # Register job to be done
      #
      # @param [Job] job
      def job_done(job)
        var_active_jobs.with do |active_jobs|
          active_jobs.delete(job)
        end
      end

      # Finalize worker
      #
      # @return [undefined]
      def finalize
        var_final.put(nil) if var_running.modify(&:pred).zero?
      end
    end # Worker

    # Job result sink
    class Sink
      include AbstractType

      # Process job result
      #
      # @param [Object]
      #
      # @return [self]
      abstract_method :result

      # The sink status
      #
      # @return [Object]
      abstract_method :status

      # Test if processing should stop
      #
      # @return [Boolean]
      abstract_method :stop?
    end # Sink

    # Parallel run configuration
    class Config
      include Adamantium::Flat, Anima.new(
        :jobs,
        :processor,
        :sink,
        :source
      )
    end # Config

    # Parallel execution status
    class Status
      include Adamantium::Flat, Anima.new(
        :active_jobs,
        :done,
        :payload
      )

      alias_method :done?, :done
    end # Status

  end # Parallel
end # Mutant
