#!/usr/bin/env ruby
require 'highline/import'
require 'colorize'
require 'trollop'
require 'yaml'
require 'json'
require 'syslog/logger'
require 'net/ssh'
require 'vmware_secret_server'

#functions 
require_relative '/home/nholloway/scripts/Ruby/functions/password_functions.rb'

#procss ID
pid = Process.pid

#command line options
opts = Trollop::options do
  #Required parameters
  opt :action, "Action Set", :type => :string, :required => true
  opt :vrealms, "List of vRealm(s)", :type => :strings, :required => true
  opt :change_number, "Change Number", :type => :string, :require => true
  #Optional paremeters
  opt :esx_password, "ESXi Password", :type => :string, :required => false, :default => 'zombieownsall'
  opt :hyperic_password, "ESXi Password", :type => :string, :required => false, :default => 'm0n3yb0vin3'
  opt :target_vcd_version, "vCloud-Director Version", :type => :string, :required => false
  opt :target_vcd_build, "vCloud-Director Build", :type => :string, :required => false
  opt :zor_log_level, "Log level for the zor command", :type => :string, :required => false, :default => 'debug'
  opt :engine_api, "Zombie engine api location, i.e d0p1tlm-zmb-eng-fe-a:8080", :type => :string, :default => 'http://d0p1tlm-zmb-eng-fe-a:8080'
  opt :zedVersion, "Action Set Version", :type => :string, :default => '1.4.17'
  opt :certificate_warning_days, "How many days to check for expired SSL Certs", :type => :string
  opt :group_count, "How many hosts to perform at once", :type => :string, :required => false
  opt :precheck_only, "If true will only perform precheck. Actionset dependent", :type => :boolean, :required => false, :default => true
  opt :dedicated_vrealm, "Determines if vRealm is dedicated", :type => :boolean, :required => false, :default => true
  opt :snapshot_memory, "Whether to snapshot the memory", :type => :boolean, :required => false, :default => true
  opt :quiesce_filesystem, "Whether to quiesce the filesystem for the snapshot", :type => :boolean, :required => false, :default => true
end

#validate input
Trollop::die :action, "Action Set Name is incorrect" unless /(\w+_praxis_child|\w+_praxis_hosts|\w+_praxis_parent|\w+vrealm_hosts|\w+_vrealm_vcenter|upgrade_vrealm_vcd)/.match(opts[:action])
Trollop::die :target_vcd_version, "Must Match X.Y.Z" unless /^\d+[.]\d+[.]\d+$/.match(opts[:target_vcd_version]) if opts[:target_vcd_version]
Trollop::die :target_vcd_build, "Must Match 1234567" unless /^\d{7}$/.match(opts[:target_vcd_build]) if opts[:target_vcd_build]

#methods
def ssh_conn(vm, user, domain, adpass)
  access = 'false'
  count = 0
  puts "[ " + "INFO".green + " ] #{vm}: Attempting to connect via PMP Password with user #{user}"
  $logger.info "INFO - #{vm}: Attempting to connect via PMP Password"
  if user == 'administrator@vsphere.local'
    pass = 'vmware'
  else
    pass = get_password(adpass, "#{user}@#{vm}", domain)
  end

  while access == 'false'
    begin
      session = Net::SSH.start(vm, user, :password => pass, :auth_methods => ['password'], :number_of_password_prompts => 0)
      access = 'true'
      session.close
      puts '[ ' + 'INFO'.green + " ] #{vm}: Succesfully authenticated"
    rescue Net::SSH::AuthenticationFailed
      if (pass != 'm0n3yb0vin3') && (count == 0)
        puts '[ ' + 'WARN'.yellow + " ] Failed to authenictate with password #{pass}. Trying default password."
        pass = 'm0n3yb0vin3'
        count += 1
      else
        puts '[ ' + 'WARN'.yellow + " ] Failed to authenticate to #{vm} with password #{pass}."
        pass = ask("Please enter a new password for #{vm} and user #{user}") { |q| q.echo="*"}
        count += 1
      end
    end
  end
  return pass
end

def ssh_conn2(vm, user, pass)
  access = 'false'
  puts "[ " + "INFO".green + " ] Verifying AD Password"
  while access == 'false'
    begin
      session = Net::SSH.start(vm, user, :password => pass, :auth_methods => ['password'], :number_of_password_prompts => 0)
      access = 'true'
      puts '[ ' + 'INFO'.green + " ] AD Authentication successful"
      session.close
    rescue Net::SSH::AuthenticationFailed
        puts '[ ' + 'WARN'.yellow + " ] Failed to authenticate to #{vm} with password."
        pass = ask("Please enter your Ad Password") { |q| q.echo="*"}
    end
  end
  return pass
