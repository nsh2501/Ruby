#!/usr/bin/env ruby

#this script will get a list of all VM's in prod from TLM/OSS

require 'trollop'

require_relative '/home/nholloway/scripts/Ruby/functions/format.rb'
require_relative '/home/nholloway/scripts/Ruby/functions/get_password.rb'
require_relative '/home/nholloway/scripts/Ruby/functions/rbvmomi_methods.rb'
require_relative '/home/nholloway/scripts/Ruby/functions/vcenter_list.rb'

opts = Trollop::options do
  opt :vcenters, 'List of vcenters. Example: d0p1tlm-mgmt-vc0 d0p1oss-mgmt-vc0', :type => :strings, :required => false
  opt :vcenter_type, 'Type of vCenters you wish to get VM\'s from. Example: tlm, oss, or mgmt', :type => :string, :required => false
  opt :num_workers, 'Then number of threads', :type => :int, :required => false, :default => 5
  opt :file, 'File to save output to. If not set then output will send to screen', :type => :string, :required => false
end

#die conditions
Trollop::die "You must specify ether --vcenters or --vcenter_type not both." if (!opts[:vcenters].nil?) && (!opts[:vcenter_type].nil?)
Trollop::die "Valid options are tlm, oss, or mgmt" unless (opts[:vcenter_type] =~ (/^tlm|mgmt|oss$/)) || opts[:vcenter_type].nil?

#variables
@ad_user = 'AD\cap-p1osswinjump'
@ad_pass = 'e$1*n3$Q4'
@vim_inv = []
domain = ENV['HOSTNAME'].split('.')[1]
num_workers = 5
queue = Queue.new

#get vcenter list
if opts[:vcenter_type].nil?
  vcenter_list = opts[:vcenters]
else
  vcenter_list = f_get_vcenter_list(domain, opts[:vcenter_type])
end

#build threads based off of number of workers specified
threads = num_workers.times.map do
 Thread.new do
   until (vcenter = queue.pop) == :END
    puts
    clear_line
    print '[ ' + 'INFO'.green + " ] Collecting VM's from #{vcenter}"
     vim = connect_viserver(vcenter, @ad_user, @ad_pass)
     dc = vim.serviceInstance.find_datacenter
     vim_inv = get_inv_info(vim, dc, nil, nil)
     @vim_inv.push(*vim_inv)
     vim.close
     clear_line
     print '[ ' + 'INFO'.green + " ] Done collecting VM's from #{vcenter}"
   end
 end
end

#populate queue, set :END to end of each queue, join threads
vcenter_list.each { |vcenter| queue << vcenter };
num_workers.times { queue << :END };
threads.each(&:join)

clear_line
puts '[ ' + 'INFO'.green + " ] Completed collecting from all vcenters"

#get list of VM's from inventory
vms = @vim_inv.select { |inv| inv.obj.is_a?(RbVmomi::VIM::VirtualMachine) }
powered_on_vms = vms.select { |vm| vm.propSet[1].val == 'poweredOn' }

if opts[:file].nil?
  powered_on_vms.each do |vm|
    puts "#{vm.propSet[0].val}"
  end
else
  f = File.open(opts[:file], 'w')
  powered_on_vms.each do |vm|
    f.puts(vm.propSet[0].val)
  end
  f.close
end









