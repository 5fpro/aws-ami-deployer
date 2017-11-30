# config valid only for current version of Capistrano
lock '3.8.2'

set :application, ENV['APP_NAME']
set :repo_url, 'git@github.com:5fpro/aws-ami-deployer.git'

# Default branch is :master
ask :branch, `git rev-parse --abbrev-ref HEAD`.chomp

# Default deploy_to directory is /var/www/my_app_name
# set :deploy_to, "/var/www/my_app_name"

# Default value for :format is :airbrussh.
# set :format, :airbrussh

# You can configure the Airbrussh format using :format_options.
# These are the defaults.
# set :format_options, command_output: true, log_file: "log/capistrano.log", color: :auto, truncate: :auto

# Default value for :pty is false
# set :pty, true

# Default value for :linked_files is []
append :linked_files, '.env'

# Default value for linked_dirs is []
append :linked_dirs, 'log', 'tmp/pids', 'tmp/cache'

# Default value for default_env is {}
# set :default_env, { path: "/opt/ruby/bin:$PATH" }

# Default value for local_user is ENV['USER']
# set :local_user, -> { `git config user.name`.chomp }

# Default value for keep_releases is 5
# set :keep_releases, 5

set :ssh_options, forward_agent: true

set :rbenv_type, :user
set :rbenv_ruby, IO.read('.ruby-version').strip
set :rbenv_prefix, "RBENV_ROOT=#{fetch(:rbenv_path)} RBENV_VERSION=#{fetch(:rbenv_ruby)} #{fetch(:rbenv_path)}/bin/rbenv exec"

after 'deploy:publishing', 'deploy:restart'
namespace :deploy do
  task :restart do
    on roles(:web) do |_host|
      execute "cd #{current_path} && RACK_ENV=#{fetch(:stage)} #{fetch(:rbenv_prefix)} bundle exec bin/app restart -p #{fetch(:port)} -h #{fetch(:host)}"
    end
  end
end
