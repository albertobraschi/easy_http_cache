module ActionController #:nodoc:
  module Caching
    module HttpCache
      mattr_accessor :default_last_change_at

      def self.included(base) #:nodoc:
        base.extend(ClassMethods)
      end

      module ClassMethods
        # Declares that +actions+ should be cached.
        # If none "complex Proc" (i.e. arity > 0) is detected in :last_change_at and, prepends the cache filter (this works as Rails caches_page).
        def http_cache(*actions)
          return unless perform_caching
          options = actions.extract_options!
          last_changes = options.delete(:last_change_at)

          if has_complex_proc?(last_changes) || has_complex_proc?(ActionController::Caching::HttpCache.default_last_change_at) || has_complex_proc?(options[:if])
            around_filter(HttpCacheFilter.new(last_changes), {:only => actions}.merge(options))
          else
            prepend_around_filter(HttpCacheFilter.new(last_changes), {:only => actions}.merge(options))
          end
        end

        private 
        # Returns true if the given object has or is a Proc with arity > 0
        def has_complex_proc?(object) #:nodoc:
          !Array(object).select{|item| item.is_a?(Proc) || item.is_a?(Method) ? item.arity > 0 : false}.empty?
        end
      end

      class HttpCacheFilter #:nodoc:
        def initialize(last_changes)
          @last_changes = [last_changes].flatten.compact
          @http_cache_allowed = nil
        end

        def before(controller)
          return unless controller.request.get?
          last_change_at = get_last_change(controller)

          if @http_cache_allowed && controller.request.env['HTTP_IF_MODIFIED_SINCE'] && (last_change_at.blank? || last_change_at <= Time.rfc2822(controller.request.env['HTTP_IF_MODIFIED_SINCE']))
            controller.send!(:render, :text => '304 Not Modified', :status => 304)
            return false
          end
        end

        def after(controller)
          return unless @http_cache_allowed && controller.request.get? && controller.response.headers['Status'].to_i == 200
          controller.response.headers['Last-Modified'] = Time.now.httpdate
        end

        protected
        # Get newest time from @last_changes (sent through :last_change_at) and from @@default_last_change_at.
        # Set http_cache_allowed to false if not only Time (and Date, DateTime, TimeZone...) objects are found in the attributes above.
        def get_last_change(controller)
          processed_last_changes = evaluate_methods(controller, @last_changes + [ActionController::Caching::HttpCache.default_last_change_at].flatten.compact)
          if @http_cache_allowed = all_valid?(processed_last_changes)
            return processed_last_changes.map(&:to_time).sort.last
          else
            return nil
          end
        end

        def evaluate_methods(controller, array = [])
          array.collect{|item| item.is_a?(Proc) || item.is_a?(Method) ? (item.arity > 0 ? item.call(controller) : item.call ) : item}  
        end

        def all_valid?(array = [])
          array.select{|item| !item.respond_to?(:to_time)}.empty?
        end
      end
    end
  end
end

ActionController::Base.send :include, ActionController::Caching::HttpCache
