#!/usr/bin/env ruby

require 'trollop'
require 'rbvmomi'
require 'syslog/logger'
require 'net/ssh'
require 'socket'
require 'timeout'
require 'colorize'
require 'highline/import'

#require 'pry';binding.pry

#procss ID
pid = Process.pid

opts = Trollop::options do 
  opt :pods, "List of Pods to gather VM list from. Example: 1 2 3", :type => :ints, :required => false
  opt :all_pods, "Use this option if you want to gather VMs from all pods. Example: --all-pods", :required => false
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
      if child.runtime.powerState == 'poweredOn' && child.config.name =~ /(-vcd-[a-z]$)|(-vcd-nfs$)/
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

def podList()
  #this function will find all pods in prod
  (1..30).each do |pod|
    begin
      Timeout::timeout(1) do
        begin
          s = TCPSocket.new("172.20.#{pod}.3", 22)
          s.close
          @podList.push pod
        rescue
        end #end of second begin
      end #end of timeout
    rescue Timeout::Error
    end #end of begin
  end #(1..X).each
end #def podList

def port_check(vm, port)
  begin
    Timeout::timeout(1) do
      begin
          s = TCPSocket.new(vm, port)
          s.close
          clear_line
          print '[ ' + 'INFO'.green + " ] Validated #{vm}"
          @successList.push vm
      rescue
        clear_line
        print '[ ' + 'INFO'.green + " ] Could not connect to #{vmw}"
        @failedList.push vm
      end #second begin
    end #timeout
  rescue Timeout::Error
    clear_line
    print '[ ' + 'INFO'.green + " ] Could not connect to #{vmw}"
    @failedList.push vm
  end #first begin
end #def port_check


#configure logging
executeUser = `whoami`.chomp
script_name = 'zenoss_vm-list.rb'
@logger = Syslog::Logger.new script_name
@logger.level = Kernel.const_get 'Logger::INFO'
@logger.info "INFO - Logging initalized. User: #{executeUser}"
puts "[ " + "INFO".green + " ] Logging started search #{script_name}[#{pid}] in /var/log/messages for logs."

#variables
@vms = []
@podList = []
@failedList = []
@successList = []
adUser = executeUser + '@ad.prod.vpc.vmw'
successFile = '/tools-export/scripts/Ruby/outputs/vms_for_zenoss'
failedFile = '/tools-export/scripts/Ruby/outputs/failed_vms_for_zenoss'

#Prompt for AD Pass and verify it
adPassAsk = ask("Please enter you AD Password") { |q| q.echo="*"}
#verify AD password
adPass = verifyAD_Pass(`hostname`.chomp, executeUser, adPassAsk)

if opts[:all_pods] == true
  clear_line
  print '[ ' + 'INFO'.green + " ] Gathering list of pods"
  podList
  clear_line
  print '[ ' + 'INFO'.green + " ] List of pods gathered"
end

unless opts[:pods].nil?
  opts[:pods].each do |x|
    @podList.push x
  end
end

#remove any duplicates that might of been added
@podList.uniq!

#Gathering list of vms
unless @podList.nil?
  @podList.each do |pod|
    podSubnet = pod.to_i * 2
    vcenter = "10.#{podSubnet}.3.2"
    clear_line
    print '[ ' + 'INFO'.green + " ] Logging into #{vcenter} to get list of vRealms"

    #Connecting to vCenter
    begin
      vim = RbVmomi::VIM.connect :host => vcenter, :user => adUser, :password => adPass, :insecure => true
      dc = vim.serviceInstance.find_datacenter
      list_vms(dc.vmFolder)
      clear_line 
      print '[ ' + 'INFO'.green + " ] Logging out of #{vcenter}"
      vim.close
    rescue
        clear_line
        puts '[ ' + 'ERROR'.red + " ] Failed to login to #{vcenter}"
        require 'pry';binding.pry
    end #end of begin
  end #end of @podList
end #unless #podList.nil?

unless @vms.nil?
  @vms.each do |vm|
    port_check(vm, 22)
  end #@vms.each
end #unless @vms.nil

unless @successList.nil? || @successList.empty?
  f = File.open(successFile, 'w')
  @successList.each do |vm|
    f.puts(vm)
  end #@successList.each
  f.close
  clear_line
  puts '[ ' + 'INFO'.green + " ] List of VMs has been generated and is located at #{successFile}"
end #unless @successList.nil?


unless @failedList.nil? || @failedList.empty?
  f = File.open(failedFile, 'w')
  @failedList.each do |vm|
    f.puts(vm)
  end #@successList.each
  f.close
  puts '[ ' + 'WARN'.yellow + " ] List of VMs that could not be accessed has been generated and is located at #{failedFile}"
end #unless @successList.nil?