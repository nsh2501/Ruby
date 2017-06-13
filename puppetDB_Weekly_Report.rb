#!/usr/bin/env ruby
#this script will collect a list of vms from py_collector and from puppetDB and do a compare
require 'rest-client'
require 'json'
require 'trollop'
require 'tiny_tds'
require 'pp'
require 'mail'
require_relative "/home/nholloway/scripts/Ruby/functions/podlist.rb"

#command line options
opts = Trollop::options do
  opt :vmregex, "Regex. Example: (vcd-[a-f]$|oss-mgmt-puppet|vccmt)", :type => :string, :required => false, :default => '(-vcd-[a-z]$)|(-vcd-nfs$)|(-vcdse-[a-f])|(oss-mgmt-puppet)|(oss-mgmt-netsvc-[a-b])|(mgmt-vc0)|(mgmt-centosrepo)|(mgmt-linjump)'
  opt :email, "Option for emailing instead of printing to screen", :type => :strings, :required => false
end

def clear_line ()
  print "\r"
  print "                                                                                                                   "
  print "\r"
end

def pupdb_query(podID, endpoint, query)
  begin
    RestClient::Request.execute(method: :post, url: "https://#{podID}oss-mgmt-puppetdb.prod.vpc.vmw:8081/pdb/query/v4/#{endpoint}",
      headers: {accept: 'application/json', content_type: 'application/json'},
      payload: "#{query}",  
      ssl_ca_file: "/home/nholloway/puppetCerts/#{podID}-ca.pem",
      ssl_client_cert: OpenSSL::X509::Certificate.new(File.read("/home/nholloway/puppetCerts/#{podID}-cert.pem")),
      ssl_client_key: OpenSSL::PKey::RSA.new(File.read("/home/nholloway/puppetCerts/#{podID}-key.pem"))
    )
  rescue => e
    pp e
  end
end

def check_dns(vm)
  `/usr/bin/nslookup #{vm} | /bin/grep -q NXDOMAIN;if [ $? -eq 0 ];then echo false;else echo true;fi`.chomp
end

def get_old(podID)
query = nil
yesterday = (DateTime.now - 1).to_time
begin
  nodes = RestClient::Request.execute(method: :post, url: "https://#{podID}oss-mgmt-puppetdb.prod.vpc.vmw:8081/pdb/query/v4/nodes",
    headers: {accept: 'application/json', content_type: 'application/json'},
    payload: "#{query}",  
    ssl_ca_file: "/home/nholloway/puppetCerts/#{podID}-ca.pem",
    ssl_client_cert: OpenSSL::X509::Certificate.new(File.read("/home/nholloway/puppetCerts/#{podID}-cert.pem")),
    ssl_client_key: OpenSSL::PKey::RSA.new(File.read("/home/nholloway/puppetCerts/#{podID}-key.pem"))
  )
rescue => e
  puts e
end
oldArray = {}
nodes = JSON.parse(nodes)
nodes.each do |x|
  unless x['report_timestamp'].nil?
    rtime = Time.parse(x['report_timestamp'])
    if yesterday > rtime
      dns = check_dns("#{x['certname']}")
      if dns == 'true'
        oldArray["#{x['certname']}"] = Hash.new
        oldArray["#{x['certname']}"]['timestamp'] = "#{x['report_timestamp']}"
        oldArray["#{x['certname']}"]['dns'] = dns
      end
    end
  end
  if x['report_timestamp'].nil?
    dns = check_dns("#{x['certname']}")
    if dns == 'true'
      oldArray["#{x['certname']}"] = Hash.new
      oldArray["#{x['certname']}"]['timestamp'] = "Nil Timestamp"
      oldArray["#{x['certname']}"]['dns'] = dns
    end
  end
end
  unless oldArray.empty? || oldArray.nil?
    return oldArray
  end
end



#variables
domain = ENV["HOSTNAME"].split(".")[1]
py_collect_vms = []
py_collect_vms_array = []
puppetdb_vms_all = []
puppetdb_vms = []
podList = f_pod_list(domain)
oldArray = {}
issues = false
vmregex = Regexp.new opts[:vmregex]

#connect to ops reporting DB as dbmonitor user
client = TinyTds::Client.new username: 'dbmonitor', password: 'Gqt51093g8', host: 'd0p1tlm-opsrep', database: 'py_collector', timeout: 30

#get the 5 latest session id's and select the second largest one
result = client.execute("SELECT TOP 5 id from [Py_collect].sessions order by id desc")
results = result.each(:symbolize_keys => true, :as => :array, :cache_rows => true, :empty_sets => true) do |rowset| end
id = results[1][0]

