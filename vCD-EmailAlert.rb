#!/usr/bin/env ruby
#this script can be used to remove/change the alerting email from vCloud-Director under the Administrator tab

require 'vcd_functions'
require 'trollop'
require 'nokogiri'
require 'rbvmomi'
require 'syslog/logger'
require 'net/ssh'

#procss ID
pid = Process.pid

#command line options
opts = Trollop::options do
  opt :vrealms, "vRealms to modify the email in vCD. Example: dXpYvZ dXpYvZ", :type => :strings, :required => false
  opt :pods, "List of pods to modify the emails in vCD. Example: 1 10 6", :type => :ints, :required => false
  opt :user, "User to use when logging into the vCloud Director. Defaults to linjump user. Example: nholloway", :type => :string, :required => true
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

#configure logging
executeUser = `whoami`.chomp
script_name = 'vCD-EmailAlert.rb'
logger = Syslog::Logger.new script_name
logger.level = Kernel.const_get 'Logger::INFO'
logger.info "INFO - Logging initalized. User: #{executeUser}"
puts "[ " + "INFO".green + " ] Logging started search #{script_name}[#{pid}] in /var/log/messages for logs."

#Prompt for AD Pass and verify it
adPassAsk = ask("Please enter you AD Password") { |q| q.echo="*"}

#verify AD password
adPass = verifyAD_Pass(`hostname`.chomp, opts[:user], adPassAsk)

=begin
#create session
session = Vcd_functions::Session.new('d2p3v8', opts[:user])

#login to session
response = session.login
if response.code != '201'

#get email settings
email_set = session.get('/admin/extension/settings/email');
emailXML = Nokogiri::XML(email_set);

emailXML.at("//vmext:AlertEmailTo").content = ''
=end
