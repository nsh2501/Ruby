#!/usr/bin/env ruby

require 'rbvmomi'
require 'highline/import'
require 'net/ssh'
require 'trollop'
require 'colorize'
require 'syslog/logger'
require 'json'
require 'rest-client'


#personal functions
require_relative "/home/nholloway/scripts/Ruby/functions/get_password.rb"

opts = Trollop::options do
  # parameters
  opt :vrealms, "vRealm(s) to run the vSphere 6 presto update commands to", :type => :strings, :required => false
  opt :pods, "Do a whole pod instead of just a single vRealms", :type => :strings, :required => false
  opt :vc_user, "vCenter user to get list of vRealms in a pod. Defaul will use linjump user", :type => :string, :required => false
end

if (opts[:vrealms] == nil && opts[:pods] == nil)
  puts '[ ' + 'ERROR'.red + " ] Must specify either vrealms or pods"
  exit
end

if (opts[:vrealms_given] == true && opts[:pods_given] == true)
  puts '[ ' + 'ERROR'.red + " ] Must specify either vrealms or pods"
  exit
end  

if opts[:vc_user] == nil
  vc_user = `whoami`.chomp + "@ad.prod.vpc.vmw"
else
  vc_user = opts[:vc_user].split('@')[0] + '@ad.prod.vpc.vmw'
end

#Functions
def clear_line ()
  print "\r"
  print "                                                                                                                   "
  print "\r"
end

def list_vms(folder)
  children = folder.children.find_all
  children.each do |child|
    if child.class == RbVmomi::VIM::VirtualMachine
      if child.runtime.powerState == 'poweredOn' && child.config.name =~ /vc0/ && child.config.name !~ /tlm-mgmt-vc0/
        @vms.push child.name
          clear_line
          print "[ " + "INFO".green + " ] #{child.name} added to inventory"
          
      end
    elsif child.class == RbVmomi::VIM::Folder
      list_vms(child)
    end
  end
end

def verifyAD_Pass(vm, user, pass)
  access = 'false'
  clear_line
  print '[ ' + 'INFO'.green + " ] Verifying AD Password"
  while access == 'false'
    begin
      session = Net::SSH.start(vm, user, :password => pass, :auth_methods => ['password'], :number_of_password_prompts => 0)
      access = 'true'
      clear_line
      print '[ ' + 'INFO'.green + " ] AD Authentication successful"
      session.close
    rescue Net::SSH::AuthenticationFailed 
        clear_line
        puts '[ ' + 'WARN'.yellow + " ] Failed to authenticate to #{vm} with password provided."
        pass = ask("Please enter your Ad Password") { |q| q.echo="*"}
    end
  end
  return pass
end

def rest_session(url, user, password)
  session = RestClient::Resource.new(url,
  :user => user,
  :password => password,
  :verify_ssl  => OpenSSL::SSL::VERIFY_NONE)

  return session
end

#process
pid = Process.pid

#date
time = Time.new
datestamp = time.strftime("%m%d%Y-%s")

#Configure Logging
#script_name = 'vSphere6_UpdatePresto'
#logger = Syslog::Logger.new script_name
#logger.level = Kernel.const_get 'Logger::INFO'
#logger.info "INFO  - Logging initalized."
#puts "[ " + "INFO".green + " ] Logging started search #{script_name}[#{pid}] in /var/log/messages for logs."

#variables
adPass = ask("Enter the AD password for the user #{vc_user}: ") { |q| q.echo="*"};
localVM = `hostname`.chomp
adPass = verifyAD_Pass(localVM, vc_user, adPass)
prestoUser = vc_user.split('@')[0]
prestoVM = 'd0p1oss-presto-b'
prestoRootPass = get_password(prestoVM, 'root')
@vms = []
vrealms = []
podArray = []