#get vms for tlm and oss vcenters
tlm_result = client.execute("SELECT name FROM [Py_collect].inv_vsphere_vm WHERE session_id = '#{id}' AND vcenter LIKE '%tlm-mgmt%' AND power_state = 'poweredOn' AND name NOT LIKE '%vc0%'")
tlm_results = tlm_result.each(:symbolize_keys => true, :as => :array, :cache_rows => true, :empty_sets => true) do |rowset| end

oss_result = client.execute("SELECT name FROM [Py_collect].inv_vsphere_vm WHERE session_id = '#{id}' AND vcenter LIKE '%oss-mgmt%' AND power_state = 'poweredOn' AND name NOT LIKE '%vc0%'")
oss_results = oss_result.each(:symbolize_keys => true, :as => :array, :cache_rows => true, :empty_sets => true) do |rowset| end

vc_result = client.execute("SELECT hostname FROM [Py_collect].inv_vsphere_vc WHERE session_id = '#{id}' AND api_version = '6'")
vc_results = vc_result.each(:symbolize_keys => true, :as => :array, :cache_rows => true, :empty_sets => true) do |rowset| end

#combine the arrays
db_results = tlm_results
db_results.concat oss_results
db_results.concat vc_results

#close out DB connection
client.close

#select all results that match Regex
py_collect_vms += tlm_results.select do |vm|
  vm[0] =~ vmregex
end

py_collect_vms.each do |vm|
  py_collect_vms_array.push vm[0]
end

#get all vms from puppetdb
podList.each do |pod|
  puppetdb_vms_all += JSON.parse(pupdb_query(pod, 'nodes', ' '))
  oldVMs = get_old(pod)
  unless oldVMs.nil?
    oldArray = oldArray.merge(oldVMs)
  end
end

#only get certname
puppetdb_vms_all.each do |vm|
  puppetdb_vms.push vm['certname'].split('.')[0]
end

#if remove_build_vms is true check service now
svcnow_json = RestClient::Request.execute(method: :get, url: "https://vchs.service-now.com/api/now/table/pm_project?sysparm_query=sys_class_name%3Dpm_project%5Eu_type%3DCloud%20Build%5Eactive%3Dtrue%5Eu_vpc_idISNOTEMPTY&sysparm_fields=u_vpc_id",
  headers: {accept: 'application/json'},
  user: 'vchs.p1.linjump',
  password: '3hW@HC&sKelSaq'
)
builds = JSON.parse(svcnow_json)
  unless builds['result'].empty?
  builds['result'].each do |vpc|
    py_collect_vms_array.reject! { |vm| vm.match("#{vpc['u_vpc_id']}m")}
  end
end

#remove pod 18 VMs
py_collect_vms_array.reject! { |vm| vm.match("d12p18") }

#get list of missing VMs and check if DNS is configure for the VM
missing_vms = py_collect_vms_array - puppetdb_vms
missing_vms.delete_if { |vm| check_dns(vm) == 'false' }

#if email then send out email, otherwise print to screen
if opts[:email].nil?
  #list out vms that are not in puppetDB
  puts "Here is a list of all VMs in prod that are not in puppetDB"
  pp missing_vms
  puts "\nHere is a list of all VMs in prod that have not checked in, in the last 24 hours"
  pp oldArray
else
  to_email = opts[:email].join('; ')
  from_email = 'p1-linjump@prod.vpc.vmw'
  subject = 'Weekly PuppetDB Report'
  content_type = 'text/html; charset=UTF-8'
  email_array = []
  unless missing_vms.nil? || missing_vms.empty?
    issues = true
    email_array.push '<h1>Missing VMs from PuppetDB</h1>'
    email_array.push '<table border="2">'
    email_array.push '<tr><th>VM Name</th></tr>'
    missing_vms.each do |vm|
      email_array.push "<tr><td>#{vm}</td></tr>"
    end
    email_array.push '</table>'
  end

  unless oldArray.empty? || oldArray.nil?
    issues = true
    email_array.push '<h1>VMs that have not checked-in in the last 24 hours</h1>'
    email_array.push '<table border="2">'
    email_array.push '<tr><th>VM Name</th><th>Timestamp</th><th>DNS</th></tr>'
    oldArray.each do |vm|
      email_array.push "<tr><td>#{vm[0]}</td><td>#{vm[1]['timestamp']}</td><td>#{vm[1]['dns']}</td></tr>"
    end
    email_array.push '</table>'
  end

  if issues == false
    subject = 'Weekly PuppetDB Report - No issues found'
    email_array.push 'No Issues found!'
  end

  Mail.deliver do
    to "#{to_email}"
    from "#{from_email}"
    subject "#{subject}"
    content_type "#{content_type}"
    body "#{email_array.join('')}"
  end
end