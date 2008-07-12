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
            :etag => options.delete(:etag),
            :namespace => options.delete(:namespace)
          )
          filter_options = {:only => actions}.merge(options)

          around_filter(http_cache_filter, filter_options)
        end
      end

      class HttpCacheFilter #:nodoc:
        def initialize(options = {})
          @options = options
          @digested_etag = nil
          @max_last_change_at = nil
        end

        def before(controller)
          # We perform :last_change_at when it is set or when another cache
          # mechanism, i.e. :etag or :expires_in or :expires_at is set also.
          #
          # We also must have HTTP_IF_MODIFIED_SINCE in the header and a valid
          # max_last_change_at
          #
          if @options[:last_change_at] || !(@options[:etag] || @options[:expires_in] || @options[:expires_at])
            @max_last_change_at = get_from_time_array(:last, @options[:last_change_at], controller, true)
            perform_time_cache = @max_last_change_at && controller.request.env['HTTP_IF_MODIFIED_SINCE']
          end

          # If we have :etag and HTTP_IF_NONE_MATCH in the header we perform etag cache
          #
          if @options[:etag]
            @digested_etag = %("#{Digest::MD5.hexdigest(evaluate_method(@options[:etag], controller).to_s)}")
            perform_etag_cache = controller.request.env['HTTP_IF_NONE_MATCH']
          end

          if (!component_request?(controller) && perform_time_cache && @max_last_change_at <= Time.rfc2822(controller.request.env['HTTP_IF_MODIFIED_SINCE']).utc) || (perform_etag_cache && @digested_etag == controller.request.headers['HTTP_IF_NONE_MATCH'])
            controller.send!(:render, :text => '304 Not Modified', :status => 304)
            return false
          end
        end

        def after(controller)
          return unless controller.response.headers['Status'].to_i == 200
          expires, control = nil, nil

          controller.response.headers['Last-Modified'] = Time.now.httpdate if @max_last_change_at
          controller.response.headers['ETag'] = @digested_etag if @digested_etag
          controller.response.headers['Expires'] = expires.httpdate if expires = get_from_time_array(:first, expires_array(@options), controller)
          controller.response.headers['Cache-Control'] = control if control = control_with_namespace(@options, controller)
        end

        protected
        # Get first or last time an array with Time objects
        #
        def get_from_time_array(first_or_last, array, controller, append_zero = false)
          evaluated_array = [array].flatten.compact.collect{ |item| evaluate_method(item, controller) }
          evaluated_array << Time.utc(0) if append_zero
          return extract_time(first_or_last, evaluated_array)
        end

        def evaluate_method(method, *args)
          case method
            when Symbol
              object = args.shift
              object.send(method, *args)
            when String
              eval(method, args.first.instance_eval { binding })
            when Proc, Method
              method.call(*args)
            else
              method
            end
        end

        # Extract times from an array and get the first or last.
        # It will search for :to_time or :updated_at or :updated_on methods.
        #
        # Converts all times to UTC.
        #
        # If we want the :first element from array, we set to nil all times
        # before the current time.
        #
        def extract_time(first_or_last, array = [])
          array.collect do |item|
            item = if item.respond_to?(:to_time)
              item.to_time.utc
            elsif item.respond_to?(:updated_at)
              item.updated_at.utc
            elsif item.respond_to?(:updated_on)
              item.updated_on.utc
            else
              nil
            end

            (first_or_last == :first && item && item < Time.now.utc) ? nil : item
          end.compact.sort.send(first_or_last)
        end

        # Get :expires_in and :expires_at and put them together in one array
        #
        def expires_array(options)
          expires_in = [@options[:expires_in]].flatten.compact.collect{ |interval| Time.now.utc + interval.to_i }
          expires_at = [@options[:expires_at]]
          return (expires_in + expires_at)
        end

        # Parses the control option
        #
        def control_with_namespace(options, controller)
          control = if options[:namespace]
            "private=(#{evaluate_method(options[:namespace], controller).to_s.gsub(/\s+/,' ').gsub(/[^a-zA-Z0-9_\-\.\s]/,'')})"
          elsif options[:control]
            options[:control].to_s
          else
            nil
          end

          headers = controller.response.headers
          return (if headers['ETag'] || headers['Last-Modified']
            "#{control || 'private'}, max-age=0, must-revalidate"
          elsif headers['Expires']
            control || 'public'
          else
            control
          end)
        end

        # We should not render http cache when we are using components
        #
        def component_request?(controller)
          controller.instance_variable_get('@parent_controller')
        end
      end

    end
  end
end

ActionController::Base.send :include, ActionController::Caching::HttpCache