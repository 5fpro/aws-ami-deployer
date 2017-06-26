class App < Sinatra::Base

  set :dump_errors, true
  set :show_exceptions, true

  get '/' do
    'Hi'
  end

  post '/deploy' do
    puts "deploy##{params[:no]}"
    Deployer.new(params['deploy'].symbolize_keys).perform
  end

  get '/logging' do
    res = `cat log/#{App.env}.log | awk 'BEGIN{ found=0} /deploy##{params[:no]}/{found=1}  {if (found) print }'`
    res.to_s.gsub("\n", "<br />\n")
  end
end
