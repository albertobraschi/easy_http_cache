# Those lines are plugin test settings
ENV["RAILS_ENV"] = "test"
require File.dirname(__FILE__) + '/../../../../config/environment'
require File.dirname(__FILE__) + '/../lib/easy_http_cache.rb'
require 'test_help'

ActionController::Base.perform_caching = true
ActionController::Routing::Routes.draw do |map|
  map.connect ':controller/:action/:id'
end

class HttpCacheTestController < ActionController::Base
  before_filter :filter  
  http_cache :index, :fail
  http_cache :show, :last_change_at => 2.hours.ago, :if => Proc.new { |c| !c.request.format.json? }
  http_cache :edit, :last_change_at => Proc.new{ 30.minutes.ago }
  http_cache :destroy, :last_change_at => [2.hours.ago, Proc.new{|c| 30.minutes.ago }]
  attr_accessor :filter_performed

  def index
    render :text => '200 OK', :status => 200
  end

  def fail
    render :text => '500 Internal Server Error', :status => 500
  end

  alias_method :show, :index
  alias_method :edit, :index
  alias_method :destroy, :index

  protected
  def filter
    @filter_performed = true
  end
end

class HttpCacheTest < Test::Unit::TestCase
  def setup
    reset!
    ActionController::Caching::HttpCache.default_last_change_at = nil
  end

  def test_default_last_change_at_attr
    ActionController::Caching::HttpCache.default_last_change_at = Time.utc(2000)
    assert_equal Time.utc(2000), ActionController::Caching::HttpCache.default_last_change_at
  end

  def test_append_filter
    @request.env['HTTP_IF_MODIFIED_SINCE'] = 1.hour.ago.httpdate
    get :index
    assert_nil @controller.filter_performed
    reset!

    @request.env['HTTP_IF_MODIFIED_SINCE'] = 1.hour.ago.httpdate
    get :show
    assert @controller.filter_performed
    reset!

    @request.env['HTTP_IF_MODIFIED_SINCE'] = 30.seconds.ago.httpdate
    get :edit
    assert_nil @controller.filter_performed
    reset!

    @request.env['HTTP_IF_MODIFIED_SINCE'] = 30.seconds.ago.httpdate
    get :destroy
    assert @controller.filter_performed
  end

  def test_simple_http_cache_process
    http_cache_process(:show,1.hour.ago,3.hours.ago)
  end

  def test_http_cache_process_with_proc
    http_cache_process(:edit,15.minutes.ago,45.minutes.ago)
  end

  def test_http_cache_process_with_array
    http_cache_process(:destroy,15.minutes.ago,45.minutes.ago)
  end

  def test_http_cache_without_expiration_time
    get :index
    assert_equal '200 OK', @response.headers['Status']
    assert @response.headers['Last-Modified']
    reset!

    @request.env['HTTP_IF_MODIFIED_SINCE'] = 1.hour.ago.httpdate
    get :index
    assert_equal '304 Not Modified', @response.headers['Status']
    assert_nil @response.headers['Last-Modified']
    reset!

    @request.env['HTTP_IF_MODIFIED_SINCE'] = 3.hours.ago.httpdate
    get :index
    assert_equal '304 Not Modified', @response.headers['Status']
    assert_nil @response.headers['Last-Modified']
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

  def test_http_cache_with_default_last_change_at
    ActionController::Caching::HttpCache.default_last_change_at = [2.hours.ago, Proc.new{|c| 30.minutes.ago }]
    http_cache_process(:index,15.minutes.ago,45.minutes.ago)
  end

  def test_http_cache_should_not_perform
    ActionController::Caching::HttpCache.default_last_change_at = [2.hours.ago, false]
    @request.env['HTTP_IF_MODIFIED_SINCE'] = 1.hour.ago.httpdate
    get :index
    assert_equal '200 OK', @response.headers['Status']
    assert_nil @response.headers['Last-Modified']
  end

  def test_http_cache_should_not_perform_with_post
    post :show
    assert_equal '200 OK', @response.headers['Status']
    assert_nil @response.headers['Last-Modified']
    reset!

    @request.env['HTTP_IF_MODIFIED_SINCE'] = 1.hour.ago.httpdate
    post :show
    assert_equal '200 OK', @response.headers['Status']
    assert_nil @response.headers['Last-Modified']
  end

  def test_http_cache_should_not_perform_with_500_status
    # It does not send a Last-Modified field
    get :fail
    assert_equal '500 Internal Server Error', @response.headers['Status']
    assert_nil @response.headers['Last-Modified']
    reset!

    # But it can process the HTTP_IF_MODIFIED_SINCE 
    @request.env['HTTP_IF_MODIFIED_SINCE'] = 1.hour.ago.httpdate
    get :fail
    assert_equal '304 Not Modified', @response.headers['Status']
    assert_nil @response.headers['Last-Modified']
  end

  private
    def reset!
      @request = ActionController::TestRequest.new
      @response = ActionController::TestResponse.new
      @controller = HttpCacheTestController.new
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
      assert @response.headers['Last-Modified']
      reset!

      @request.env['HTTP_IF_MODIFIED_SINCE'] = not_expired_time.httpdate
      get action
      assert_equal '304 Not Modified', @response.headers['Status']
      assert_nil @response.headers['Last-Modified']
      reset!

      @request.env['HTTP_IF_MODIFIED_SINCE'] = expired_time.httpdate
      get action
      assert_equal '200 OK', @response.headers['Status']
      assert @response.headers['Last-Modified']
    end
end