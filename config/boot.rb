require 'rubygems'
require 'bundler'
Bundler.setup

RACK_ENV ||= ENV['RACK_ENV'] || 'development'
Bundler.require(:default, RACK_ENV)
require 'dotenv/load'

require 'sinatra'
require 'active_support/all'

ROOT_DIR = File.expand_path(File.join(File.dirname(__FILE__), '..')).freeze

require File.expand_path(File.join(File.dirname(__FILE__), 'application'))

App.root = ROOT_DIR

def App.env
  @env ||= RACK_ENV
end

Dir[File.join(App.root, 'app', '*')].each do |dir|
  require_all File.join(dir, '**', '*.rb')
end
