#!/usr/bin/env ruby
require 'highline/import'
require 'colorize'
require 'trollop'
require 'yaml'
require 'json'

#Process ID
pid = Process.pid

#command line options
opts = Trollop::options do
  #Required parameters
  opt :datacenter, "Datacenter", :type => :string, :required => true
  opt :vcenter, "vCenter name", :type => :string, :required => true
  opt :vm_match_pattern, "Match pattern for VMs", :type => :string, :required => true
  opt :vc_user, "vCenter user", :type => :string, :required => true
  opt :engine_api, "Zombie engine api location, i.e d0p1tlm-zmb-eng-fe-a:8080", :type => :string, :required => true
  #Optional parameters defaults at zed actionset when left out.
  opt :vm_exclude_pattern, "Pattern for VMs to ignore", :type => :string, :required => false
  opt :command, "Command Executed by the ssh task to initial the puppet install", :type => :string, :required => false
  opt :cleanup_command, "Command to run for cleanup at completion.", :type => :string, :required => false
  opt :vm_username, "Username for connecting to specified VMs", :type => :string, :required => false
  opt :key_file, "Location of the ssh key", :type => :string, :required => false
  opt :scp_method, "Method for the scp tasks", :type => :string, :required => false
  opt :remote_path, "Remote path to place for scp files", :type => :string, :required => false
  opt :repo_file, "Location of the repo config file", :type => :string, :required => false
  opt :script_file, "Location of the isntall script", :type => :string, :required => false
  opt :suse_rpm, "Location of the suse rpm", :type => :string, :required => false
  opt :zor_log_level, "Log level for the zor command", :type => :string, :required => false, :default => 'debug'
  opt :log_level, "Logging level.", :type => :string, :default => 'info'
  opt :action_version, "Zed Action Version.", :type => :string, :default => '1.4'
end

#validate input
Trollop::die :datacenter, "must match dXpY" unless /^d\d{1,3}p\d{1,3}(oss)$/.match(opts[:datacenter]) if opts[:datacenter]
Trollop::die :vcenter, "must match dXpY" unless /d\d{1,}p\d{1,}(tlm-|oss-|v\d{1,})mgmt-vc\d{1,}/.match(opts[:vcenter]) if opts[:vcenter]
Trollop::die :log_level, "Invalid logging level.  Options are INFO (default), DEBUG, WARN, or FATAL" unless /(?i)(^INFO$)|(^DEBUG$)|(^WARN$)|(^FATAL$)/.match(opts[:log_level])
Trollop::die :zor_log_level, "Invalid logging level for zor.  Options are [d | debug], [i | info], [w | warn], [e | error], [f | fatal], [q | quiet] (default: info)" unless /(?i)(^INFO$)|(^i$)|(^DEBUG$)|(^d$)|(^WARN$)|(^w$)|(^f$)|(^ERROR$)|(^e$)|(^FATAL$)|(^f$)|(^QUIET$)|(^q$)/.match(opts[:log_level])

#Configure logging
script_name = 'puppet_install_zed'
if opts[:log_level].upcase == 'DEBUG'
  #Uses $logger gem and local log in uses home directory
  require 'logger'
  $logger = Logger.new(ENV["HOME"] + "/#{script_name}.log")
  $logger.progname = script_name
  $logger.formatter = proc do |severity, datetime, progname, msg|
    date_format = datetime.strftime("%b %e %k:%M:%S")
    "#{date_format} #{ENV['HOSTNAME']} #{progname}[#{pid}]: #{msg}\n"
  end
  $logger.level = Kernel.const_get 'Logger::' + opts[:log_level].upcase
  puts "[ " + "INFO".white + " ] Logging started search #{script_name}[#{pid}] in #{ENV['HOME']}/#{script_name}.log for logs."
else
  #Uses syslog gem and logs using syslog
  require 'syslog/logger'
  $logger = Syslog::Logger.new script_name
  $logger.level = Kernel.const_get 'Logger::' + opts[:log_level].upcase
  puts "[ " + "INFO".white + " ] Logging started search #{script_name}[#{pid}] in /var/log/messages for logs."
end

$logger.info "INFO  - Logging initalized."
puts "[ " + "INFO".white + " ] Logging started search #{script_name}[#{pid}] for logs."

#Set additional variables
$logger.info "INFO  - Getting password from user."
opts[:vc_password] = ask("Enter the vc_user password: ") { |q| q.echo="*"};
$logger.info "INFO  - Setting pluginlocation based on datacenter."
opts[:pluginlocation] = "pod" + opts[:datacenter].split('p')[1]

$logger.debug "DEBUG - opts: #{opts}"

yaml_file = ENV["HOME"] + "/install_puppet-#{pid}.yaml"
$logger.debug "DEBUG - yaml_file: #{yaml_file}"

#Cleanup hash contents for yaml file
opts.each { |k,v|
  #Remove keys with nil values
  if v.nil?
    opts.delete(k)
  end
  #Remove keys created by Trollop used
  #to indicate provided at command line
  if k =~ /given/
    opts.delete(k)
  end
}

$logger.info "INFO  - Creating #{yaml_file}"
file = File.new(yaml_file,  "w+")
#Build YAML file.
$logger.info "INFO  - Creating yaml file using values provided at runtime."
file.write(opts.to_yaml)
file.close

#exceute zor command
zor_cmd = "zor --engine-api=#{opts[:engine_api]} --log-level=#{opts[:zor_log_level]} engine-run -f #{yaml_file} -n install_puppet -v #{opts[:action_version]}"
$logger.debug "DEBUG - zor_cmd: #{zor_cmd}"
$logger.info "INFO  - Excecuting zor command to initiate zombie action in overwatch."
zor_rtn = %x{ #{zor_cmd} }
File.delete(yaml_file)
$logger.info "INFO  - Zor command exceution completed"
$logger.debug "DEBUG - zor command response: #{yaml_file}"
if (opts[:zor_log_level] =~ /(?i)(d|debug)/) != nil
  zor_response = JSON.parse("{\n" + (zor_rtn.scan(/(?m)\{\n(.+|\S+|\s+|\w+|\W+)\}\n\}/))[0][0] + "}\n}")
  $logger.debug "DEBUG - zor response: #{zor_response}"
  $logger.info "INFO  - Execution result: #{zor_response['response']['result']}"
  if zor_response['response']['result']['code'] != 202
    $logger.error "ERROR - Post failed: #{zor_response['response']['result']['code']} - #{zor_response['response']['result']['description']}"
    puts "[ " + "ERROR".red + " ] Post failed: #{zor_response['response']['result']['code']} - #{zor_response['response']['result']['description']}"
    exit
  end
  puts "[ " + "INFO".white + " ] Post Sucessful: #{zor_response['response']['result']['code']} - #{zor_response['response']['result']['description']}"
  puts "[ " + "INFO".white + " ] ZAI: #{zor_response['response']['entity']['id']}"
  $logger.debug "DEBUG - ZAI: #{zor_response['response']['entity']['id']}"
  puts "[ " + "INFO".white + " ] Check #{zor_response['response']['entity']['id']} on http://#{opts[:engine_api]} to monitor status"
end
