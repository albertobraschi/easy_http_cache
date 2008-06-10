Copyright (c) 2008 José Valim (jose.valim at gmail dot com)
Site: http://www.pagestacker.com/
Blog: http://josevalim.blogspot.com/
License: MIT
Version: 1.2

Description
-----------

Allows Rails applications to use HTTP 1.1 cache specifications easily:

  class ListsController < ApplicationController
    http_cache :index, :show
  end

It accepts a wide range of options used to manipulate your cache
headers. Those options usually accepts also Proc, Method and Symbols
that are evaluated within the current controller and must return the
specified in which option. You can also pass Arrays, except when is
said otherwise.

  :last_change_at
    Used to manipulate Last-Modified header.
    It accepts anything that responds to the method :to_time,
    :updated_at or :updated_on, allowing also to pass resources.
    At least, you can pass an Array and it will get the newest time
    from it to compare with the time sent by the client.

  :etag
    Used to manipulate Etag header.
    It accepts anything that responds to the method :to_s.
    Does not accept Array.

  :namespace
    It adds user control to cache responding with "private=(namespace)".
    It accepts anything that responds to the method :to_s.
    Does not accept Array.
  
  :expires_in
    Used to manipulate Expires header.
    It accepts anything that responds to the method :to_time.
    At least, you can pass an Array and it will get the closest time
    from it to send to the client.
  
  :control
    Specifies Cache-Control header, accepts ONLY :public or :private
    If it's not specified, doesn't change the header.

  :if
    Only perform http cache if the result of the Proc, Method or Symbol is true

  :unless
    Only perform http cache if the result of the Proc, Method or Symbol is false

Install
-------

This plugin uses features that only exist on Rails 2.1 and above.
So if you just want a static copy of the plugin:

    cd myapp
    git clone git://github.com/josevalim/easy-http-cache.git vendor/plugins/eash_http_cache
    rm -rf vendor/plugins/easy_http_cache/.git

Examples
--------

Just as above:

  class ListsController < ApplicationController
    http_cache :index, :show
  end

If you do not want to cache json requests, you can simply do:

  class ListsController < ApplicationController
    http_cache :index, :show, :if => Proc.new { |c| !c.request.format.json? }
  end

Another important example (perform cache only if flash is empty):

  class ListsController < ApplicationController
    http_cache :index, :show, :if => Proc.new { |c| c.send(:flash).empty? }
  end

You can easily set Expires header to expire all cache 1 hour after
the request:

  class ListsController < ApplicationController
    http_cache :index, :show, :expires_in => Proc.new { 1.hour.from_now }
  end

And you can also set :etag header (it also accepts Procs):

  class ListsController < ApplicationController
    http_cache :index, :show, :etag => 'this_will_never_change', :control => :public
  end

All etags will be Digested with MD5, so if you want to use a string,
feel free to put something that matters to you.

Or if you want to expire all http cache before 2008, just do:

  class ListsController < ApplicationController
    http_cache :index, :show, :last_change_at => Time.utc(2008)
  end

Or if you are looking into something more dynamic:

  class ListsController < ApplicationController
    http_cache :index, :show, :last_change_at => Proc.new{ 10.minutes.ago }
  end

How the last example works?
---------------------------

The first time http://www.railsapp.com/lists/index is requested, it renders the
action normally but adds a "Last-Modified" to your response with the current
request time, let's suppose 10h30.

If the client do another request at 10h35, the http_cache will check that
:last_change_at and see that the last change was at 10h25, which is older than
the "Last-Modified" field (10h30) returned by the client's browser, so it sends
a "304 Not Modified" response and does not execute the action.

But, if another request from the same client comes at 10h42, the last change was
at 10h32, which is newer than the "Last-Modified" field (10h30), so the action
is performed again and "Last-Modified" field set at 10h42.

More examples
-------------

Now we understand how it works, we can do even more dynamic caches!

So, if You want to cache a list and automatically expire the cache when
it changes, just do:

  class ListsController < ApplicationController
    http_cache :index, :show, :last_change_at => :list

    protected
    def list
      @list ||= List.find(params[:id])
    end
  end

This will automatically call the list method on your controller, get
the object @list and call updated_at or updated_on on it.

Finally, you can also pass an array at :last_change_at as below:

  class ListsController < ApplicationController
    http_cache :index, :show,
               :last_change_at => [ Time.utc(2007,12,27), Proc.new { 10.minutes.ago } ]
  end

This will check which one is the newest time to compare with the
"Last-Modified" field sent by the client.

Namespaces
----------

Do you have a page that is different for each user, but has the same url. How
would you guarantee that they won't see each other page if they are on the same
computer? Just do:

  class ListsController < ApplicationController
    http_cache :index, :show,
               :last_change_at => Time.utc(2008),
               :namespace => Proc.new{|c| c.get_instance_variable('@current_user').username}
  end

If the namespace is 'josevalim', the header will be:

  headers['Cache-Control'] = 'private=(josevalim), max-age=0, must-revalidate'

The namespace only accepts some [a-z], [A-Z], single spaces, dot (.),
line (-) and underline (_). It's also case sensitive.