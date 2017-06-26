class App < Sinatra::Base

  set :dump_errors, true
  set :show_exceptions, true

  get '/' do
    TestService.new.a
  end
end
