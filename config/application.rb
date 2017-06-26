class App < Sinatra::Base

  set :dump_errors, true
  set :show_exceptions, true

  get '/' do
    'Hi'
  end

  post '/deploy' do
    Deployer.new(params['deploy'].symbolize_keys).perform
  end
end
