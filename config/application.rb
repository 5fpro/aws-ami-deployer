class App < Sinatra::Base
  get '/' do
    'Hi'
  end

  post '/deploy' do
    Deployer.new(params['deploy'].symbolize_keys).perform
  end

  get '/log' do
    n = params[:n] || 20
    `tail -n #{n} -f #{App.root}/log/#{App.env}.log`
  end
end
