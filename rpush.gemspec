# -*- encoding: utf-8 -*-
$:.push File.expand_path("../lib", __FILE__)
require "rpush/version"

Gem::Specification.new do |s|
  s.name        = "rpush"
  s.version     = Rpush::VERSION
  s.authors     = ["Ian Leitch"]
  s.email       = ["port001@gmail.com"]
  s.homepage    = "https://github.com/rpush/rpush"
  s.summary     = %q{Professional grade APNs and GCM for Ruby}
  s.description = %q{Professional grade APNs and GCM for Ruby}
  s.license    = "MIT"

  s.files         = `git ls-files -- lib README.md CHANGELOG.md LICENSE`.split("\n")
  s.test_files    = `git ls-files -- {test,spec,features,config}`.split("\n")
  s.executables   = `git ls-files -- bin`.split("\n").map{ |f| File.basename(f) }
  s.require_paths = ["lib"]

  s.add_dependency "multi_json", "~> 1.0"
  s.add_dependency "net-http-persistent"

  if defined? JRUBY_VERSION
    s.platform = 'java'
    s.add_dependency "jruby-openssl"
    s.add_dependency "activerecord-jdbc-adapter"
  end
end