end

#Configure Logging
script_name = 'vSphere6_upg_kickoff'
$logger = Syslog::Logger.new script_name
$logger.level = Kernel.const_get 'Logger::INFO'
$logger.info "INFO  - Logging initalized."
puts "[ " + "INFO".green + " ] Logging started search #{script_name}[#{pid}] in /var/log/messages for logs."

#static variables
yaml_file = ENV["HOME"] + "/#{script_name}.#{pid}"

#environment variables
localVM = ENV['HOSTNAME']
domain = localVM.split('.')[1..-1].join('.')
numbers = localVM.scan(/\d+/)
pod_id = 'd' + numbers[0] + 'p' + numbers[1]
ss_url = "https://#{pod_id}oss-mgmt-secret-web0.#{domain}/SecretServer/webservices/SSWebservice.asmx?wsdl"

#user variables
ad_credentials = {}
snapshot_options = {}
opts[:ad_username] = `whoami`.chomp
opts[:ad_password] = get_adPass

#perform the following on each vRealm specified
opts[:vrealms].each { |vrealm|
  #Dyanamic Variables
  vc = vrealm + "mgmt-vc0"
  vrealm_numbers = vrealm.scan(/\d+/)
  opts[:target_datacenter] = vrealm_numbers[0]
  opts[:target_pod] = vrealm_numbers[1]
  opts[:target_vrealm] = vrealm_numbers[2]

  if opts[:action].downcase =~ /\w+_hosts/
    opts[:ipmi_password] = get_password(opts[:ad_password], 'ADMIN@ipmi-dXpXsXchXsrvX', domain.split(".")[0])
    opts[:vcenter_root_password] = ssh_conn(vc, 'root', domain.split(".")[0], opts[:ad_password])
  elsif opts[:action].downcase =~ /upgrade_vrealm_vcd/
    opts[:zedVersion] = '1.1.13'
    opts[:target_version] = opts[:target_vcd_version]
    opts[:target_build] = opts[:target_vcd_build]

    #build ad_credentials
    ad_credentials[:username] = opts[:ad_username]
    ad_credentials[:password] = opts[:ad_password]
    opts[:ad_credentials] = ad_credentials

    #build snapshot_options
    snapshot_options[:snapshot_name] = opts[:change_number] + "-pre-vcd-upgrade"
    snapshot_options[:snapshot_memory] = opts[:snapshot_memory]
    snapshot_options[:quiesce_filesystem] = opts[:quiesce_filesystem]
    opts[:snapshot_options] = snapshot_options

    #delete not used options
    opts.delete(:ad_username)
    opts.delete(:ad_password)
    opts.delete(:target_vcd_version)
    opts.delete(:target_vcd_build) 
    opts.delete(:change_number)
    opts.delete(:snapshot_memory)
    opts.delete(:quiesce_filesystem)
  else
    opts[:target_vcenter_root_password] = ssh_conn(vc, 'root', domain.split(".")[0], opts[:ad_password])
    opts[:target_vcenter_sso_password] = ssh_conn(vc, 'administrator@vsphere.local', domain.split(".")[0], opts[:ad_password])
    if opts[:action].downcase =~ /\w+_praxis_parent/
      sso = vrealm + "mgmt-sso-a"
      opts[:sso_root_password] = ssh_conn(sso, 'root', domain.split(".")[0], opts[:ad_password])
    end
    if opts[:action].downcase =~ /precheck_vrealm_vcenter/
      opts[:target_vcd_version] = '8.1.1'
      opts[:target_vcd_build] = '2962070'
    end
  end

  #clearing out opts of any nil values or given
  opts.each { |k,v|
    if v.nil?
      opts.delete(k)
    end
    if k =~ /given/
      opts.delete(k)
    end
  }

  #creating new array for yaml file
  newOpts = opts.clone
  if opts[:action] =~ /\w+_hosts/
    newOpts.each { |k,v|
      if (k =~ /action/) || (k =~ /vrealms/) || (k =~ /hyperic_password/) || (k =~ /zor_log_level/) || (k =~ /engine_api/) || (k =~ /hqPass/) || (k =~ /help/) || (k =~ /zedVersion/) || (k =~ /precheck_only/) || (k =~ /dedicated_vrealm/) || (k =~ /snapshot_memory/) || (k =~ /quiesce_filesystem/) || (k =~ /change_number/)
        newOpts.delete(k)
      end
    }
  elsif opts[:action] =~ /\w+_praxis_parent/
    newOpts.each { |k,v|
      if (k =~ /action/) || (k =~ /vrealms/) || (k =~ /esx_password/) || (k =~ /zor_log_level/) || (k =~ /engine_api/) || (k =~ /help/) || (k =~ /zedVersion/) || (k =~ /precheck_only/) || (k =~ /dedicated_vrealm/) || (k =~ /snapshot_memory/) || (k =~ /quiesce_filesystem/) || (k =~ /change_number/)
        newOpts.delete(k)
      end
    }
  elsif opts[:action] =~ /\w+_praxis_child/
    newOpts.each { |k,v|
      if (k =~ /action/) || (k =~ /vrealms/) || (k =~ /esx_password/) || (k =~ /zor_log_level/) || (k =~ /engine_api/) || (k =~ /help/) || (k =~ /zedVersion/) || (k =~ /precheck_only/) || (k =~ /dedicated_vrealm/) || (k =~ /snapshot_memory/) || (k =~ /quiesce_filesystem/) || (k =~ /change_number/)
        newOpts.delete(k)
      end
    }
  elsif opts[:action] =~ /\w+_vrealm_vcenter/
    newOpts.each { |k,v|
      if (k =~ /action/) || (k =~ /vrealms/) || (k =~ /esx_password/) || (k =~ /zor_log_level/) || (k =~ /engine_api/) || (k =~ /help/) || (k =~ /zedVersion/) || (k =~ /precheck_only/) || (k =~ /dedicated_vrealm/) || (k =~ /snapshot_memory/) || (k =~ /quiesce_filesystem/) || (k =~ /change_number/)
        newOpts.delete(k)
      end
    }
  elsif opts[:action] =~ /upgrade_vrealm_vcd/
    newOpts.each { |k,v|
      if (k =~ /action/) || (k =~ /vrealms/) || (k =~ /esx_password/) || (k =~ /zor_log_level/) || (k =~ /engine_api/) || (k =~ /help/) || (k =~ /zedVersion/) || (k =~ /hyperic/)
        newOpts.delete(k)
      end
    }
  else
    puts '[ ' + 'ERROR'.red + " ] Action set did not match any patterns"
    exit
  end


  #Create Yaml File for use
  puts '[ ' + 'INFO'.green + " ] Creating #{yaml_file}"
  $logger.info "INFO - Creating #{yaml_file}"
  file = File.new(yaml_file, "w+")
  file.write(newOpts.to_yaml)
  file.close

  #execute zor command
  zor_cmd = "/usr/local/bin/zor --engine-api=#{opts[:engine_api]} --log-level=#{opts[:zor_log_level]} engine-run -f #{yaml_file} -n #{opts[:action]} -v #{opts[:zedVersion]}"
  $logger.info "INFO  - Excecuting zor command to initiate zombie action in overwatch."
  zor_rtn = %x{ #{zor_cmd} }
  File.delete(yaml_file)
  $logger.info "INFO  - Zor command exceution completed"
  zor_response = JSON.parse("{\n" + (zor_rtn.scan(/(?m)\{\n(.+|\S+|\s+|\w+|\W+)\}\n\}/))[0][0] + "}\n}")
  if zor_response['response']['result']['code'] != 202
    $logger.error "ERROR - Post failed: #{zor_response['response']['result']['code']} - #{zor_response['response']['result']['description']}"
    puts "[ " + "ERROR".red + " ] Post failed: #{zor_response['response']['result']['code']} - #{zor_response['response']['result']['description']}"
  else
    puts "[ " + "INFO".green + " ] Post Sucessful: #{zor_response['response']['result']['code']} - #{zor_response['response']['result']['description']}"
    puts "[ " + "INFO".green + " ] ZAI: #{zor_response['response']['entity']['id']}"
    $logger.debug "DEBUG - ZAI: #{zor_response['response']['entity']['id']}"
    puts "[ " + "INFO".green + " ] Check #{zor_response['response']['entity']['id']} on http://#{opts[:engine_api]} to monitor status"
  end
}
