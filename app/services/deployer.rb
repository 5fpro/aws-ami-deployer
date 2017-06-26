class Deployer
  # Eaxmple:
  #   {
  #     count: 1,
  #     name: 'doodle-web',
  #     source_instance_id: 'i-08643369d25e61025',
  #     elb_name: 'livetest-5fpro-com',
  #     lunch_options: {
  #       security_group_id: 'sg-622e0f05',
  #       instance_type: 't2.small',
  #       subnet_id: 'subnet-541d2530',
  #       iam_role: 'ec2',
  #       availability_zone: 'ap-southeast-1a'
  #     },
  #     health_check_rule: {
  #       port: 88,
  #       protocol: 'http',
  #       method: 'get',
  #       path: '/ping',
  #       status: 200,
  #       body_match: 'ok'
  #     },
  #     git: {
  #       sha: '1231231',
  #       branch: 'develop'
  #     },
  #     default_tags: {
  #       Env: 'production',
  #       Version: 'doodle'
  #     },
  #     awscli_postfix: '--profile shopmatic'
  #   }
  def initialize(count:, name:, source_instance_id:, lunch_options:, health_check_rule:, default_tags:, elb_name:, git:, awscli_postfix: '')
    @count = count
    @name = name
    @instance = source_instance_id
    @lunch_options = lunch_options.symbolize_keys
    @health_check_rule = health_check_rule
    @git = git
    @elb_name = elb_name
    @default_tags = default_tags || {}
    @awscli_postfix = awscli_postfix
  end

  def perform
    ami_name = "#{@name}-web-#{Time.now.strftime('%Y%m%d%H%M')}"
    return 'instance not health' unless health?(@instance)

    ami_id = create_ami_until_available(@instance, ami_name)
    instances = create_instances_until_available(ami_id, @count)
    exists_instances = fetch_elb_instance_ids(@elb_name)
    log exists_instances.inspect
    add_instances_to_elb_until_available(@elb_name, instances)
    remove_and_terminate_exists_instances_from_elb(@elb_name, exists_instances)
  end

  private

  def create_ami_until_available(instance_id, ami_name)
    ami_id = create_ami(instance_id, ami_name)
    log "ami: #{ami_id}"
    create_ami_tag(ami_id, 'Branch', @git[:branch])
    create_ami_tag(ami_id, 'SHA', @git[:sha])
    create_ami_tag(ami_id, 'Deploy', @name)
    status = nil
    while status != 'available'
      status = fetch_ami_status(ami_id)
      log "AMI status: #{status}"
      sleep(20) if status != 'available'
    end
    ami_id
  end

  def create_instances_until_available(ami_id, count)
    instances = create_instances(ami_id, count)
    log instances.inspect
    instances.each_with_index do |instance, index|
      @default_tags.each { |key, value| create_instance_tags(instance, key, value) }
      create_instance_tags(instance, 'Name', "#{@name}-#{index + 1}")
    end
    ok_instances = []
    until instances.empty?
      instances.each do |instance|
        state = fetch_instance_state(instance)
        runed = state == 'running'
        health = runed ? health?(instance) : false
        log "#{instance}: #{state}, #{health}"
        ok_instances << instance if runed && health
      end
      ok_instances.each { |i| instances.delete(i) }
      sleep(20) unless instances.empty?
    end
    ok_instances
  end

  def add_instances_to_elb_until_available(elb_name, instances)
    instances.each { |instance_id| add_instance_to_elb(elb_name, instance_id) }
    healthed_instances = []
    until instances.empty?
      instances.each do |instance_id|
        state = check_instance_health_of_elb(elb_name, instance_id)
        log "#{instance_id} of ELB: #{state}"
        healthed_instances << instance_id if state == 'InService'
      end
      healthed_instances.each { |i| instances.delete(i) }
      sleep(5)
    end
    healthed_instances
  end

  def remove_and_terminate_exists_instances_from_elb(elb_name, instances)
    instances.each do |instance_id|
      remove_instance_from_elb(elb_name, instance_id)
      terminate_instance(instance_id)
    end
  end

  def health?(instance_id)
    checker = @health_check_rule
    checker[:protocol] ||= 'http'
    checker[:status] ||= 200
    checker[:port] ||= 80
    checker[:method] ||= 'get'
    ip = fetch_instance_ip(instance_id)
    res = false
    if ip
      begin
        response = Faraday.new(url: "#{checker[:protocol]}://#{ip}:#{checker[:port]}#{checker[:path]}").public_send(checker[:method].to_s.downcase) do |req|
          req.url checker[:path]
        end
        res = (response.status == checker[:status].to_i && response.body.index(checker[:body_match]) >= 0)
      rescue => e
        log e.message
      end
    end
    res
  end

  def terminate_instance(instance_id)
    aws_cmd("ec2 terminate-instances --instance-ids #{instance_id}")
  end

  def create_ami_tag(ami_id, key, value)
    aws_cmd("ec2 create-tags --resources #{ami_id} --tags Key=#{key},Value=#{value}")
  end

  def create_instance_tags(instance_id, key, value)
    aws_cmd("ec2 create-tags --resources #{instance_id} --tags Key=#{key},Value=#{value}")
  end

  def create_ami(instance_id, ami_name)
    aws_cmd("ec2 create-image --instance-id #{instance_id} --name #{ami_name} --no-reboot")['ImageId']
  end

  def create_instances(ami_id, count)
    options = [
      '--monitoring Enabled=true',
      "--security-group-ids #{@lunch_options[:security_group_id]}",
      "--instance-type #{@lunch_options[:instance_type]}",
      '--enable-api-termination',
      "--subnet-id #{@lunch_options[:subnet_id]}",
      '--associate-public-ip-address',
      "--iam-instance-profile Name=\"#{@lunch_options[:iam_role]}\"",
      "--placement AvailabilityZone=#{@lunch_options[:availability_zone]}",
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

  def aws_cmd(body)
    res = `aws #{body} #{@awscli_postfix}`
    res.present? ? JSON.parse(res) : res
  end

  def log(msg)
    Thread.current[:stdout] = msg
  end
end
