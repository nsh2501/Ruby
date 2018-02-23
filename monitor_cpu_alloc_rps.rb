#!/usr/bin/env ruby

#this script will accept a list of vRealms and then get each resource pool and 'monitor' it from the database
require 'trollop'

require_relative '/home/nholloway/scripts/Ruby/functions/format.rb'
require_relative '/home/nholloway/scripts/Ruby/functions/password_functions.rb'
require_relative '/home/nholloway/scripts/Ruby/functions/rbvmomi_methods.rb'

#Trollop options
opts = Trollow::optios do
  #opt :vrealms, "List of vRealms to monitor", :type => :strings, :required => true
  opt :log_level, "Log level to output", :type => :string, :requried => false, :default => 'INFO'
end

#trollop die statements
#opts[:vrealms].each do |vrealm|
#  Trollop::die :vrealm, "vRealm must be in dXpYvZ format" unless /^d\d+p\d+v\d+$/.match(vrealm)
#end
Trollop::die :log_level, "Must be set to INFO or DEBUG" unless /(INFO|DEBUG)/.match(opts[:log_level])

#variables
@ad_user = 'AD\cap-p1osswinjump'
@ad_pass = 'e$1*n3$Q4'
script_name = 'monitor_cpu_alloc_rps.rb'
rsps_prop = %w(name config.cpuAllocation)
@rsp_array = []
rsp_matches = []
rsp_not_found = []
cpu_allocation_not_unlimited = []
num_workers = 5
queue = Queue.new
zen_user = 'secret-systems'
zen_pass = 'eeCair6Mu3mie0ahphup'

#vcenter list
vcenter_list = %w(d3p4v8mgmt-vc0 d7p7v27mgmt-vc0 d7p7v37mgmt-vc0 d7p7v13mgmt-vc0 d7p7v14mgmt-vc0 d7p7v20mgmt-vc0 d2p13v17mgmt-vc0 d2p13v16mgmt-vc0)

#resource pool list
rsp_list = []
rsp_list.push('PFE-EXCHANGE-VA1 (753dfe29-fce6-48fa-9a88-7beabda4a959)')
rsp_list.push('PFE-EXCHANGE-NJ1 (819b53c2-48ed-46b3-a0b8-99ec3ba78ce7)')
rsp_list.push('HCX-IX')
rsp_list.push('MIT-NJ-DEVTEST (0e328ed4-c473-44a1-84e2-196006b28b99)')
rsp_list.push('MIT-NJ-PROD (b9e2b22a-6124-48d8-8f53-b45727d488b6)')
rsp_list.push('MIT-EXP (5d656449-6cb5-41dc-b9a2-fe8039b8678e)')
rsp_list.push('MIT-CA-2 (83468dd1-a553-4f14-a717-0c29293f3a20)')
rsp_list.push('MIT-CA-1 (20c34676-5591-4958-8db8-a0c7cacb44cb)')

#configure logging
$logger = config_logger(opts[:log_level], script_name)

$logger.info "INFO - Script Options passed: vCenters: #{vcenters}, Number of Wokrers: #{num_workers}"
$logger.info "INFO - Resource Pool #{rsp_list}"


#actions to perform for each vCenter
threads = num_workers.times.map do
  Thread.new do
    until (vcenter = queue.pop) == :END
      clear_line
      print '[ ' + 'INFO'.white + " ] Connecting to vCenter: #{vcenter}"
      $logger.info "INFO - Connecting to vCenter"
      vim = connect_viserver(vcenter, @ad_user, @ad_pass)
      rsps = get_resource_pool(vim, rsps_prop)
      @rsp_array.push(*rsps)
      vim.close
      clear_line
      print '[ ' + 'INFO'.white + " ] Done collecting Resource Pools from #{vcenter}"
      $logger.info "INFO - Done collecting Resource Pools from #{vcenter}. Found #{rsps.count} Resource Pools."
    end
  end
end

#populate queue and join threads
vcenter_list.each { |vcenter| queue << vcenter };
num_workers.times { queue << :END };
threads.each(&:join);


#find all resource pools 
rsp_list.each do |resource|
  x = nil
  x = @rsp_array.find { |rsp| rsp.propSet.find { |prop| prop.name == 'name' && prop.val == resource } }
  if (x)
    rsp_matches.push(x)
  else
    rsp_not_found.push(x)
  end
end

#build list of all Resource Pools not set to unlimted
cpu_allocation_not_unlimited = rsp_matches.select { |rsp| rsp.propSet.find { |prop| prop.name == 'config.cpuAllocation' && prop.val.limit != -1 } }



