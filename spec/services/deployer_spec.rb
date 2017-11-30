require 'spec_helper'

describe Deployer, type: :service do

  let(:params) { YAML.load_file(fixtures_path('deployer_params.yml'))[RACK_ENV].deep_symbolize_keys.merge(git: git_params) }
  let(:git_params) { { sha: 'ancd', branch: 'develop' } }
  subject { described_class.new(params) }
  it do
    subject.perform
  end
end
