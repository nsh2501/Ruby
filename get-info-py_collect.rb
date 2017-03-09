#!/usr/bin/env ruby
#This script will pull vm names from the py_collector database on the ops reporting server

require 'tiny_tds'
require 'trollop'
require 'colorize'
require 'json'
require 'rest-client'

#command line options
opts = Trollop::options do
  #Required parameters
  opt :vmregex, "Regex. Example: (vcd-[a-f]$|oss-mgmt-puppet|vccmt)", :type => :string, :required => false, :default => '(-vcd-[a-z]$)|(-vcd-nfs$)|(-vcdse-[a-f])|(oss-mgmt-puppet)|(mgmt-vccmt)|(mgmt-netsvc-)|(linjump)|(centosrepo)|(mgmt-ca)'
  opt :file_output, "File to place the output in.", :type => :string, :required => false
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
vms = []
failedList = []
successList = []
vmregex = Regexp.new opts[:vmregex]

#connect to ops reporting DB as dbmonitor user
client = TinyTds::Client.new username: 'dbmonitor', password: 'Gqt51093g8', host: 'd0p1tlm-opsrep', database: 'py_collector', timeout: 90

#get the 5 latest session id's and select the second largest one
result = client.execute("SELECT TOP 5 id from [Py_collect].sessions order by id desc")
results = result.each(:symbolize_keys => true, :as => :array, :cache_rows => true, :empty_sets => true) do |rowset| end
id = results[1][0]

#get vms for tlm and oss vcenters
tlm_result = client.execute("SELECT name FROM [Py_collect].inv_vsphere_vm WHERE session_id = '#{id}' AND vcenter LIKE '%tlm-mgmt%' AND power_state = 'poweredOn'")
tlm_results = tlm_result.each(:symbolize_keys => true, :as => :array, :cache_rows => true, :empty_sets => true) do |rowset| end

oss_result = client.execute("SELECT name FROM [Py_collect].inv_vsphere_vm WHERE session_id = '#{id}' AND vcenter LIKE '%oss-mgmt%' AND power_state = 'poweredOn'")
oss_results = oss_result.each(:symbolize_keys => true, :as => :array, :cache_rows => true, :empty_sets => true) do |rowset| end

#pull all vCenters listed as 6.0
vc_result = client.execute("SELECT hostname FROM [Py_collect].inv_vsphere_vc WHERE session_id = '#{id}' AND api_version = '6'")
vc_results = vc_result.each(:symbolize_keys => true, :as => :array, :cache_rows => true, :empty_sets => true) do |rowset| end

#add '-os' to the end of each VM in vc_restuls
vc_results.each do |vc|
  vc[0].concat '-os'
end

#select all results that match Regex
vms += tlm_results.select do |vm|
  vm[0] =~ vmregex
end

vms += oss_results.select do |vm|
  vm[0] =~ vmregex
end

vc_results.each do |vc|
  vms.push vc
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
      vms.reject! { |vm| vm[0].match("#{vpc['u_vpc_id']}m")}
    end
  end
end

vms.reject! { |vm| vm[0].match("d12p18")}

vms.each do |vm|
  dns = check_dns(vm[0])
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