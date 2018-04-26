#!/usr/bin/env ruby
# Script to take snapshot of a virtual machine

functions_dir = File.dirname(File.realpath(__FILE__)) + '/functions'

#requires
require 'trollop'
require_relative "#{functions_dir}/password_functions.rb"
require_relative "#{functions_dir}/functions/rbvmomi_methods.rb"
require_relative "#{functions_dir}/functions/format.rb"

#params
opts = Trollop::options do
  opt :vm, "VM you want to snapshot", :type => :strings, :required => true
  opt :vcenter, "vCenter that the VM is on", :type => :string, :requied => true
  opt :snapshot_memory, "Whether or not to snapshot the memory", :type => :string, :requied => false, :default => 'true'
  opt :quiesce_filesystem, "Where or not to quiesce the filesystem", :type => :string, :required => false, :default => 'false'
  opt :snapshot_name, "Name of the snapshot. Normally the change you are running", :type => :string, :required => true
  opt :log_level, "Level of logs that you want", :type => :string, :required => false, :default => 'INFO'
end

Trollop::die :snapshot_memory, "Must be either true or false" unless (opts[:snapshot_memory] != 'true') || (opts[:snapshot_memory] != 'false')
Trollop::die :quiesce_filesystem, "Must be either true or false" unless (opts[:quiesce_filesystem] != 'true') || (opts[:quiesce_filesystem] != 'false')

#variables
ad_user =  'AD\\' + `whoami`.chomp
ad_pass = get_adPass
script_name = 'takeSnapshot.rb'
domain = ENV['HOSTNAME'].split('.')[1]


#logging
logger = config_logger(opts[:log_level].upcase, script_name)

#options to debug logs
logger.info "INFO - opts: #{opts}"
logger.debug "INFO - User: #{ad_user}"

#log into vCenter
clear_line
logger.info "INFO - Logging into #{opts[:vcenter]} to get list of vms"
print '[ ' + 'INFO'.white + " ] Logging into #{opts[:vcenter]} to get list of vms"
vim = connect_viserver(opts[:vcenter], ad_user, ad_pass)
vms = get_vm_2(vim)

opts[:vm].each do |vm_name|
  #find specific VM passed
  clear_line
  logger.info "INFO - Finding #{vm_name} from gathered VMs"
  puts '[ ' + 'INFO'.white + " ] Finding #{vm_name} from gathered VMs"

  vm = vms.find { |vm| vm.propSet.find { |prop| prop.name == 'name'}.val == vm_name }

  if vm.nil?
    clear_line
    logger.info "ERROR - Could not find #{vm_name} on vCenter #{opts[:vcenter]}."
    puts '[ ' + 'ERROR'.red + " ] Could not find #{vm_name} on vCenter #{opts[:vcenter]}."
    exit
  end

  clear_line
  logger.info "INFO - Taking snapshot of #{vm_name}"
  print '[ ' + 'INFO'.white + " ] Taking snapshot of #{vm_name}"

  snap = take_snapshot(vm, opts[:snapshot_name], opts[:snapshot_memory], opts[:quiesce_filesystem], logger)
end

clear_line
logger.info "INFO - Script completed"
print '[ ' + 'INFO'.white + " ] Script completed"

vim.close








