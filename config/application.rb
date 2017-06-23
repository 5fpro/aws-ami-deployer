class App < Sinatra::Base
  get '/' do
    'Hi'
  end

  post '/deploy' do
    Deployer.new(params['deploy'].deep_symbolize_keys).perform
  end
end
