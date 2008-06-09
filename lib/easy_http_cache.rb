module ActionController #:nodoc:
  module Caching
    module HttpCache
      def self.included(base) #:nodoc:
        base.extend(ClassMethods)
      end

      module ClassMethods
        # Declares that +actions+ should be cached.
        # If none "complex Proc" (i.e. arity > 0) is detected in :last_change_at and, prepends the cache filter (this works as Rails caches_page).
        def http_cache(*actions)
          return unless perform_caching
          options = actions.extract_options!
          options_with_complex_proc = has_complex_proc?(options)

          http_cache_filter = HttpCacheFilter.new(:control => options.delete(:control), :expires_in => options.delete(:expires_in), :last_change_at => options.delete(:last_change_at), :etag => options.delete(:etag), :namespace => options.delete(:namespace))
          filter_options = {:only => actions}.merge(options)

          if options_with_complex_proc
            around_filter(http_cache_filter, filter_options)
          else
            prepend_around_filter(http_cache_filter, filter_options)
          end
        end

        private 
        # Returns true if the given collection of object has or is a Proc or a Method with arity > 0
        def has_complex_proc?(collection) #:nodoc:
          collection.each do |key, object|
            return true if !Array(object).select{|item| item.is_a?(Proc) || item.is_a?(Method) ? item.arity > 0 : false}.empty?
          end
          return false
        end
      end

      class HttpCacheFilter #:nodoc:
        def initialize(options = {})
          @options = options
          @digested_etag = nil
          @max_last_change_at = nil
        end

        def before(controller)
          return unless controller.request.get?

          # If we have :etag but not :last_change_at we don't perform time cache
          # We also must have HTTP_IF_MODIFIED_SINCE in the header and a valid max_last_change_at
          if @options[:last_change_at] || (!@options[:etag] && !@options[:expires_in])
            @max_last_change_at = get_time_array(:last, @options[:last_change_at], controller, true)
            perform_time_cache = @max_last_change_at && controller.request.env['HTTP_IF_MODIFIED_SINCE']
          end

          # If we have :etag and HTTP_IF_NONE_MATCH in the header we perform etag cache
          if @options[:etag]
            @digested_etag = %("#{Digest::MD5.hexdigest(evaluate_method(@options[:etag], controller).to_s)}")
            perform_etag_cache = controller.request.env['HTTP_IF_NONE_MATCH']
          end

          if (perform_time_cache && @max_last_change_at <= Time.rfc2822(controller.request.env['HTTP_IF_MODIFIED_SINCE']).utc) || (perform_etag_cache && @digested_etag == controller.request.headers['HTTP_IF_NONE_MATCH'])
            controller.send!(:render, :text => '304 Not Modified', :status => 304)
            return false
          end
        end

        def after(controller)
          return unless controller.request.get? && controller.response.headers['Status'].to_i == 200
          expires, control = nil, nil

          controller.response.headers['Last-Modified'] = Time.now.httpdate if @max_last_change_at
          controller.response.headers['ETag'] = @digested_etag if @digested_etag
          controller.response.headers['Expires'] = expires.httpdate if expires = get_time_array(:first, @options[:expires_in], controller)
          controller.response.headers['Cache-Control'] = control if control = control_with_namespace(@options, controller)
        end

        protected
        # Get first or last time an array with Time or Procs that return Time objects
        #
        def get_time_array(first_or_last, time_array, controller, append_zero = false)
          processed_time_array = [time_array].flatten.compact.collect{|item| evaluate_method(item, controller) }
          processed_time_array << Time.utc(0) if append_zero
          if all_valid?(processed_time_array)
            return processed_time_array.map(&:to_time).map(&:utc).sort.send(first_or_last)
          else
            return nil
          end
        end

        def evaluate_method(item, controller)
          item.is_a?(Proc) || item.is_a?(Method) ? (item.arity > 0 ? item.call(controller) : item.call ) : item  
        end

        def all_valid?(array = [])
          array.select{|item| !item.respond_to?(:to_time)}.empty?
        end

        def control_with_namespace(options, controller)
          control = nil
          if options[:namespace]
            control = "private=(#{evaluate_method(options[:namespace], controller).to_s.gsub(/\s+/,' ').gsub(/[^a-zA-Z0-9_\-\.\s]/,'')})"
          elsif options[:control]
            control = options[:control].to_s
          end

          headers = controller.response.headers
          if headers['ETag'] || headers['Last-Modified']
            return "#{control || 'private'}, max-age=0, must-revalidate"
          elsif headers['Expires']
            return (control || 'public')
          else
            return control
          end
        end
      end

    end
  end
end

ActionController::Base.send :include, ActionController::Caching::HttpCache