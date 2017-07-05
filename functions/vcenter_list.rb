#!/usr/bin/env ruby

require_relative '/home/nholloway/scripts/Ruby/functions/format.rb'
require_relative '/home/nholloway/scripts/Ruby/functions/podlist.rb'

#functions

def f_get_vcenter_list (domain, type)
  #get pod list based off of domain
  pod_list = f_pod_list(domain)
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
  else
    clear_line
    puts '[ ' + 'ERROR'.red + " ] Only valid options for f_get_vcenter_list are: tlm, oss, and mgmt"
  end
  return vcenters unless vcenters.nil?
end