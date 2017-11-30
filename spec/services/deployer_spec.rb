require 'spec_helper'

describe Deployer, type: :service do

  let(:params) { YAML.load_file(fixtures_path('deployer_params.yml'))[RACK_ENV].deep_symbolize_keys.merge(git: git_params) }
  let(:git_params) { { sha: 'ancd', branch: 'develop' } }
  subject { described_class.new(params) }
  it do
    expect(subject).to receive(:finished_processing).with(true)
    subject.perform
  end

  context 'Fail' do
    before { allow(subject).to receive(:remove_and_terminate_exists_instances_from_elb).and_raise('Fail') }

    it 'finished_processing with exception' do
      expect(subject).not_to receive(:finished_processing).with(true)
      subject.perform
    end
    it 'destroy_ami' do
      expect_any_instance_of(AwsClient).to receive(:destroy_ami)
      expect {
        subject.perform
      }.to raise_error
    end

    it 'terminate_instance' do
      expect_any_instance_of(AwsClient).to receive(:terminate_instance).with(created_instance_ids.first)
      expect {
        subject.perform
      }.to raise_error
    end
  end
end
