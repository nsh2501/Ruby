#!/usr/bin/env ruby

#this script will set the specified vm(s) to upgrade virtual hardware version oon next power cycle
require 'trollop'

require_relative '/home/nholloway/scripts/Ruby/functions/format.rb'
require_relative '/home/nholloway/scripts/Ruby/functions/password_functions.rb'
require_relative '/home/nholloway/scripts/Ruby/functions/rbvmomi_methods.rb'

opts = Trollop::options do 
  opt :vrealms, "List of vRealms to perform this action on", :type => :strings, :required => true
  opt :vm_version, "Hardware version to upgrade to. Example: 11", :type => :string, :required => false, :default => '11'
  opt :log_level, "Log level to set", :type => :string, :required => false, :default => 'INFO'
  opt :upg_policy, "Set this to always or never", :type => :string, :required => false, :default => 'always'
end

#verify input
opts[:vrealms].each do |vrealm|
  Trollop::die :vrealm, "vRealm must be in dXpYvZ format" unless /^d\d+p\d+v\d+$/.match(vrealm)
end
Trollop::die :vm_version, "Version must be in format XX" unless opts[:vm_version] =~ /^\d+$/
Trollop::die :log_level, "Log level must be set to INFO or DEBUG" unless /(INFO|DEBUG)/.match(opts[:log_level])

#variables
user = `whoami`.chomp
ad_pass = get_adPass
script_name = 'upgrade_vm_compatibility.rb'
vm_prop = %w(name runtime.powerState summary.guest.toolsStatus resourcePool)
vm_version = 'vmx-' + opts[:vm_version]
upg_info = RbVmomi::VIM::ScheduledHardwareUpgradeInfo(upgradePolicy: opts[:upg_policy], versionKey: vm_version)
spec = RbVmomi::VIM::VirtualMachineConfigSpec(scheduledHardwareUpgradeInfo: upg_info)


#configure logging
$logger = config_logger(opts[:log_level], script_name)

$logger.info "INFO - Script options. User: #{user}, Vrealms: #{opts[:vrealms]}, VMs: opts[:vms]}, Version: #{opts[:vm_version]}, Policy: #{opts[:upg_policy]}"

#get list of vms from vRealms
opts[:vrealms].each do |vrealm|
  vcenter = vrealm + 'mgmt-vc0'
  clear_line
  print '[ ' + 'INFO'.white + " ] Logging into #{vcenter}"
  $logger.info "INFO - Logging into #{vcenter}"
  vim = connect_viserver(vcenter, user, ad_pass)

  #get list of vms
  clear_line
  print '[ ' + 'INFO'.white + " ] Getting list of VMs and Resource Pools"
  $logger.info "INFO - Getting list of VMs and Resource Pools"
  all_vms = get_vm_2(vim, vm_prop)
  all_rps = get_resource_pool(vim)

  #print count of vms if debug
  $logger.debug "DEBUG - Number of VMs gathered. #{all_vms.count}"

  #get of list of cutomer created Resource Pools
  cust_rps = all_rps.select { |pool| pool.propSet.find { |prop| prop.name == 'name' && prop.val !~ /System vDC|vmware_service|Resources|fleetRP/ } }

  #get all VMs in Resource Pools created by customer
  cust_vms = []
  clear_line
  print '[ ' + 'INFO'.white + " ] Getting list of Customer VMs"
  $logger.info "INFO - Gettng list of Customer VMs"
  cust_rps.each do |pool|
    cust_vms += all_vms.select do |vm| 
      vm.propSet.find do |prop|
        prop.name == 'resourcePool' && prop.val == pool.obj
      end
    end
  end

  #Set upgrade policy on all VMs found
  clear_line
  print '[ ' + 'INFO'.white + " ] Setting the upgrade policy on each VM"
  $logger.info "INFO - Setting the upgrade policy on each VM"

  cust_vms.each do |vm|
    vm_name = vm.propSet.find { |prop| prop.name == 'name' }.val
    begin
      task = vm.obj.ReconfigVM_Task(spec: spec)
      task_state = task.info.state
      count = 0
      while (task.info.state == 'running') && (count <= 5) do 
        sleep 1
        clear_line
        puts '[ ' + 'ERROR'.red + " ] Task still in running state after 5 seconds. Please check VM: #{vm_name} in #{vcenter}" if count == 5
      end
      task_state = task.info.state
      $logger.debug "DEBUG - VM Name: #{vm_name}, Task State: #{task_state}"
    rescue => e
      clear_line
      puts '[ ' + 'ERROR'.red + " ] Unknown error occured when trying to set the upgrade policy. Please see below message."
      puts '[ ' + 'ERROR'.red + " ] Error: #{e}"
      $logger.info "ERROR - Unknown error occured when trying to set the upgrade policy. Please see below message."
      $logger.info "ERROR - Error: #{e}"
    end
  end
  clear_line
  print '[ ' + 'INFO'.white + " ] Completed all vms in #{vcenter}."
  $logger.info "INFO - Completed all vms in #{vcenter}"
  vim.close
end

#end o script
clear_line
print '[ ' + 'INFO'.white + " ] Completed all vRealms in list."
$logger.info "INFO - Completed all vRealms in list."