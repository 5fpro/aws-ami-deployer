class App < Sinatra::Base

  set :dump_errors, true
  set :show_exceptions, true

  get '/' do
    'Hi'
  end

  post '/deploy' do
    Deployer.new(params['deploy'].symbolize_keys.merge(log_id: params[:no])).perform
  end

  get '/log' do
    log_file = File.join(App.root, 'log', "deploy-#{params[:no]}.log")
    reload_script = params['live'] ? '<script>setTimeout(function(){location.reload();}, 5000);</script>' : ''
    res = `cat #{log_file}`
    res.to_s.gsub("\n", "<br />\n") + reload_script
  end
end