clear_line
puts '[ ' + 'INFO'.green + " ] Getting list of all vRealms for each pod"
#get list of vCenters if pods variable is defined
unless opts[:pods].nil?
  opts[:pods].each do |pod| 
    podSubnet = pod.to_i * 2
    vc = "10.#{podSubnet}.3.2"
    clear_line
    print '[ ' + 'INFO'.green + " ] Logging into #{vc}"
    
    #connect to vCenter
    vim = RbVmomi::VIM.connect :host => vc, :user => vc_user, :password => adPass, :insecure => true

    #get datacenter
    dc = vim.serviceInstance.find_datacenter

    list_vms(dc.vmFolder)

    vim.close
  end #end of opts[:pods].each do |pod|

  clear_line
  puts '[ ' + 'INFO'.green + " ] Querying presto for each vRealm found to get vRealm Type"
  foundVms = @vms
  foundVms.each do |vm|
    numbers = vm.scan(/\d+/)
    dc_num = numbers[0]
    pod_num = numbers[1]
    vpc_num = numbers[2]
    vrealm = "d#{dc_num}p#{pod_num}v#{vpc_num}"

    #build URL to query presto
    clear_line
    print '[ ' + 'INFO'.green + " ] Querying presto for #{vrealm}"
    
    url = "https://10.2.28.97:443/api/v2/version_data?datacenter_instance_id=#{dc_num}&pod_instance_id=#{pod_num}&vrealm_instance_id=#{vpc_num}"
    session = rest_session(url, prestoUser, adPass)
    e = nil
    begin
      sessionGet = session.get
    rescue => e
      puts '[ ' + 'ERROR'.red + " ] Error getting info from presto. Pod: #{pod_num}, VPC: #{vpc_num}"
    end

    unless e
      jsonObj = JSON.parse(sessionGet)
      collectionType = jsonObj['rows'][0]['parent']['collection_type_name']
      if collectionType == 'vRealm'
        vrealms.push vrealm
      end #if collectionType == 'vRealm'
    end #unless e.nil
  end #end of foundVms.each do |vm|
end #end of unless opts[:pods].nil?

#query presto if opts[:vrealms] is defined
unless opts[:vrealms].nil?
  opts[:vrealms].each do |vpc|
    numbers = vpc.scan(/\d+/)
    dc_num = numbers[0]
    pod_num = numbers[1]
    vpc_num = numbers[2]
    vrealm = "d#{dc_num}p#{pod_num}v#{vpc_num}"

    #build URL to query presto
    clear_line
    print '[ ' + 'INFO'.green + " ] Querying presto for #{vrealm}"
    
    url = "https://10.2.28.97:443/api/v2/version_data?datacenter_instance_id=#{dc_num}&pod_instance_id=#{pod_num}&vrealm_instance_id=#{vpc_num}"
    session = rest_session(url, prestoUser, adPass)
    e = nil
    begin
      sessionGet = session.get
    rescue => e
      clear_line
      puts '[ ' + 'ERROR'.red + " ] Error getting info from presto. Pod: #{pod_num}, VPC: #{vpc_num}"
    end

    unless e
      jsonObj = JSON.parse(sessionGet)
      collectionType = jsonObj['rows'][0]['parent']['collection_type_name']
      if collectionType == 'vRealm'
        vrealms.push vrealm
      else
        clear_line
        puts '[ ' + 'WARN'.yellow + " ] #{vrealm} is not type vrealm in presto. Not adding this to the list"
      end #if collectionType == 'vRealm'
    end #unless e.nil
  end #opts[:vrealms].each do |vpc|
end #unless opts[:vrealms].nil?

#connecting to presto-b to run update commands
clear_line
puts '[ ' + 'INFO'.green + " ] Logging into the presto-b server"
sshSession = Net::SSH.start(prestoVM, "root", :password => prestoRootPass, :auth_methods => ['password'])
unless sshSession.nil?
  vrealms.each do |vrealm|
    clear_line
    print '[ ' + 'INFO'.green + " ] Creating vc_vsupg for vRealm: #{vrealm}"
    
    #Get vpc identifiers
    numbers = vrealm.scan(/\d+/)
    dc_num = numbers[0]
    pod_num = numbers[1]
    vpc_num = numbers[2]

    #get update command
    cmd = nil
    cmd = "sudo -i -u presto bash -c 'export RAILS_ENV=production;rake vcenter:create_vc_vsupg[#{pod_num},\"vRealm\",#{vpc_num},\"medium\"]'"
    sshSession.exec!(cmd)
  end #vrealms.each do |vrealm|
  vrealms.each do |vrealm|
    podArray.push vrealm.split('v')[0]
  end #vrealms.each do |vrealm|
  podArray.uniq!
  podArray.each do |pod|
    numbers = pod.scan(/\d+/)
    dc_num = numbers[0]
    pod_num = numbers[1]
    clear_line
    print '[ ' + 'INFO'.green + " ] Updating pod #{pod_num} in presto"
    
    cmd = nil
    cmd = "sudo -i -u presto bash -c 'export RAILS_ENV=production;rake vcenter:update_vc_vsupg_information[#{dc_num}, #{pod_num}]'"
    sshSession.exec!(cmd)
  end #podArray.each do |pod|
  sshSession.close
  clear_line
  puts '[ ' + 'INFO'.green + " ] Completed"
end #unless sshSession.nil?
