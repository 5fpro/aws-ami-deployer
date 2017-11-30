class AwsClient
  def initialize(cmd_postfix: nil)
    @cmd_postfix = cmd_postfix
  end

  def terminate_instance(instance_id)
    aws_cmd("ec2 terminate-instances --instance-ids #{instance_id}")
  end

  def create_ami_tag(ami_id, key, value)
    aws_cmd("ec2 create-tags --resources #{ami_id} --tags Key=#{key},Value=#{value}")
  end

  def create_instance_tag(instance_id, key, value)
    aws_cmd("ec2 create-tags --resources #{instance_id} --tags Key=#{key},Value=#{value}")
  end

  def create_ami(instance_id, ami_name)
    aws_cmd("ec2 create-image --instance-id #{instance_id} --name #{ami_name} --no-reboot")['ImageId']
  end

  def create_instances(count: 1, ami_id:, security_group_id:, subnet_id:, instance_type:, availability_zone:, iam_role:)
    options = [
      '--monitoring Enabled=true',
      "--security-group-ids #{security_group_id}",
      "--instance-type #{instance_type}",
      '--enable-api-termination',
      "--subnet-id #{subnet_id}",
      '--associate-public-ip-address',
      "--iam-instance-profile Name=\"#{iam_role}\"",
      "--placement AvailabilityZone=#{availability_zone}",
      "--count #{count}"
    ]
    aws_cmd("ec2 run-instances --image-id #{ami_id} #{options.join(' ')}")['Instances'].map { |h| h['InstanceId'] }
  end

  def fetch_instance_tag_value(instance_id, tag_name)
    aws_cmd("ec2 describe-instances --instance-id #{instance_id}").values[0][0]['Instances'][0]['Tags'].select { |h| h['Key'] == tag_name }.first.try(:[], 'Value')
  end

  def fetch_elb_instance_ids(elb_name)
    aws_cmd("elb describe-instance-health --load-balancer-name #{elb_name}")['InstanceStates'].map { |i| i['InstanceId'] }
  end

  def fetch_ami_status(ami_id)
    aws_cmd("ec2 describe-images --image-ids #{ami_id}")['Images'][0]['State']
  end

  def fetch_instance_ip(instance_id)
    aws_cmd("ec2 describe-instances --instance-id #{instance_id}").values[0][0]['Instances'][0]['PublicIpAddress']
  end

  def fetch_instance_state(instance_id)
    aws_cmd("ec2 describe-instances --instance-id #{instance_id}").values[0][0]['Instances'][0]['State']['Name']
  end

  def add_instance_to_elb(elb_name, instance_id)
    aws_cmd("elb register-instances-with-load-balancer --load-balancer-name #{elb_name} --instances #{instance_id}")
  end

  def remove_instance_from_elb(elb_name, instance_id)
    aws_cmd("elb deregister-instances-from-load-balancer --load-balancer-name #{elb_name} --instances #{instance_id}")
  end

  def check_instance_health_of_elb(elb_name, instance_id)
    aws_cmd("elb describe-instance-health --load-balancer-name #{elb_name} --instances #{instance_id}")['InstanceStates'].first['State']
  end

  def assign_a_record(hosted_zone_id, domain_name, ip)
    tmp_json_file = File.join('', 'tmp', "#{ip}-#{domain_name}-#{Time.now.to_i}")
    IO.write(tmp_json_file, {
      Changes: [{ Action: 'UPSERT', ResourceRecordSet: { Name: domain_name, Type: 'A', TTL: 300, ResourceRecords: [{ Value: ip }] } }]
    }.to_json)
    aws_cmd("route53 change-resource-record-sets --hosted-zone-id #{hosted_zone_id} --change-batch file://#{tmp_json_file}")
    File.delete(tmp_json_file)
  end

  private

  def aws_cmd(body)
    res = `#{ENV['AWS_PATH']}aws #{body} #{@cmd_postfix}`
    res.present? ? JSON.parse(res) : res
  end
end
