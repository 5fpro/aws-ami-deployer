class App < Sinatra::Base
  configure do
    enable :logging
    file = File.new("#{ROOT_DIR}/log/#{RACK_ENV}.log", 'a+')
    file.sync = true
    use Rack::CommonLogger, file
  end

  get '/' do
    TestService.new.a
  end
end
