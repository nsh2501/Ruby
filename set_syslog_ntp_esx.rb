#!/usr/bin/env ruby
#This script will audit/set syslog and NTP on each host in a given vcenter/pod

require 'trollop'

require_relative '/home/nholloway/scripts/Ruby/functions/format.rb'
require_relative '/home/nholloway/scripts/Ruby/functions/password_functions.rb'
require_relative '/home/nholloway/scripts/Ruby/functions/rbvmomi_methods.rb'
require_relative '/home/nholloway/scripts/Ruby/functions/vcenter_list_v2.rb'

opts = Trollop::options do
  opt :vcenters, "vCenters you would like to configure syslog/ntp for ESXi hosts", :type => :strings, :required => false
  opt :pods, "List of pods you would like to run this script against. If left blank it will default to all pods. Example d0p1 d0p2", :type => :strings, :required => false
  opt :log_level, "Logging Level", :type => :string, :require => false, :default => 'INFO'
  opt :verify_only, "Use this option to run an audit only", :type => :boolean, :required => false, :default => false
  opt :num_workers, "Set the number of threads to use.", :type => :int, :required =>false, :default => 5
end

Trollop::die "You can only specify one of vcenters, pods, or all-pods" if (!opts[:vcenters].nil?) && (!opts[:pods].nil?)
Trollop::die :log_level, "Invalid logging level. Options are INFO, DEBUG, or WARN" unless /(?i)(^INFO$)|(^DEBUG$)|(^WARN$)/.match(opts[:log_level])
Trollop::die :pods, "Pods format must be in dXpY format" unless (opts[:pods].find { |x| !x.match(/^d\d{1,3}p\d{1,3}$/) }).nil?
Trollop::die :vcenters, "vCenters must be in format dXpYvZmgmt-vc0 dXpYvZmgmt-vc0" unless (opts[:vcenters].find { |x| \
  !x.match(/^d\d{1,3}p\d{1,3}v\d{1,3}mgmt-vc0$/)}).nil?

#Process ID
pid = Process.pid

#set log level to all upper case
opts[:log_level].upcase!

#configure logging
script_name = 'set_syslog_ntp_esx.rb'
if opts[:log_level] == 'DEBUG'
  require 'logger'
  log_file = ENV['HOME'] + "/#{script_name}.log"
  logger = Logger.new(log_file)
  logger.progname = script_name
  logger.formatter = proc do |severity, datetime, progname, msg|
    date_format = datetime.strftime("%b %e %k:%M:%S")
    "#{date_format} #{ENV['HOSTNAME']} #{progname}[#{pid}]: #{msg}\n"
  end
  logger.level = Kernele.const_get 'Logger::' + opts[:log_level]
  logger.info "INFO - Logging Initalized"
  puts '[ ' + 'INFO'.white + " ] Logging started, search #{script_name}[#{pid}] in #{log_file} for logs"
else
  require 'syslog/logger'
  logger = Syslog::Logger.new script_name
  logger.level = Kernel.const_get 'Logger::INFO'
  logger.info "INFO - Logging Initalized"
  puts '[ ' + 'INFO'.white + " ] Loggin started, search #{script_name}[#{pid}] in /var/log/messages for logs"
end


#variables
ad_user = 'AD\\' + `whoami`.chomp
ad_pass = get_adPass
@incorrect_syslog = {}
host_prop = %w(name parent runtime.connectionState config.option)

#logging script options if debug is enabled
logger.debug "DEBUG - opts: #{opts}"
logger.debug "DEBUG - ad_user: #{ad_user}"

#get list of vcenters if list was not specified
clear_line 
logger.info "INFO - Gathering list of vCenters"
print '[ ' + 'INFO'.white + " ] Gathering list of vCenters"
if opts[:vcenters].nil?
  vcenters = f_get_vcenter_list(logger, pod: opts[:pods], ad_user: ad_user, ad_pass: ad_pass)
else
  vcenters = opts[:vcenters]
end

#build the threads/commands to run so they can be run in a serial fashion
threads = opts[:num_workers].map do
  Thread.new do
    until (vcenter = queue.pop) == :END
      #logging
      logger.info "INFO - Logging into #{vcenter}"
      clear_line
      print '[ ' + 'INFO'.white + " ] Logging into #{vcenter}"

      #calculate ip and then get syslog info
      pod_subnet = vcenter.scan(/\d+/)[1].to_i * 2
      pod_syslog = "tcp://10.#{pod_subnet}.28.13"

      #Connect to vCenter and get list of hosts
      vim = connect_viserver(vcenter, ad_user, ad_pass)
      dc = vim.serviceInstance.find_datacenter

      #get list of connected hosts
      connected_hosts = get_connected_hosts (vim, dc, host_prop)

      if opts[:verify_only]
      #get list of hosts that have incorrect syslog
      connected_hosts.reject { |vmhost| vmhost.propSet.find { |prop| prop.name == 'config.option' }.val.find { |syslog| syslog.key == 'Syslog.global.logHost' && syslog.value == "#{pod_syslog}" } }
    end
  end
end











