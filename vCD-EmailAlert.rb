#!/usr/bin/env ruby
#this script can be used to remove/change the alerting email from vCloud-Director under the Administrator tab

require 'vcd_functions'
require 'trollop'
require 'nokogiri'
require 'rbvmomi'
require 'syslog/logger'
require 'net/ssh'
require 'socket'
require 'timeout'

#require 'pry';binding.pry

#procss ID
pid = Process.pid

#command line options
opts = Trollop::options do
  opt :vrealms, "vRealms to modify the email in vCD. Example: dXpYvZ dXpYvZ", :type => :strings, :required => false
  opt :pods, "List of pods to modify the emails in vCD. Example: 1 10 6", :type => :ints, :required => false
  opt :user, "User to use when logging into the vCloud Director. Defaults to linjump user. Example: nholloway", :type => :string, :required => false
end

def clear_line ()
  print "\r"
  print "                                                                                                                   "
  print "\r"
end

def list_vms(folder)
  children = folder.children.find_all
  children.each do |child|
    if child.class == RbVmomi::VIM::VirtualMachine
      if child.runtime.powerState == 'poweredOn' && child.config.name =~ /-vcd-[a-z]$/
        @vms.push child.name
          clear_line
          print "[ " + "INFO".green + " ] #{child.name} added to inventory"
          @logger.info "INFO - #{child.name} added to inventory"
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
      @logger.info "INFO - AD Authentication successful"
      session.close
    rescue Net::SSH::AuthenticationFailed
        clear_line
        puts '[ ' + 'WARN'.yellow + " ] Failed to authenticate to #{vm} with password provided."
        @logger.info "WARN - Failed to authenticate to #{vm} with password provided."
        pass = ask("Please enter your Ad Password") { |q| q.echo="*"}
    end
  end
  return pass
end

=begin
def port_check(vm, port, timeout=3)
  Timeout::timeout(timeout) do
    begin
      begin
        s = TCPSocket.new(vm, port)
        s.close
        return true
      rescue
        return false
      end
    rescue Timeout::Error
      return false
    end
  end
end
=end

def remove_email(vpc, user, password)
  session = Vcd_functions::Session.new(vpc, user)
  response = session.login(password)
  if response.code != 200
    clear_line
    puts '[ ' + 'ERROR'.red + " ] Could not log into #{vpc}"
    @logger.info "ERROR - Could not log into #{vpc}"
  else
    clear_line
    print '[ ' + 'INFO'.green + " ] Logged into #{vpc} vCD sucessfully"
    @logger.info "INFO - Logged into #{vpc} vCD sucessfully"
    email_set = session.get('/admin/extension/settings/email');
    emailXML = Nokogiri::XML(email_set);
    emailXML.at("//vmext:AlertEmailTo").content = ''
    response = session.put('/admin/extension/settings/email', emailXML.to_xml, 'application/vnd.vmware.admin.emailSettings+xml')
    if response.code == 200
      clear_line
      puts '[ ' + 'INFO'.green + " ] Removed email alerting from #{vpc}"
      @logger.info "INFO - Removed email alerting from #{vpc}"
    else
      clear_line
      puts '[ ' + 'ERROR'.red + " ] Failed to remove email alerting from #{vpc}"
      @logger.info "ERROR - Failed to remove email alerting from #{vpc}"
    end
    session.logout
  end
end #def remove_email

#configure logging
executeUser = `whoami`.chomp
script_name = 'vCD-EmailAlert.rb'
@logger = Syslog::Logger.new script_name
@logger.level = Kernel.const_get 'Logger::INFO'
@logger.info "INFO - Logging initalized. User: #{executeUser}"
puts "[ " + "INFO".green + " ] Logging started search #{script_name}[#{pid}] in /var/log/messages for logs."

#option verification
if opts[:vrealms].nil? && opts[:pods].nil?
  clear_line
  puts '[ ' + 'ERROR'.red + " ] You must either specify --vrealms or --pods."
  exit
end

if opts[:user].nil?
  opts[:user] = `whoami`.chomp
end

#variables
@vms = []
vrealm_list = []
vcUser = opts[:user].dup
vcUser = vcUser.concat "@ad.prod.vpc.vmw"

#Prompt for AD Pass and verify it
adPassAsk = ask("Please enter you AD Password") { |q| q.echo="*"}

#verify AD password
adPass = verifyAD_Pass(`hostname`.chomp, opts[:user], adPassAsk)

#get list of VMs from each pod
unless opts[:pods].nil?
  opts[:pods].each do |pod|
    podSubnet = pod.to_i * 2
    vcenter = "10.#{podSubnet}.3.2"
    clear_line
    print '[ ' + 'INFO'.green + " ] Logging into #{vcenter} to get list of vRealms"
    @logger.info "INFO - Logging into #{vcenter} to get list of vRealms"

    #connect to vCenter
    begin
      vim = RbVmomi::VIM.connect :host => vcenter, :user => vcUser, :password => adPass, :insecure => true

      #get dc
      dc = vim.serviceInstance.find_datacenter

      #get list of vms
      list_vms(dc.vmFolder)

      #exit from vCenter
      clear_line
      print '[ ' + 'INFO'.green + " ] Exiting from #{vcenter}"
      vim.close
    rescue
      clear_line
      puts '[ ' + 'ERROR'.red + " ] Failed to login to #{vcenter}"
    end
  end #opts[:pods].each do |pod|

  @vms.each do |vm|
    numbers = vm.scan(/\d+/)
    vpc = 'd' + numbers[0] + 'p' + numbers[1] + 'v' + numbers[2]
    vrealm_list.push vpc
  end
end

unless opts[:vrealms].nil?
  opts[:vrealms].each do |vrealm|
    numbers = vrealm.scan(/\d+/)
    vpc = 'd' + numbers[0] + 'p' + numbers[1] + 'v' + numbers[2]
    vrealm_list.push vpc
  end
end

vrealm_list.uniq!

unless vrealm_list.nil?
  vrealm_list.each do |vpc|
    remove_email(vpc, opts[:user], adPass)
  end #vrealm_list.each do |vpc|
end #unless vrealm_list.nil?
