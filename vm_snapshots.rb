#!/usr/bin/env ruby
require 'rbvmomi'
require 'highline/import'
require 'yaml'
require 'colorize'
require 'trollop'

#Process ID
pid = Process.pid

#command line options
opts = Trollop::options do
  opt :yaml, "Path to YAML file.", :type => :string, :required => true
  opt :user, "AD username.", :type => :string
  opt :pod, "Target pod (dXpY).  Overrides value in YAML file.", :type => :string
  opt :log_level, "Logging level.", :type => :string, :default => 'info'
  opt :snapshot_name, "Snapshot name.", :type => :string, :short => 'n'
  opt :snapshot_memory, "Snapshot memory.", :type => :string, :short => 'm'
  opt :quiesce, "$quiesce filesystem.", :type => :flag, :short => 'q', :default => false
  opt :vpc, "Managment vCenter. tlm|oss", :type => :string, :default => 'tlm'
end

#validate input
Trollop::die :yaml, "must exist" unless File.exist?(opts[:yaml]) if opts[:yaml]
Trollop::die :pod , "must match dXpY" unless /^d\d{1,3}p\d{1,3}$/.match(opts[:pod]) if opts[:pod]
Trollop::die :log_level, "Invalid logging level.  Options are INFO (default), DEBUG, WARN, or FATAL" unless /(?i)(^INFO$)|(^DEBUG$)|(^WARN$)|(^FATAL$)/.match(opts[:log_level])
Trollop::die :vpc, "Invalid vpc identifier.  options are TLM or OSS" unless /(?i)(^TLM$)|(^OSS$)/.match(opts[:vpc])
Trollop::die :snapshot_memory, "Override memory snapshot setting. true|false" unless /(?i)(^TRUE$)(^FALSE$)/.match(opts[:snapshot_memory]) if opts[:snapshot_memory]

#Configure logging
script_name = 'vm_snapshot'
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
  $logger = Syslog::Logger.new 'gss_org_access'
  $logger.level = Kernel.const_get 'Logger::' + opts[:log_level].upcase
  puts "[ " + "INFO".white + " ] Logging started search #{script_name}[#{pid}] in /var/log/messages for logs."
end

$logger.info "INFO  - Logging initalized."
puts "[ " + "INFO".white + " ] Logging started search #{script_name}[#{pid}] for logs."

#override YAML with command-line options
pod              = opts[:pod]
vpc              = opts[:vpc]
if opts[:vc_user_given]
  vc_user          = opts[:user].split('@')[0] + '@ad'
end
$snapshot_name   = opts[:snapshot_name]
$snapshot_memory = opts[:snapshot_memory]
$quiesce         = opts[:quiesce]

#variables
params             = YAML.load_file(opts[:yaml])
pod              ||= params[:pod]
vpc              ||= params[:vpc]
vcenter            = pod + vpc + '-mgmt-vc0'
vc_user          ||= params[:user].split('@')[0] + '@ad'
$snapshot_name   ||= params[:snapshot_name]
$snapshot_memory ||= params[:snapshot_memory]
$quiesce         ||= params[:quiesce]
vm_regex           = Regexp.new(params[:vm_regex])
vcenter_pass       = ask("Enter your AD password: ") { |q| q.echo="*"};
num_workers        = 5

$logger.debug "DEBUG - opts: #{opts}"
$logger.debug "DEBUG - params: #{params.to_s}"
$logger.debug "DEBUG - pod: #{pod}"
$logger.debug "DEBUG - vpc: #{vpc}"
$logger.debug "DEBUG - vcenter: #{vcenter}"
$logger.debug "DEBUG - vc_user: #{vc_user}"
$logger.debug "DEBUG - vm_regex: #{vm_regex}"
$logger.debug "DEBUG - $snapshot_name: #{$snapshot_name}"
$logger.debug "DEBUG - $snapshot_memory: #{$snapshot_memory}"
$logger.debug "DEBUG - $quiesce: #{$quiesce}"

