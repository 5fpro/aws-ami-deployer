module ObjectMocks
  def mock_aws_client!
    allow_any_instance_of(AwsClient).to receive(:terminate_instance).and_return(
      nil
    )
    allow_any_instance_of(AwsClient).to receive(:create_ami_tag).and_return(
      nil
    )
    allow_any_instance_of(AwsClient).to receive(:create_instance_tag).and_return(
      nil
    )
    allow_any_instance_of(AwsClient).to receive(:create_ami).and_return(
      'ami-abcdefg'
    )
    allow_any_instance_of(AwsClient).to receive(:create_instances).and_return(
      ['ins-1', 'ins-2']
    )
    allow_any_instance_of(AwsClient).to receive(:fetch_elb_instance_ids).and_return(
      ['ins-3', 'ins-4']
    )
    allow_any_instance_of(AwsClient).to receive(:fetch_ami_status).and_return(
      'available'
    )
    allow_any_instance_of(AwsClient).to receive(:fetch_instance_ip).and_return(
      '128.0.0.1'
    )
    allow_any_instance_of(AwsClient).to receive(:fetch_instance_state).and_return(
      'running'
    )
    allow_any_instance_of(AwsClient).to receive(:add_instance_to_elb).and_return(
      nil
    )
    allow_any_instance_of(AwsClient).to receive(:remove_instance_from_elb).and_return(
      nil
    )
    allow_any_instance_of(AwsClient).to receive(:check_instance_health_of_elb).and_return(
      'InService'
    )
    allow_any_instance_of(AwsClient).to receive(:assign_a_record).and_return(
      nil
    )
  end

  def mock_cmd!
    mock_reader = double(gets: nil)
    allow(IO).to receive(:popen).and_yield(mock_reader)
  end
end
