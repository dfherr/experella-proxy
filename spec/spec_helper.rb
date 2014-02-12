# This file was generated by the `rspec --init` command. Conventionally, all
# specs live under a `spec` directory, which RSpec adds to the `$LOAD_PATH`.
# Require this file using `require "spec_helper"` to ensure that it is only
# loaded once.
#
# See http://rubydoc.info/gems/rspec-core/RSpec/Core/Configuration
require 'rubygems'
require 'bundler'
Bundler.setup

require 'pathname'

LIB_ROOT= Pathname.new(File.dirname(__FILE__) +"/../")
RSPEC_ROOT=LIB_ROOT.join("spec")
$: << LIB_ROOT.join("lib")
require 'experella-proxy.rb'
require 'em-http'
require 'posix/spawn'

# clear spec logfile on startup
File.new(File.join(File.expand_path(File.dirname(__FILE__)),"/fixtures/spec.log"), "w+")
# load config once before all specs
ExperellaProxy::Configuration.new(:configfile => File.join(File.dirname(__FILE__),"/fixtures/test_config.rb"))

RSpec.configure do |config|
  config.treat_symbols_as_metadata_keys_with_true_values = true
  config.run_all_when_everything_filtered = true
  config.filter_run :focus

  # Run specs in random order to surface order dependencies. If you find an
  # order dependency and want to debug it, you can fix the order by providing
  # the seed, which is printed after each run.
  #     --seed 1234
  config.order = 'random'
end