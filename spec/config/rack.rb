require 'rack/test'

module RSpecMixin
  include Rack::Test::Methods
  def app
    ::App
  end
end

RSpec.configure do |config|
  config.include RSpecMixin
end
