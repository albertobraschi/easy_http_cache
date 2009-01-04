Gem::Specification.new do |s|
  s.name     = "easy_http_cache"
  s.version  = "2.0"
  s.date     = "2008-11-29"
  s.summary  = "Allows Rails applications to use HTTP cache specifications easily."
  s.email    = "jose.valim@gmail.com"
  s.homepage = "http://github.com/josevalim/easy_http_cache"
  s.description = "Allows Rails applications to use HTTP cache specifications easily."
  s.has_rdoc = true
  s.authors  = [ "José Valim" ]
  s.files    = [
    "MIT-LICENSE",
		"README",
		"Rakefile",
		"lib/easy_http_cache.rb",
    "test/easy_http_cache_test.rb"
  ]
  s.test_files = [
    "test/easy_http_cache_test.rb"
  ]
  s.rdoc_options = ["--main", "README"]
  s.extra_rdoc_files = ["README"]
end
