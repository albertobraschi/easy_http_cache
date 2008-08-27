# Those lines are plugin test settings
ENV["RAILS_ENV"] = "test"
require 'ostruct'
require File.dirname(__FILE__) + '/../../../../config/environment'
require File.dirname(__FILE__) + '/../lib/easy_http_cache.rb'
require 'test_help'

ActionController::Base.perform_caching = true
ActionController::Routing::Routes.draw do |map|
  map.connect ':controller/:action/:id'
end

class HttpCacheTestController < ActionController::Base
  before_filter :set_perform
  attr_accessor :filter_performed

  http_cache :index, :fail
  http_cache :show, :last_change_at => 2.hours.ago, :if => Proc.new { |c| !c.request.format.json? }
  http_cache :edit, :last_change_at => Proc.new{ 30.minutes.ago }
  http_cache :destroy, :last_change_at => [2.hours.ago, Proc.new{|c| 30.minutes.ago }]
  http_cache :invalid, :last_change_at => [1.hours.ago, false]

  http_cache :etag, :etag => Proc.new{ 'ETAG_CACHE' }, :control => :public
  http_cache :namespace, :namespace => Proc.new{ 'José 0 _ 0 vaLim' }, :control => :public
  http_cache :expires_in, :expires_in => 10.minutes
  http_cache :expires_at, :expires_at => [:some_time_from_now, Time.utc(2020)], :expires_in => [20.years, 15.years]
  http_cache :expires, :expires_at => [:some_time_from_now, Time.utc(0)], :expires_in => [20.years, 10.minutes]
  http_cache :resources, :last_change_at => [:resource, :list, :object]
  http_cache :resources_with_method, :last_change_at => [:resource, :list, :object], :method => :cached_at

  def index
    render :text => '200 OK', :status => 200
  end

  def fail
    render :text => '500 Internal Server Error', :status => 500
  end

  alias_method :show, :index
  alias_method :edit, :index
  alias_method :destroy, :index
  alias_method :invalid, :index
  alias_method :etag, :index
  alias_method :namespace, :index
  alias_method :expires_in, :index
  alias_method :expires_at, :index
  alias_method :expires, :index
  alias_method :resources, :index
  alias_method :resources_with_method, :index

  protected
    def set_perform
      @filter_performed = true
    end

    def some_time_from_now
      Time.utc(2014)
    end
    
    def resource
      resource = OpenStruct.new
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

