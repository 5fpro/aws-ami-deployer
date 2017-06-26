class App < Sinatra::Base
  get '/' do
    'Hi'
  end

  post '/deploy' do
    Deployer.new(params['deploy'].symbolize_keys).perform
  end
end
