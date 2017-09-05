#!/usr/bin/env ruby

require_relative '/home/nholloway/scripts/Ruby/functions/format.rb'
require_relative '/home/nholloway/scripts/Ruby/functions/podlist.rb'
require_relative '/home/nholloway/scripts/Ruby/functions/rbvmomi_methods.rb'

#functions
def f_get_vcenter_list(logger, **hash_args)
  #get domain
  domain = ENV['HOSTNAME'].split('.')[1]

  #set default's if options are not specified
  if hash_args[:pod].nil?
    pod_list = f_pod_list(domain)
  else
    pod_list = hash_args[:pod]
  end

  if hash_args[:type].nil?
    hash_args[:type] = 'all'
  end

  logger.debug "DEBUG - Arguments passed into f_get_vcenter_list: #{hash_args}"

  #get pod list based off of domain
  vcenters = []

  #case statement to determine list of VM's based off of type
  case hash_args[:type]
  when 'tlm'
    clear_line
    logger.info "INFO - Gettin list of TLM vCenters."
    print '[ ' + 'INFO'.white + " ] Getting list of TLM vCenters"
    pod_list.each do |pod|
      vcenters.push "#{pod}tlm-mgmt-vc0"
    end
  when 'oss'
    clear_line
    logger.info "INFO - Gettin list of OSS vCenters."
    print '[ ' + 'INFO'.white + " ] Getting list of OSS vCenters"
    pod_list.each do |pod|
      vcenters.push "#{pod}oss-mgmt-vc0"
    end
  when 'mgmt'
    clear_line
    logger.info "INFO - Gettin list of MGMT vCenters."
    print '[ ' + 'INFO'.white + " ] Getting list of MGMT vCenters"
    pod_list.each do |pod|
      vcenters.push "#{pod}tlm-mgmt-vc0"
      vcenters.push "#{pod}oss-mgmt-vc0"
    end
  when 'vpc'
    clear_line
    logger.info "INFO - Gettin list of customer vCenters."
    print '[ ' + 'INFO'.white + " ] Getting list of customer vCenters"
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
          vms = f_get_cust_vcenters(vcenter, hash_args[:ad_user], hash_args[:ad_pass])
          @cust_vms.push(*vms)
        end
      end
    end

    vcenters.each { |vcenter| queue << vcenter }
    num_workers.times { queue << :END }
    threads.each(&:join)

    vcenters = @cust_vms
  when 'all'
    clear_line
    logger.info "INFO - Gettin list of all vCenters."
    print '[ ' + 'INFO'.white + " ] Getting list of all vCenters"
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
          vms = f_get_cust_vcenters(vcenter, hash_args[:ad_user], hash_args[:ad_pass])
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
  clear_line
  logger.info "INFO - Completed getting list of vCenters"
  print '[ ' + 'INFO'.white + " ] Completed getting list of vCenters"
  logger.debug "DEBUG - Full list of vCenters. #{vcenters}"
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