#methods
def find_vms(folder, regex) # recursively go thru a folder, dumping vm info
  @vms ||= []
  folder.childEntity.each do |x|
    name, junk = x.to_s.split('(')
    case name
    when "Folder"
      find_vms(x, regex)
    when "VirtualMachine"
      $logger.debug "DEBUG - Discovered #{x.name}"
      if regex =~ x.name
        if x.runtime.powerState == "poweredOn"
          print '                                                                                                                                                                      '
          print "\r"
          print "[ " + "INFO".white + " ] #{x.name} added to inventory"
          print "\r"
          $logger.info "INFO  - #{x.name} added to inventory"
          @vms.push x
        end
      end
    end
  end
  return @vms
end

def snapshot(vm_obj)
  #push task to array
  vm_name = vm_obj.name
  puts "[ " + "INFO".white + " ] Creating snapshot task for #{vm_name}."
  $logger.info "INFO  - Creating snapshot task for #{vm_name}."
  #Unless $snapshot_memory is specified at start snapshot_memory is set to true for vCenters and vcddb servers
  if $snapshot_memory.nil?
    if /vc0|vcddb/.match(vm_name)
      snapshot_memory = true
    else
      snapshot_memory = false
    end
  else
    snapshot_memory = $snapshot_memory
  end
  begin 
    task = vm_obj.CreateSnapshot_Task(name: $snapshot_name, description: ' ', memory: snapshot_memory, quiesce: $quiesce).wait_for_completion
  rescue RbVmomi::Fault => e
    puts "[ " + "ERROR".red + " ] Snapshot creation failed for #{vm_name}: #{e}"
    return
  end
  puts "[ " + "PASS".green + " ] Snapshot task successful for #{vm_name}."
  $logger.info "INFO  - Snapshot task successful for #{vm_name}"
end

#Process
#Connect to vCenter
puts "[ " + "INFO".white + " ] Connecting to #{vcenter}"
$logger.info 'INFO  - Connecting to ' + vcenter
begin
  $vim = RbVmomi::VIM.connect host: vcenter, user: vc_user, password: vcenter_pass, :insecure => true
rescue RbVmomi::Fault => e
  puts "[ " + "FAIL".red + " ] Connection to vCenter failed: #{e}"
  $logger.fatal "FATAL - Connection to #{vcenter} failed."
  $logger.error e
  exit
end

#get dc
@dc = $vim.serviceInstance.find_datacenter(pod)
if @dc.class != RbVmomi::VIM::Datacenter
  puts "[ " + "FAIL".red + " ] Failed to find datacenter."
  $logger.fatal "FATAL - Failed to get datacenter."
  exit
end

#get array of VMs
find_vms(@dc.vmFolder, vm_regex)
print '                                                                                                                                                                      '
print "\r"
puts "[ " + "INFO".white + " ] VM inventory complete"
$logger.info "INFO  - VM inventory complete."

#Queue snapshot tasks.
queue = Queue.new
threads = num_workers.times.map do
  Thread.new do
    until (vm_obj = queue.pop) == :END
      snapshot(vm_obj)
    end
  end
end
@vms.each { |vm_obj| queue << vm_obj }
num_workers.times { queue << :END }
threads.each(&:join)
puts "[ " + "PASS".green + " ] All snapshot tasks processed"

#disconnect from vCenter
print '                                                                                                                                                                      ';
print "\r";
print "[ " + "INFO".white + " ] Disconnecting from #{vcenter}";
begin 
  $vim.close  
rescue RbVmomi::Fault => e
  print '                                                                                                                                                                      '
  print "\r"
  puts "[ " + "ERROR".red + " ] Failed to disconnect from #{vcenter}: #{e}"
end
print '                                                                                                                                                                      '
print "\r"
puts "[ " + "PASS".green + " ] Disconnected from #{vcenter} "