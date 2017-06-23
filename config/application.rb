class App < Sinatra::Base
  get '/' do
    TestService.new.a
  end
end
