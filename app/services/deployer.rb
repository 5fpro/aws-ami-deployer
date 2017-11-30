class Deployer
  # Eaxmple:
  #   {
  #     count: 1,
  #     name: 'doodle-web',
  #     source_instance_id: 'i-08643369d25e61025',
  #     elb_name: 'livetest-5fpro-com',
  #     launch_options: {
  #       security_group_id: 'sg-622e0f05',
  #       instance_type: 't2.small',
  #       subnet_id: 'subnet-541d2530',
  #       iam_role: 'ec2',
  #       availability_zone: 'ap-southeast-1a'
  #     },
  #     post_create_scripts: {
  #       ssh_user: "ubuntu", # default to current user
  #       ssh_command: "ssh", # default to 'ssh'
  #       ssh_port: 22, # default to '22'
  #       commands: ['echo hello > /tmp/hello.txt'],
  #       local_files: ['/path/to/local/script.sh'],
  #       remote_files: ['/path/to/script.sh', '/another/script.sh'],
  #       route53_a_records: {
  #         hosted_zone_id: 'xxxxx',
  #         domain_name_pattern: 'web-<INDEX>.example.com'
  #       }
  #     }
  #     health_check_rule: {
  #       port: 88,
  #       protocol: 'http',
  #       method: 'get',
  #       path: '/ping',
  #       status: 200,
  #       body_match: 'ok',
  #       count: 3
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
  def initialize(count:, name:, source_instance_id:, launch_options:, health_check_rule:, default_tags:, elb_name:, git:, awscli_postfix: '', log_id: nil, post_create_scripts: {})
    @count = count
    @name = name
    @instance = source_instance_id
    @launch_options = launch_options.symbolize_keys
    @health_check_rule = health_check_rule
    @git = git
    @elb_name = elb_name
    @default_tags = default_tags || {}
    @awscli_postfix = awscli_postfix
    @log_id = log_id || Time.now.to_f
    @log_file = File.join(App.root, 'log', "deploy-#{@log_id}.log")
    @post_create_scripts = post_create_scripts
    Thread.current[:log] = []
  end

  def perform
    log "Parameters: #{params.inspect}"
    begin
      ami_name = "#{@name}-web-#{Time.now.strftime('%Y%m%d%H%M')}"
      return 'instance not health' unless check_instance_health(@instance)

      ami_id = create_ami_until_available(@instance, ami_name)
      instance_ids = create_instances_until_available(ami_id, @count)
      exists_instance_ids = aws_client.fetch_elb_instance_ids(@elb_name)
      log exists_instance_ids.inspect
      add_instances_to_elb_until_available(@elb_name, instance_ids)
      remove_and_terminate_exists_instances_from_elb(@elb_name, exists_instance_ids)
      finished_processing(true)
    rescue => e
      log "Fail! #{e.class}: #{e.message}"
      log e.backtrace.inspect
      finished_processing(false)
      raise e if App.env.test?
    end
    @log_id
  end

  private

  def params
    @params ||= {
      log_id: @log_id,
      log_file: @log_file,
      count: @count,
      name: @name,
      source_instance_id: @source_instance_id,
      launch_options: @launch_options,
      health_check_rule: @health_check_rule,
      default_tags: @default_tags,
      elb_name: @elb_name,
      git: @git,
      awscli_postfix: @awscli_postfix,
      post_create_scripts: @post_create_scripts
    }
  end

  def check_instance_health(instance)
    health = false
    until health
      log "checking health of #{instance}"
      health = health?(instance)
      log health.inspect
      wait(5)
    end
    health
  end

  def create_ami_until_available(instance_id, ami_name)
    ami_id = aws_client.create_ami(instance_id, ami_name)
    log "ami: #{ami_id}"
    aws_client.create_ami_tag(ami_id, 'Branch', @git[:branch])
    aws_client.create_ami_tag(ami_id, 'SHA', @git[:sha])
    aws_client.create_ami_tag(ami_id, 'AMIDeploy', @name)
    status = nil
    while status != 'available'
      status = aws_client.fetch_ami_status(ami_id)
      log "AMI status: #{status}"
      wait(20) if status != 'available'
    end
    ami_id
  end

  def generate_instances(instance_ids)
    @instances = instance_ids.each_with_index.map do |instance_id, index|
      Instance.new(id: instance_id, name: "#{@name}-#{index + 1}", index: index)
    end
  end

  def create_instances_until_available(ami_id, count)
    instance_ids = create_instances(ami_id, count)
    instances = generate_instances(instance_ids)
    log "created instances: #{instances.inspect}"
    instances.each do |instance|
      @default_tags.each { |key, value| aws_client.create_instance_tag(instance.id, key, value) }
      aws_client.create_instance_tag(instance.id, 'Name', instance.name)
      aws_client.create_instance_tag(instance.id, 'AMIDeploy', @name)
    end
    runed_instance_ids = []
    until (instance_ids - runed_instance_ids).empty?
      instances.each do |instance|
        next if runed_instance_ids.include?(instance.id)
        state = aws_client.fetch_instance_state(instance.id)
        runed = state == 'running'
        health = runed ? health?(instance.id) : false
        log "#{instance} => status: #{state}, health: #{health}"
        runed_instance_ids << instance.id if runed && health
      end
      wait(20) unless (instance_ids - runed_instance_ids).empty?
    end
    # why we need read instance's name from map is because their names are not in order
    instances.each do |instance|
      run_post_create_scripts(instance)
    end
    instance_ids
  end

  def add_instances_to_elb_until_available(elb_name, instances)
    instances.each { |instance_id| aws_client.add_instance_to_elb(elb_name, instance_id) }
    healthed_instances = []
    until instances.empty?
      instances.each do |instance_id|
        state = aws_client.check_instance_health_of_elb(elb_name, instance_id)
        log "#{instance_id} of ELB: #{state}"
        healthed_instances << instance_id if state == 'InService'
      end
      healthed_instances.each { |i| instances.delete(i) }
      wait(5)
    end
    healthed_instances
  end

  def remove_and_terminate_exists_instances_from_elb(elb_name, instances)
    instances.each do |instance_id|
      aws_client.remove_instance_from_elb(elb_name, instance_id)
      aws_client.terminate_instance(instance_id)
    end
  end

  def health?(instance_id)
    @instances_health ||= {}
    @instances_health[instance_id] ||= 0
    checker = @health_check_rule
    checker[:protocol] ||= 'http'
    checker[:status] ||= 200
    checker[:port] ||= 80
    checker[:method] ||= 'get'
    checker[:count] ||= 3
    ip = aws_client.fetch_instance_ip(instance_id)
    res = false
    if ip
      begin
        response = Faraday.new(url: "#{checker[:protocol]}://#{ip}:#{checker[:port]}#{checker[:path]}").public_send(checker[:method].to_s.downcase) do |req|
          req.url checker[:path]
        end
        res = (response.status == checker[:status].to_i && response.body.index(checker[:body_match]) >= 0)
      rescue => e
        log "instance #{instance_id} is not health: #{e.message}"
        raise e if App.env.test?
      end
    end
    if res
      @instances_health[instance_id] += 1
      log "instance #{instance_id} is health (#{@instances_health[instance_id]}/#{checker[:count]})"
      @instances_health[instance_id] >= checker[:count].to_i
    else
      @instances_health[instance_id] = 0
      res
    end
  end

  def create_instances(ami_id, count)
    aws_client.create_instances(
      ami_id: ami_id,
      count: count,
      security_group_id: @launch_options[:security_group_id],
      instance_type: @launch_options[:instance_type],
      subnet_id: @launch_options[:subnet_id],
      iam_role: @launch_options[:iam_role],
      availability_zone: @launch_options[:availability_zone]
    )
  end

  def run_command_with_log(cmd)
    IO.popen(cmd) do |result|
      while output = result.gets
        # remove color code for logging
        log ">> #{output.gsub(/\e\[.*?m/, '')}"
      end
    end
  end

  def render_cmd_template(cmd, opts = {})
    opts.each do |find, replace|
      cmd = cmd.gsub(/<#{find.to_s.upcase}>/, replace.to_s)
    end
    cmd
  end

  def pack_remote_command(cmd)
    time = Time.now.to_f
    result = "<<'__ENDOFCOMMAND_#{time}__' \n"
    result << cmd
    result << "\n"
    result << "__ENDOFCOMMAND_#{time}__"
    result
  end

  def run_post_create_scripts(instance)
    ip = aws_client.fetch_instance_ip(instance.id)
    # We do not check the host key since it will be changed by AWS
    ssh_command = @post_create_scripts[:ssh_command] || 'ssh -o StrictHostKeyChecking=no'
    ssh_user = @post_create_scripts[:ssh_user].nil? ? '' : "#{@post_create_scripts[:ssh_user]}@"
    command_prefix = "#{ssh_command} #{ssh_user}#{ip}"
    # commands
    @post_create_scripts[:commands]&.each do |remote_raw_command|
      remote_command = render_cmd_template(remote_raw_command, instance_name: instance.name)
      log "running command: #{remote_command}"
      cmd = "#{command_prefix} #{pack_remote_command(remote_command)}"
      run_command_with_log(cmd)
    end
    # local scripts
    @post_create_scripts[:local_files]&.each do |filename|
      log "running local script: #{filename}"
      cmd = "#{command_prefix} #{pack_remote_command(File.read(filename))}"
      run_command_with_log(cmd)
    end
    # remote scripts
    @post_create_scripts[:remote_files]&.each do |filename|
      log "running remote script: #{filename}"
      cmd = "#{command_prefix} #{pack_remote_command("sh #{filename}")}"
      run_command_with_log(cmd)
    end
    # assign route53 a record
    domain_name_pattern = @post_create_scripts[:route53_a_records]&.dig(:domain_name_pattern)
    domain_name = render_cmd_template(domain_name_pattern, instance_id: instance.id, instance_name: instance.name, index: instance.index + 1)
    hosted_zone_id = @post_create_scripts[:route53_a_records]&.dig(:hosted_zone_id)
    aws_client.assign_a_record(hosted_zone_id, domain_name, ip)
  end

  def log(msg)
    logger.info msg
    STDOUT.puts msg
  end

  def logger
    @logger ||= Logger.new(@log_file)
  end

  def aws_client
    @aws_client ||= AwsClient.new(cmd_postfix: @awscli_postfix)
  end

  def wait(seconds)
    App.env.test? ? sleep(1) : sleep(seconds)
  end

  def finished_processing(success = true)
    log "Finished!(#{success ? 'success' : 'fail'})"
  end
end
