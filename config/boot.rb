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
  @env ||= String.new(RACK_ENV)
  unless @env.respond_to?(:method_missing)
    def @env.method_missing(method_name, *args)
      return self == method_name.to_s[0..-2] if method_name.to_s[-1] == '?'
      super
    end
  end
  @env
end

Dir[File.join(App.root, 'app', '*')].each do |dir|
  require_all File.join(dir, '**', '*.rb')
end
