class App < Sinatra::Base
  get '/' do
    'Hi'
  end

  post '/deploy' do
    Deployer.new(params['deploy'].symbolize_keys).perform
  end

  get '/log' do
    Thread.current[:log].join("<br />\n")
  end
end
