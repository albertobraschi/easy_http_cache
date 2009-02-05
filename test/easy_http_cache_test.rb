# Those lines are plugin test settings
require 'test/unit'
require 'rubygems'
require 'ostruct'

ENV["RAILS_ENV"] = "test"

require 'active_support'
require 'action_controller'
require 'action_controller/test_case'
require 'action_controller/test_process'

require File.dirname(__FILE__) + '/../lib/easy_http_cache.rb'

ActionController::Base.perform_caching = true
ActionController::Routing::Routes.draw do |map|
  map.connect ':controller/:action/:id'
end

class HttpCacheTestController < ActionController::Base
  http_cache :index
  http_cache :show, :last_modified => 2.hours.ago, :if => Proc.new { |c| !c.request.format.json? }
  http_cache :edit, :last_modified => Proc.new{ 30.minutes.ago }
  http_cache :destroy, :last_modified => [2.hours.ago, Proc.new{|c| 30.minutes.ago }]
  http_cache :invalid, :last_modified => [1.hours.ago, false]

  http_cache :etag, :etag => 'ETAG_CACHE'
  http_cache :etag_array, :etag => [ 'ETAG_CACHE', :resource ]
  http_cache :resources, :last_modified => [:resource, :list, :object]
  http_cache :resources_with_method, :last_modified => [:resource, :list, :object], :method => :cached_at

  def index
    render :text => '200 OK', :status => 200
  end

  alias_method :show, :index
  alias_method :edit, :index
  alias_method :destroy, :index
  alias_method :invalid, :index
  alias_method :etag, :index
  alias_method :etag_array, :index
  alias_method :resources, :index
  alias_method :resources_with_method, :index

  protected

    def resource
      resource = OpenStruct.new
      resource.instance_eval do
        def to_param
          12345
        end
      end

      resource.updated_at = 2.hours.ago
      resource
    end

    def list
      list = OpenStruct.new
      list.updated_on = 30.minutes.ago
      list
    end

    def object
      object = OpenStruct.new
      object.cached_at = 15.minutes.ago
      object
    end
end

class HttpCacheTest < ActionController::TestCase
  def setup
    reset!
  end

  def test_last_modified_http_cache
    last_modified_http_cache(:show, 1.hour.ago, 3.hours.ago)
  end

  def test_last_modified_http_cache_with_proc
    last_modified_http_cache(:edit, 15.minutes.ago, 45.minutes.ago)
  end

  def test_last_modified_http_cache_with_array
    last_modified_http_cache(:destroy, 15.minutes.ago, 45.minutes.ago)
  end
  
  def test_last_modified_http_cache_with_resources
    last_modified_http_cache(:resources, 15.minutes.ago, 45.minutes.ago)
  end

  def test_last_modified_http_cache_with_resources_with_method
    last_modified_http_cache(:resources_with_method, 10.minutes.ago, 20.minutes.ago)
  end

  def test_last_modified_http_cache_discards_invalid_input
    last_modified_http_cache(:invalid, 30.minutes.ago, 90.minutes.ago)
  end

  def test_http_cache_without_input
    get :index
    assert_headers('200 OK', 'private, max-age=0, must-revalidate', 'Last-Modified', Time.utc(0).httpdate)
    reset!

    @request.env['HTTP_IF_MODIFIED_SINCE'] = 1.hour.ago.httpdate
    get :index
    assert_headers('304 Not Modified', 'private, max-age=0, must-revalidate', 'Last-Modified', Time.utc(0).httpdate)
    reset!

    @request.env['HTTP_IF_MODIFIED_SINCE'] = 3.hours.ago.httpdate
    get :index
    assert_headers('304 Not Modified', 'private, max-age=0, must-revalidate', 'Last-Modified', Time.utc(0).httpdate)
  end

  def test_http_cache_with_conditional_options
    @request.env['HTTP_ACCEPT'] = 'application/json'
    get :show
    assert_nil @response.headers['Last-Modified']
    reset!

    @request.env['HTTP_ACCEPT'] = 'application/json'
    @request.env['HTTP_IF_MODIFIED_SINCE'] = 1.hour.ago.httpdate
    get :show
    assert_equal '200 OK', @response.status
  end

  def test_etag_http_cache
    etag_http_cache(:etag, 'ETAG_CACHE')
  end

  def test_etag_http_cache_with_array
    etag_http_cache(:etag_array, ['ETAG_CACHE', 12345])
  end

  def test_etag_http_cache_with_env_variable
    ENV['RAILS_APP_VERSION'] = '1.2.3'
    etag_http_cache(:etag, 'ETAG_CACHE')
  end

  private
    def reset!
      @request = ActionController::TestRequest.new
      @response = ActionController::TestResponse.new
      @controller = HttpCacheTestController.new
    end

    def etag_for(etag)
      %("#{Digest::MD5.hexdigest(ActiveSupport::Cache.expand_cache_key(etag))}")
    end

    def assert_headers(status, control, cache_header=nil, value=nil)
      assert_equal status, @response.status
      assert_equal control, @response.headers['Cache-Control']

      if cache_header
        if value
          assert_equal value, @response.headers[cache_header]
        else
          assert @response.headers[cache_header]
        end
      end
    end

    # Goes through a http cache process:
    #
    #   1. Request an action
    #   2. Get a '200 OK' status
    #   3. Request the same action with a not expired HTTP_IF_MODIFIED_SINCE
    #   4. Get a '304 Not Modified' status
    #   5. Request the same action with an expired HTTP_IF_MODIFIED_SINCE
    #   6. Get a '200 OK' status
    #   
    def last_modified_http_cache(action, not_expired_time, expired_time)
      get action
      assert_headers('200 OK', 'private, max-age=0, must-revalidate', 'Last-Modified')
      reset!

      @request.env['HTTP_IF_MODIFIED_SINCE'] = not_expired_time.httpdate
      get action
      assert_headers('304 Not Modified', 'private, max-age=0, must-revalidate', 'Last-Modified')
      reset!

      @request.env['HTTP_IF_MODIFIED_SINCE'] = expired_time.httpdate
      get action
      assert_headers('200 OK', 'private, max-age=0, must-revalidate', 'Last-Modified')
    end

    # Goes through a http cache process:
    #
    #   1. Request an action
    #   2. Get a '200 OK' status
    #   3. Request the same action with a valid ETAG
    #   4. Get a '304 Not Modified' status
    #   5. Request the same action with an invalid IF_NONE_MATCH
    #   6. Get a '200 OK' status
    #   
    def etag_http_cache(action, variable)
      get action
      assert_headers('200 OK', 'private, max-age=0, must-revalidate', 'ETag', etag_for(variable))
      reset!

      @request.env['HTTP_IF_NONE_MATCH'] = etag_for(variable)
      get action
      assert_headers('304 Not Modified', 'private, max-age=0, must-revalidate', 'ETag', etag_for(variable))
      reset!

      @request.env['HTTP_IF_NONE_MATCH'] = 'INVALID'
      get action
      assert_headers('200 OK', 'private, max-age=0, must-revalidate', 'ETag', etag_for(variable))
    end
end