class HttpCacheTest < Test::Unit::TestCase
  def setup
    reset!
  end

  def test_simple_http_cache_process
    http_cache_process(:show, 1.hour.ago, 3.hours.ago)
  end

  def test_http_cache_process_with_proc
    http_cache_process(:edit, 15.minutes.ago, 45.minutes.ago)
  end

  def test_http_cache_process_with_array
    http_cache_process(:destroy, 15.minutes.ago, 45.minutes.ago)
  end
  
  def test_http_cache_process_with_resources
    http_cache_process(:resources, 15.minutes.ago, 45.minutes.ago)
  end

  def test_http_cache_process_with_resources_with_method
    http_cache_process(:resources_with_method, 10.minutes.ago, 20.minutes.ago)
  end

  def test_http_cache_process_discards_invalid_input
    http_cache_process(:invalid, 30.minutes.ago, 90.minutes.ago)
  end

  def test_http_cache_without_expiration_time
    get :index
    assert_equal '200 OK', @response.headers['Status']
    assert_equal Time.utc(0).httpdate, @response.headers['Last-Modified']
    reset!

    @request.env['HTTP_IF_MODIFIED_SINCE'] = 1.hour.ago.httpdate
    get :index
    assert_equal '304 Not Modified', @response.headers['Status']
    assert_equal Time.utc(0).httpdate, @response.headers['Last-Modified']
    reset!

    @request.env['HTTP_IF_MODIFIED_SINCE'] = 3.hours.ago.httpdate
    get :index
    assert_equal '304 Not Modified', @response.headers['Status']
    assert_equal Time.utc(0).httpdate, @response.headers['Last-Modified']
  end

  def test_http_cache_with_conditional_options
    @request.env['HTTP_ACCEPT'] = 'application/json'
    get :show
    assert_nil @response.headers['Last-Modified']
    reset!

    @request.env['HTTP_ACCEPT'] = 'application/json'
    @request.env['HTTP_IF_MODIFIED_SINCE'] = 1.hour.ago.httpdate
    get :show
    assert_equal '200 OK', @response.headers['Status']
  end

  def test_http_cache_should_not_perform_with_500_status
    # It does not send a Last-Modified field
    get :fail
    assert_equal '500 Internal Server Error', @response.headers['Status']
    assert_nil @response.headers['Last-Modified']
    assert_nil @response.headers['Expires']
    assert_nil @response.headers['ETag']
    reset!

    # But it can process the HTTP_IF_MODIFIED_SINCE 
    @request.env['HTTP_IF_MODIFIED_SINCE'] = 1.hour.ago.httpdate
    get :fail
    assert_equal '304 Not Modified', @response.headers['Status']
    assert @response.headers['Last-Modified']
    assert_nil @response.headers['Expires']
    assert_nil @response.headers['ETag']
  end

  def test_http_etag_cache
    get :etag
    assert_equal '200 OK', @response.headers['Status']
    assert_equal 'public, max-age=0, must-revalidate', @response.headers['Cache-Control']
    assert_equal etag_for('ETAG_CACHE'), @response.headers['ETag']
    reset!

    @request.env['HTTP_IF_NONE_MATCH'] = etag_for('ETAG_CACHE')
    get :etag
    assert_equal '304 Not Modified', @response.headers['Status']
    assert_equal etag_for('ETAG_CACHE'), @response.headers['ETag']
    reset!

    @request.env['ETag'] = 'ETAG_CACHE'
    get :etag
    assert_equal '200 OK', @response.headers['Status']
    assert_equal 'public, max-age=0, must-revalidate', @response.headers['Cache-Control']
    assert_equal etag_for('ETAG_CACHE'), @response.headers['ETag']
  end

  def test_private_namespace
    get :namespace
    assert_equal '200 OK', @response.headers['Status']
    assert_equal 'private=(Jos 0 _ 0 vaLim), max-age=0, must-revalidate', @response.headers['Cache-Control']
    assert @response.headers['Last-Modified']
    assert_nil @response.headers['Expires']
  end

  def test_expires_at
    get :expires_at
    assert_equal '200 OK', @response.headers['Status']
    assert_equal 'public', @response.headers['Cache-Control']
    assert_equal 'Wed, 01 Jan 2014 00:00:00 GMT', @response.headers['Expires']
    assert_nil @response.headers['Last-Modified']
  end

  def test_expires_in
    get :expires_in
    assert_equal '200 OK', @response.headers['Status']
    assert_equal 'public', @response.headers['Cache-Control']
    expires = Time.rfc2822(@response.headers['Expires'])
    assert expires > 8.minutes.from_now && expires < 12.minutes.from_now
    assert_nil @response.headers['Last-Modified']
  end
  
  def test_expires_with_time_before_current_time
    get :expires_in
    assert_equal '200 OK', @response.headers['Status']
    assert_equal 'public', @response.headers['Cache-Control']
    expires = Time.rfc2822(@response.headers['Expires'])
    assert expires > 8.minutes.from_now && expires < 12.minutes.from_now
    assert_nil @response.headers['Last-Modified']
  end

  def test_should_not_cache_when_rendering_components
    set_parent_controller! 

    get :show
    assert_equal '200 OK', @response.headers['Status']
    assert_equal 'private, max-age=0, must-revalidate', @response.headers['Cache-Control']
    assert @response.headers['Last-Modified']

    set_parent_controller!

    @request.env['HTTP_IF_MODIFIED_SINCE'] = 1.hour.ago.httpdate
    get :show
    assert_equal '200 OK', @response.headers['Status']
    assert_equal 'private, max-age=0, must-revalidate', @response.headers['Cache-Control']
    assert @response.headers['Last-Modified']

    set_parent_controller!

    @request.env['HTTP_IF_MODIFIED_SINCE'] = 3.hours.ago.httpdate
    get :show
    assert_equal '200 OK', @response.headers['Status']
    assert_equal 'private, max-age=0, must-revalidate', @response.headers['Cache-Control']
    assert @response.headers['Last-Modified']
  end

  private
    def reset!
      @request = ActionController::TestRequest.new
      @response = ActionController::TestResponse.new
      @controller = HttpCacheTestController.new
    end

    def set_parent_controller!
      get :index
      old_controller = @controller.dup
      reset!

      @controller.instance_variable_set('@parent_controller', old_controller)
    end

    def etag_for(string)
      %("#{Digest::MD5.hexdigest(string)}")
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
    def http_cache_process(action, not_expired_time, expired_time)
      get action
      assert_equal '200 OK', @response.headers['Status']
      assert_equal 'private, max-age=0, must-revalidate', @response.headers['Cache-Control']
      assert @response.headers['Last-Modified']
      reset!

      @request.env['HTTP_IF_MODIFIED_SINCE'] = not_expired_time.httpdate
      get action
      assert_equal '304 Not Modified', @response.headers['Status']
      assert @response.headers['Last-Modified']
      reset!

      @request.env['HTTP_IF_MODIFIED_SINCE'] = expired_time.httpdate
      get action
      assert_equal '200 OK', @response.headers['Status']
      assert_equal 'private, max-age=0, must-revalidate', @response.headers['Cache-Control']
      assert @response.headers['Last-Modified']
    end
end
