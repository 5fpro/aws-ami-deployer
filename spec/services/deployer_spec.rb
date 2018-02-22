require 'spec_helper'

describe Deployer, type: :service do

  let(:param_file_name) { 'deployer_params.yml' }
  let(:params) { YAML.load_file(fixtures_path(param_file_name))[RACK_ENV].deep_symbolize_keys.merge(git: git_params) }
  let(:git_params) { { sha: 'ancd', branch: 'develop' } }
  subject { described_class.new(params) }

  context 'Success' do
    it 'elbv1' do
      expect(subject).to receive(:finished_processing).with(true)
      subject.perform
    end

    context 'elbv2' do
      let(:param_file_name) { 'deployer_params_elbv2.yml' }
      it do
        expect(subject).to receive(:finished_processing).with(true)
        subject.perform
      end
    end
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
      }.to raise_error(RuntimeError)
    end

    it 'terminate_instance' do
      expect_any_instance_of(AwsClient).to receive(:terminate_instance).with(created_instance_ids.first)
      expect {
        subject.perform
      }.to raise_error(RuntimeError)
    end
  end
end
