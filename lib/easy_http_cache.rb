module ActionController #:nodoc:
  module Caching
    module HttpCache
      def self.included(base) #:nodoc:
        base.extend(ClassMethods)
      end

      module ClassMethods
        # Declares that +actions+ should be cached.
        #
        def http_cache(*actions)
          return unless perform_caching
          options = actions.extract_options!

          options.assert_valid_keys(
            :last_modified, :method, :etag, :if, :unless
          )

          http_cache_filter = HttpCacheFilter.new(
            :method => options.delete(:method),
            :last_modified => [options.delete(:last_modified)].flatten.compact,
            :etag => options.delete(:etag)
          )
          filter_options = {:only => actions}.merge(options)

          before_filter(http_cache_filter, filter_options)
        end
      end

      class HttpCacheFilter #:nodoc:
        def initialize(options = {})
          @options = options
        end

        def filter(controller)
          # We don't go ahead if we are rendering a component
          #
          return if component_request?(controller)

          last_modified = get_last_modified(controller)
          controller.response.last_modified = last_modified if last_modified

          processed_etags = get_processed_etags(controller)
          controller.response.etag = processed_etags if processed_etags

          if controller.request.fresh?(controller.response)
            controller.__send__(:head, :not_modified)
            return false
          end
        end

        protected
          # If :etag is an array, it processes all Methods, Procs and Symbols
          # and return them as array. If it's an object, we only evaluate it.
          #
          # Finally, if :etag is not sent but RAILS_CACHE_ID or RAILS_APP_VERSION
          # are set, we return an empty string allowing etag to be performed
          # because those variables, when modified, are a valid way to expire
          # all previous caches.
          #
          def get_processed_etags(controller)
            if @options[:etag].is_a?(Array)
              @options[:etag].collect do |item|
                evaluate_method(item, controller)
              end
            elsif @options[:etag]
              evaluate_method(@options[:etag], controller)
            elsif ENV['RAILS_CACHE_ID'] || ENV['RAILS_APP_VERSION']
              ''
            else
              nil
            end
          end

          # We perform Last-Modified HTTP Cache when the option :last_modified is sent
          # or no other cache mechanism is set (then we set a very old timestamp).
          #
          def get_last_modified(controller)
            # Then, if @options[:last_modified] is not empty, we run through the array
            # processing all objects (if needed) and return the latest one to be used.
            #
            if !@options[:last_modified].empty?
              @options[:last_modified].collect do |item|
                evaluate_time(item, controller)
              end.compact.sort.last
            elsif @options[:etag].blank?
              Time.utc(0)
            else
              nil
            end
          end

          def evaluate_method(method, controller)
            case method
              when Symbol
                controller.__send__(method)
              when Proc, Method
                method.call(controller)
              else
                method
              end
          end

          # Evaluate the objects sent and return time objects
          #
          # It process Symbols, String, Proc and Methods, get its results and then
          # call :to_time, :updated_at, :updated_on on it.
          #
          # If the parameter :method is sent, it will try to call it on the object before
          # calling :to_time, :updated_at, :updated_on.
          #
          def evaluate_time(method, controller)
            return nil unless method
            time = evaluate_method(method, controller)

            time = time.__send__(@options[:method]) if @options[:method].is_a?(Symbol) && time.respond_to?(@options[:method])

            if time.respond_to?(:to_time)
              time.to_time.utc
            elsif time.respond_to?(:updated_at)
              time.updated_at.utc
            elsif time.respond_to?(:updated_on)
              time.updated_on.utc
            else
              nil
            end
          end

          # We should not do http cache when we are using components
          #
          def component_request?(controller)
            controller.instance_variable_get('@parent_controller')
          end
        end

    end
  end
end

ActionController::Base.__send__ :include, ActionController::Caching::HttpCache