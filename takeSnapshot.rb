#!/usr/bin/env ruby
# Script to take snapshot of a virtual machine

#requires
require 'trollop'
require_relative '/home/nholloway/scripts/Ruby/functions/password_functions.rb'
require_relative '/home/nholloway/scripts/Ruby-test/functions/rbvmomi_methods.rb'
require_relative '/home/nholloway/scripts/Ruby/functions/format.rb'

#params
opts = Trollop::options do
  opt :vm, "VM you want to snapshot", :type => :string, :required => true
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
logger.debug "DEBUG - opts: #{opts}"
logger.debug "DEBUG - User: #{ad_user}"

#log into vCenter
clear_line
logger.info "INFO - Logging into #{opts[:vcenter]} to get list of vms"
print '[ ' + 'INFO'.white + " ] Logging into #{opts[:vcenter]} to get list of vms"
vim = connect_viserver(opts[:vcenter], ad_user, ad_pass)
vms = get_vm_2(vim)

#find specific VM passed
clear_line
logger.info "INFO - Finding #{opts[:vm]} from gathered VMs"
puts '[ ' + 'INFO'.white + " ] Finding #{opts[:vm]} from gathered VMs"

vm = vms.find { |vm| vm.propSet.find { |prop| prop.name == 'name'}.val == opts[:vm] }

if vm.nil?
  clear_line
  logger.info "ERROR - Could not find #{opts[:vm]} on vCenter #{opts[:vcenter]}."
  puts '[ ' + 'ERROR'.red + " ] Could not find #{opts[:vm]} on vCenter #{opts[:vcenter]}."
  exit
end

clear_line
logger.info "INFO - Taking snapshot of #{opts[:vm]}"
print '[ ' + 'INFO'.white + " ] Taking snapshot of #{opts[:vm]}"

snap = take_snapshot(vm, opts[:snapshot_name], opts[:snapshot_memory], opts[:quiesce_filesystem], logger)

clear_line
logger.info "INFO - Script completed"
print '[ ' + 'INFO'.white + " ] Script completed"

vim.close








