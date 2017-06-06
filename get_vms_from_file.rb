#!/usr/bin/env ruby
#This script will pull vm names from the py_collector database on the ops reporting server

require 'trollop'
require 'colorize'
require 'json'
require 'rest-client'

#command line options
opts = Trollop::options do
  #Required parameters
  opt :vmregex, "Regex. Example: (vcd-[a-f]$|oss-mgmt-puppet|vccmt)", :type => :string, :required => false, :default => '(-vcd-[a-z]$)|(-vcd-nfs$)|(-vcdse-[a-f])|(oss-mgmt-puppet)|(mgmt-vccmt)|(mgmt-netsvc-)|(linjump)|(centosrepo)|(mgmt-ca$)|(mgmt-sso)|(mgmt-cass-[a-d])|(mgmt-vcps-[a-b])|(mgmt-symds-pod-a)|(prxs-mds-[a-b])|(prxs-meter-csndra-[a-d])|(prxs-podrmq-[a-b])|(prxs-grc-[a-c])|(prxs-iam-[a-b])'
  opt :file_output, "File to place the output in.", :type => :string, :required => false
  opt :input_file, "File to read list of VM's from.", :type => :string, :required => false, :default => '/tools-export/scripts/Ruby/outputs/vmList'
  opt :remove_build_vms, "Option to remove vRealms still in Cloud Build Process", :required => false
end

def check_dns(vm)
  `/usr/bin/nslookup #{vm} | /bin/grep -q NXDOMAIN;if [ $? -eq 0 ];then echo false;else echo true;fi`.chomp
end

def clear_line ()
  print "\r"
  print "                                                                                                                   "
  print "\r"
end

#variables
failedList = []
successList = []
vmregex = Regexp.new opts[:vmregex]

#get vms from file
vm_list_all = File.readlines(opts[:input_file])
vm_list_all.map! { |line| line.chomp }

#select all results that match Regex
vms = vm_list_all.select do |vm|
  vm =~ vmregex
end


#if remove_build_vms is true check service now
if opts[:remove_build_vms] == true
  svcnow_json = RestClient::Request.execute(method: :get, url: "https://vchs.service-now.com/api/now/table/pm_project?sysparm_query=sys_class_name%3Dpm_project%5Eu_type%3DCloud%20Build%5Eactive%3Dtrue%5Eu_vpc_idISNOTEMPTY&sysparm_fields=u_vpc_id",
    headers: {accept: 'application/json'},
    user: 'vchs.p1.linjump',
    password: '3hW@HC&sKelSaq'
  )
  builds = JSON.parse(svcnow_json)
    unless builds['result'].empty?
    builds['result'].each do |vpc|
      vms.reject! { |vm| vm.match("#{vpc['u_vpc_id']}m")}
    end
  end
end

vms.each do |vm|
  dns = check_dns(vm)
  if dns == 'true'
    successList.push vm
  else
    failedList.push vm
  end
end

if opts[:file_output].nil?
  puts '[ ' + 'INFO'.green + " ] List of vms that have DNS"
  successList.each do |vm|
    puts vm
  end

  puts "\n\n\n"
  puts '[ ' + 'WARN'.yellow + " ] List of vms that do not have DNS"
  failedList.each do |vm|
    puts vm
  end
else
  successFile = opts[:file_output]
  failedFile = "#{opts[:file_output]}.failed"

  f = File.open(successFile, 'w')
  successList.each do |vm|
    f.puts(vm)
  end #@successList.each
  f.close
  puts '[ ' + 'INFO'.green + " ] List of VMs has been generated and is located at #{successFile}"

  f = File.open(failedFile, 'w')
  failedList.each do |vm|
    f.puts(vm)
  end #@successList.each
  f.close
  puts '[ ' + 'WARN'.yellow + " ] List of VMs that could not be accessed has been generated and is located at #{failedFile}"
end
