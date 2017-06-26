require 'rubygems'
require 'bundler'
Bundler.setup

RACK_ENV ||= ENV['RACK_ENV'] || 'development'
Bundler.require(:default, RACK_ENV)

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

unless App.env == 'development'
  log_file = File.new("#{App.root}/log/#{App.env}.log", 'a+')
  STDOUT.reopen(log_file)
  STDERR.reopen(log_file)
  STDOUT.sync = true
  STDERR.sync = true
end
