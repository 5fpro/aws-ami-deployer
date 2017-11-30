set :rack_env, 'staging'

set :deploy_to, '/home/apps/aws-ami-deployer'
set :port, '8080'
set :host, '0.0.0.0'

server = 'apps@example.com'

role :app,                server
role :web,                server
