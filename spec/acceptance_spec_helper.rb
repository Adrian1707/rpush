require 'unit_spec_helper' # Shouldn't need to do this...
require 'fileutils'

TMP_DIR = '/tmp'
RAILS_DIR = File.join(TMP_DIR, 'rapns_test')
RAPNS_ROOT = File.expand_path(__FILE__ + '/../../')

def setup_rapns
  setup_rails
  generate
  migrate
end

def setup_rails
  return if $rails_is_setup
  `rm -rf #{RAILS_DIR}`
  FileUtils.mkdir_p(RAILS_DIR)
  cmd("bundle exec rails new #{RAILS_DIR} --skip-bundle")
  branch = `git branch | grep '\*'`.split(' ').last
  in_test_rails do
    cmd('echo "gem \'rake\'" >> Gemfile')
    if ENV['TRAVIS']
      cmd("echo \"gem 'rapns', :git => '#{RAPNS_ROOT}'\" >> Gemfile")
    else
      cmd("echo \"gem 'rapns', :git => '#{RAPNS_ROOT}', :branch => '#{branch}'\" >> Gemfile")
    end

    cmd("bundle install")
  end
end

def cmd(str, echo = false)
  puts "* #{str}" if echo
  Bundler.with_clean_env { `#{str}` }
end

def generate
  return if $generated
  $generated = true
  in_test_rails { cmd('bundle exec rails g rapns') }
end

def migrate
  return if $migrated
  $migrated = true
  in_test_rails { cmd('bundle exec rake db:migrate') }
end

def in_test_rails
  pwd = Dir.pwd
  begin
    Dir.chdir(RAILS_DIR)
    yield
  ensure
    Dir.chdir(pwd)
  end
end

def runner(str)
  in_test_rails { cmd("rails runner -e test '#{str}'").strip }
end

class MissingFixtureError < StandardError; end

def read_fixture(fixture)
  path = File.join(File.dirname(__FILE__), 'acceptance/fixtures', fixture)
  if !File.exists?(path)
    raise MissingFixtureError, "MISSING FIXTURE: #{path}"
  else
    File.read(path)
  end
end

def start_rapns
  in_test_rails do
    Bundler.with_clean_env do
      IO.popen('bundle exec rapns test -f', 'r')
    end
  end
end