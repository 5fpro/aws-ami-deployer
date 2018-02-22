class Deployer
  # Eaxmple:
  #   {
  #     count: 1,
  #     name: 'doodle-web',
  #     source_instance_id: 'i-08643369d25e61025',
  #     elb_name: 'livetest-5fpro-com',
  #     elbv2: {
  #       target_group_arns: ['xxxx', 'ooooo']
  #     }
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
  def initialize(count:, name:, source_instance_id:, launch_options:, health_check_rule:, default_tags:, elb_name: nil, elbv2: nil, git:, awscli_postfix: '', log_id: nil, post_create_scripts: {})
    @count = count
    @name = name
    @source_instance_id = source_instance_id
    @launch_options = launch_options.symbolize_keys
    @health_check_rule = health_check_rule
    @git = git
    @elb_name = elb_name
    @elbv2 = (elbv2 || {}).symbolize_keys
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
      return 'instance not health' unless check_instance_health(@source_instance_id)

      ami_id = create_ami_until_available(@source_instance_id, ami_name)
      instance_ids = create_instances_until_available(ami_id, @count)
      exists_instance_ids = get_exist_instance_ids
      log exists_instance_ids.inspect
      add_instances_to_elb_until_available(instance_ids)
      remove_and_terminate_exists_instances_from_elb(exists_instance_ids)
    rescue => e
      log "Fail! #{e.class}: #{e.message}"
      log e.backtrace.inspect
      return finished_processing(e)
    end
    finished_processing(true)
    @log_id
  end

  private

  def elbv2?
    @elbv2[:target_group_arns].present?
  end

  def target_group_arns
    @target_group_arns ||= @elbv2[:target_group_arns]
  end

  def get_exist_instance_ids
    if elbv2?
      aws_client.fetch_elbv2_instance_ids(target_group_arns)
    else
      aws_client.fetch_elb_instance_ids(@elb_name)
    end
  end

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
    @ami_id = aws_client.create_ami(instance_id, ami_name)
    log "ami: #{@ami_id}"
    aws_client.create_ami_tag(@ami_id, 'Branch', @git[:branch])
    aws_client.create_ami_tag(@ami_id, 'SHA', @git[:sha])
    aws_client.create_ami_tag(@ami_id, 'AMIDeploy', @name)
    status = nil
    while status != 'available'
      status = aws_client.fetch_ami_status(@ami_id)
      log "AMI status: #{status}"
      wait(20) if status != 'available'
    end
    @ami_id
  end

  def generate_instances(instance_ids)
    @instances = instance_ids.each_with_index.map do |instance_id, index|
      Instance.new(id: instance_id, name: "#{@name}-#{index + 1}", index: index)
    end
  end

  def create_instances_until_available(ami_id, count)
    instance_ids = create_instances(ami_id, count)
    instances = generate_instances(instance_ids)
    log "created instances: #{instances.map(&:id).inspect}"
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
        log "#{instance.id}(#{instance.name}) => status: #{state}, health: #{health}"
        runed_instance_ids << instance.id if runed && health
      end
      wait(20) unless (instance_ids - runed_instance_ids).empty?
    end
    instances.each do |instance|
      run_post_create_scripts(instance)
    end
    instance_ids
  end

  def add_instance_to_elb(instance_id)
    if elbv2?
      aws_client.add_instance_to_elbv2(target_group_arns, instance_id)
    else
      aws_client.add_instance_to_elb(@elb_name, instance_id)
    end
  end

  def instance_health_in_elb?(instance_id)
    if elbv2?
      arns_state = aws_client.check_instance_health_of_elbv2(target_group_arns, instance_id)
      arns_state.each { |arn, state| log "#{instance_id}'s state in #{arn}: #{state}" }
      arns_state.values.uniq == ['healthy']
    else
      state = aws_client.check_instance_health_of_elb(@elb_name, instance_id)
      log "#{instance_id} of ELB: #{state}"
      state == 'InService'
    end
  end

  def add_instances_to_elb_until_available(instance_ids)
    instance_ids.each { |instance_id| add_instance_to_elb(instance_id) }
    healthed_instance_ids = []
    until instance_ids.empty?
      instance_ids.each do |instance_id|
        healthed_instance_ids << instance_id if instance_health_in_elb?(instance_id)
      end
      healthed_instance_ids.each { |id| instance_ids.delete(id) }
      wait(5)
    end
    healthed_instance_ids
  end

  def remove_instance_from_elb(instance_id)
    if elbv2?
      aws_client.remove_instance_from_elbv2(target_group_arns, instance_id)
    else
      aws_client.remove_instance_from_elb(@elb_name, instance_id)
    end
  end

  def remove_and_terminate_exists_instances_from_elb(instance_ids)
    log 'removing instances from ELB'
    instance_ids.each do |instance_id|
      if instance_id == @source_instance_id
        log "#{instance_id} is source instance, skip remove"
      else
        remove_instance_from_elb(instance_id)
        log "removed instance #{instance_id} from ELB"
      end
    end
    log 'waiting 300 seconds to terminate old instances'
    wait(300)
    log 'Terminating instances from ELB'
    instance_ids.each do |instance_id|
      if instance_id == @source_instance_id
        log "#{instance_id} is source instance, skip terminate"
      else
        aws_client.terminate_instance(instance_id)
        log "terminated instance #{instance_id}"
      end
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
        # change encoding so we can display UTF-8 text
        output.force_encoding('UTF-8')
        # remove color code for logging
        begin
          log ">> #{output.gsub(/\e\[.*?m/, '')}"
        rescue
          # if some how we still cannot process the log, just ignore it
          log '>> (Unknown output format)'
        end
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
    log "assign A record #{domain_name} with #{ip} to #{instance.id}(#{instance.name})"
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
    App.env.test? ? sleep(0) : sleep(seconds)
  end

  def finished_processing(exception)
    return log('Success!') unless exception.is_a?(Exception)
    if @ami_id.present?
      log "Fail: Deregister AMI-#{@ami_id}"
      aws_client.destroy_ami(@ami_id)
    end
    @instances&.each do |instance|
      log "Fail: Terminating instance #{instance.id}(#{instance.name})"
      aws_client.terminate_instance(instance.id)
    end
    log 'Fail!'
    raise exception if App.env.test?
  end
end
