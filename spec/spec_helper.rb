ENV['RACK_ENV'] ||= 'test'
require File.expand_path(File.join(File.dirname(__FILE__), '..', 'config', 'boot'))

Dir[File.join(App.root, 'spec', 'support', '**', '*')].each { |f| require f }

RSpec.configure do |config|

  config.include ObjectMocks
  config.include WebMocks
  config.include CommonHelper

  config.before { mock_aws_client! }
  config.before { mock_cmd! }
  config.before { mock_requests! }
  config.after(:suite) { `rm -f #{App.root}/log/deploy*.log` }

  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.shared_context_metadata_behavior = :apply_to_host_groups

end

Dir[File.join(App.root, 'spec', 'config', '**', '*.rb')].each { |f| require f }
