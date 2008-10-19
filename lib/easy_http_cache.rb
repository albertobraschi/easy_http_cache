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

          http_cache_filter = HttpCacheFilter.new(
            :control => options.delete(:control),
            :expires_in => options.delete(:expires_in),
            :expires_at => options.delete(:expires_at),
            :last_change_at => options.delete(:last_change_at),
            :method => options.delete(:method),
            :etag => options.delete(:etag)
          )
          filter_options = {:only => actions}.merge(options)

          before_filter(http_cache_filter, filter_options)
        end
      end

      class HttpCacheFilter #:nodoc:
        def initialize(options = {})
          @options = options
          @digested_etag = nil
          @max_last_change_at = nil
        end

        def filter(controller)
          return unless controller.request.get?

          # We perform Last-Modified HTTP Cache when the option :last_change_at is sent
          # or when another cache mechanism is not set.
          #
          if @options[:last_change_at]
            @max_last_change_at = get_first_or_last_from_time_array(:last, @options[:last_change_at], controller)
          elsif !(@options[:etag] || @options[:expires_in] || @options[:expires_at])
            @max_last_change_at = Time.utc(0)
          end
          perform_time_cache = controller.request.env['HTTP_IF_MODIFIED_SINCE'] && @max_last_change_at && @max_last_change_at <= Time.rfc2822(controller.request.env['HTTP_IF_MODIFIED_SINCE']).utc

          # If the option :etag is sent we perform etag cache
          #
          if @options[:etag]
            @digested_etag = %("#{Digest::MD5.hexdigest(evaluate_method(@options[:etag], controller).to_s)}")
          end
          perform_etag_cache = controller.request.env['HTTP_IF_NONE_MATCH'] && @digested_etag && @digested_etag == controller.request.headers['HTTP_IF_NONE_MATCH']

          set_headers!(controller)

          if !component_request?(controller) && (perform_time_cache || perform_etag_cache)
            controller.__send__(:head, :not_modified)
            return false
          end
        end

        protected
        # Get first or last element from an array with Time objects.
        # The array is sorted (from earlier to later) and then the first or last element is returned.
        #
        # If :first is sent in first_or_last, all the timestamps before the current timestamps are discarded.
        #
        def get_first_or_last_from_time_array(first_or_last, array, controller)
          evaluated_array = [array].flatten.collect{ |item| evaluate_time(item, controller) }.compact
          evaluated_array = evaluated_array.select{ |time| time > Time.now.utc } if first_or_last == :first

          return evaluated_array.sort.__send__(first_or_last)
        end

        def evaluate_method(method, controller)
          case method
            when Symbol
              controller.__send__(method)
            when String
              eval(method, controller.instance_eval { binding })
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

        # Get :expires_in and :expires_at and put them together in one array
        #
        def get_expires_array
          expires_in = [@options[:expires_in]].flatten.compact.collect{ |interval| Time.now.utc + interval.to_i }
          expires_at = [@options[:expires_at]]
          return (expires_in + expires_at)
        end

        # Set HTTP cache headers
        #
        def set_headers!(controller)
          expires, control = nil, nil

          controller.response.headers['Last-Modified'] = @max_last_change_at.httpdate if @max_last_change_at
          controller.response.headers['ETag'] = @digested_etag if @digested_etag
          controller.response.headers['Expires'] = expires.httpdate if expires = get_first_or_last_from_time_array(:first, get_expires_array, controller)
          controller.response.headers['Cache-Control'] = control if control = get_control_by_cache(controller)
        end

        # Returns the Cache-Control based on the cache being used
        #
        def get_control_by_cache(controller)
          headers = controller.response.headers

          if headers['ETag'] || headers['Last-Modified']
            @options[:control] || 'private, max-age=0, must-revalidate'
          elsif headers['Expires']
            @options[:control] || 'public'
          else
            @options[:control]
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