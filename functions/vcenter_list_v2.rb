#!/usr/bin/env ruby

require_relative '/home/nholloway/scripts/Ruby/functions/format.rb'
require_relative '/home/nholloway/scripts/Ruby/functions/podlist.rb'
require_relative '/home/nholloway/scripts/Ruby/functions/rbvmomi_methods.rb'

#functions
type, ad_user=nil, ad_pass=nil, pods=nil
def f_get_vcenter_list (**hash_args)
  #get domain
  domain = ENV['HOSTNAME'].split('.')[1]

  #set default's if options are not specified
  if hash_args[:pod].nil?
    pod_list = f_pod_list(hash_args[:domain])
  else
    pod_list = hash_args[:pod]
  end

  if hash_args[:type].nil?
    hash_args[:type] = 'all'
  end

  #get pod list based off of domain
  vcenters = []

  #case statement to determine list of VM's based off of type
  case type
  when 'tlm'
    pod_list.each do |pod|
      vcenters.push "#{pod}tlm-mgmt-vc0"
    end
  when 'oss'
    pod_list.each do |pod|
      vcenters.push "#{pod}oss-mgmt-vc0"
    end
  when 'mgmt'
    pod_list.each do |pod|
      vcenters.push "#{pod}tlm-mgmt-vc0"
      vcenters.push "#{pod}oss-mgmt-vc0"
    end
  when 'vpc'
    pod_list.each do |pod|
      vcenters.push "#{pod}tlm-mgmt-vc0"
      vcenters.push "#{pod}oss-mgmt-vc0"
    end
    @cust_vms = []
    num_workers = 5
    queue = Queue.new
    threads = num_workers.times.map do
      Thread.new do
        until (vcenter = queue.pop) == :END
          vms = f_get_cust_vcenters(vcenter, ad_user, ad_pass)
          @cust_vms.push(*vms)
        end
      end
    end

    vcenters.each { |vcenter| queue << vcenter }
    num_workers.times { queue << :END }
    threads.each(&:join)

    vcenters = @cust_vms
  when 'all'
    pod_list.each do |pod|
      vcenters.push "#{pod}tlm-mgmt-vc0"
      vcenters.push "#{pod}oss-mgmt-vc0"
    end
    @cust_vms = []
    num_workers = 5
    queue = Queue.new
    threads = num_workers.times.map do
      Thread.new do
        until (vcenter = queue.pop) == :END
          vms = f_get_cust_vcenters(vcenter, ad_user, ad_pass)
          @cust_vms.push(*vms)
        end
      end
    end

    vcenters.each { |vcenter| queue << vcenter }
    num_workers.times { queue << :END }
    threads.each(&:join)

    vcenters.push(*@cust_vms)
  
  else
    clear_line
    puts '[ ' + 'ERROR'.red + " ] Only valid options for f_get_vcenter_list are: tlm, oss, and mgmt"
  end
  return vcenters unless vcenters.nil?
end

def f_get_cust_vcenters(vcenter, ad_user, ad_pass)
  vim = connect_viserver(vcenter, ad_user, ad_pass)
  dc = vim.serviceInstance.find_datacenter
  result = get_vm(vim,dc)
  powered_on = result.select { |x| x.propSet.find { |prop| prop.name == 'runtime.powerState' }.val == 'poweredOn' }
  vcenters = powered_on.select { |x| x.propSet.find { |prop| prop.name == 'name' }.val =~ (/vc0/) }
  vm_names = vcenters.map { |x| x.propSet.find { |prop| prop.name == 'name' }.val }
  vim.close unless vim.nil?
  return vm_names
end