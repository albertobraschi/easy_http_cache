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
  before_filter :set_perform
  attr_accessor :filter_performed

  http_cache :index, :fail
  http_cache :show, :last_change_at => 2.hours.ago, :if => Proc.new { |c| !c.request.format.json? }
  http_cache :edit, :last_change_at => Proc.new{ 30.minutes.ago }
  http_cache :destroy, :last_change_at => [2.hours.ago, Proc.new{|c| 30.minutes.ago }]
  http_cache :invalid, :last_change_at => [2.hours.ago, false]

  http_cache :etag, :etag => Proc.new{ 'ETAG_CACHE' }, :control => :public
  http_cache :namespace, :namespace => Proc.new{ 'José 0 _ 0 vaLim' }, :control => :public
  http_cache :expires, :expires_in => [Time.utc(2014), Time.utc(2020)]

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
  alias_method :expires, :index

  protected
  def set_perform
    @filter_performed = true
  end
end

class HttpCacheTest < Test::Unit::TestCase
  def setup
    reset!
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

  def test_http_cache_should_not_perform_with_invalid_last_change_at
    @request.env['HTTP_IF_MODIFIED_SINCE'] = 1.hour.ago.httpdate
    get :invalid
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

  def test_http_etag_cache
    get :etag
    assert_equal '200 OK', @response.headers['Status']
    assert_equal 'public, max-age=0, must-revalidate', @response.headers['Cache-Control']
    assert @response.headers['ETag']
    reset!

    @request.env['HTTP_IF_NONE_MATCH'] = %("#{Digest::MD5.hexdigest('ETAG_CACHE')}")
    get :etag
    assert_equal '304 Not Modified', @response.headers['Status']
    assert_nil @response.headers['ETag']
    reset!

    @request.env['ETag'] = 'ETAG_CACHE'
    get :etag
    assert_equal '200 OK', @response.headers['Status']
    assert_equal 'public, max-age=0, must-revalidate', @response.headers['Cache-Control']
    assert @response.headers['ETag']
  end

  def test_last_modified_is_not_sent_in_etag_cache
    get :etag
    assert_equal '200 OK', @response.headers['Status']
    assert_nil @response.headers['Last-Modified']
  end

  def test_private_namespace
    get :namespace
    assert_equal '200 OK', @response.headers['Status']
    assert_equal 'private=(Jos 0 _ 0 vaLim), max-age=0, must-revalidate', @response.headers['Cache-Control']
    assert @response.headers['Last-Modified']
  end

  def test_expires_in
    get :expires
    assert_equal '200 OK', @response.headers['Status']
    assert_equal 'public', @response.headers['Cache-Control']
    assert_equal 'Wed, 01 Jan 2014 00:00:00 GMT', @response.headers['Expires']
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
      assert_equal 'private, max-age=0, must-revalidate', @response.headers['Cache-Control']
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
      assert_equal 'private, max-age=0, must-revalidate', @response.headers['Cache-Control']
      assert @response.headers['Last-Modified']
    end
end
