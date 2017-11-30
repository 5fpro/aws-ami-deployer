class App < Sinatra::Base

  set :dump_errors, true
  set :show_exceptions, true

  get '/' do
    'Hi'
  end

  post '/deploy' do
    Deployer.new(params['deploy'].deep_symbolize_keys.merge(log_id: params[:no])).perform
  end

  get '/log' do
    log_file = File.join(App.root, 'log', "deploy-#{params[:no]}.log")
    body = File.exist?(log_file) ? `cat #{log_file}`.to_s.gsub("\n", "<br />\n") : 'Log file is not exists.'
    reload_script = '<script>setTimeout(function(){location.reload();}, 5000);window.scrollTo(0,document.body.scrollHeight);</script>'
    if params['live']
      "<div><a href=\"?no=#{params[:no]}\">Stop auto reload</a></div>" + body + reload_script
    else
      "<div><a href=\"?no=#{params[:no]}&live=1\">Auto reload</a></div>" + body
    end
  end
end
