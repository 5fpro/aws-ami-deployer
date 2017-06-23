require 'rubygems'
require 'bundler'
Bundler.setup

RACK_ENV ||= ENV['RACK_ENV'] || 'development'
Bundler.require(:default, RACK_ENV)

require 'sinatra'

require File.expand_path(File.join(File.dirname(__FILE__), 'application'))

def App.root
  @root ||= File.expand_path(File.join(File.dirname(__FILE__), '..'))
end

def App.env
  @env ||= RACK_ENV
end

# Dir[File.join(App.root, 'app', '*')].each do |dir|
#   # May not resolve dependency problem
#   Dir.glob(File.join(dir, '*.rb')).each { |f| require f }
# end
