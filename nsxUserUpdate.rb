#!/usr/bin/env ruby
require 'highline/import'
require 'nokogiri'
require 'rest-client'
require 'trollop'
require 'colorize'
require 'syslog/logger'
require 'rbvmomi'
require 'net/ssh'

#personal functions
require_relative "/home/nholloway/scripts/Ruby/functions/get_password.rb"

#pid
pid = Process.pid

opts = Trollop::options do
  #parameters
  opt :vrealms, "vRealm to update the NSX User. Ex: dXpYvZ", :type => :strings, :required => false
  opt :pods, "List of pods to update user in NSX for all vRealms", :type => :ints, :required => false
  opt :user, "The user you want to uddate. Default systems@ad.prod.vpc.vmw", :type => :string, :required => false, :default => 'systems@ad.prod.vpc.vmw'
  opt :role, "The Role you want to set the user to", :type => :string, :required => false, :default => 'enterprise_admin'
end

#methods
def rest_session(url, user, password)
  session = RestClient::Resource.new(url,
  :user => user,
  :password => password,
  :verify_ssl  => OpenSSL::SSL::VERIFY_NONE,
  :headers     => { :content_type => 'application/xml'})

  return session
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

def clear_line ()
  print "\r"
  print "                                                                                                                   "
  print "\r"
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
script_name = 'nsxUserUpdate'
logger = Syslog::Logger.new script_name
logger.level = Kernel.const_get 'Logger::INFO'
logger.info "INFO - Logging initalized. User: #{executeUser}"
puts "[ " + "INFO".green + " ] Logging started search #{script_name}[#{pid}] in /var/log/messages for logs."

#variables
vrealms = []
@vms = []
capUser = 'cap-p1osswinjump'
capPass = get_password('d0p1oss-mgmt-winjump',capUser)
capUser.concat "@ad.prod.vpc.vmw"

#get list of pods if pods is specified
unless opts[:pods].nil?
  verifyAD_Pass('d0p1oss-mgmt-linjump', capUser, capPass)
  opts[:pods].each do |pod|
    podSubnet = pod.to_i * 2
    vcenter = "10.#{podSubnet}.3.2"
    clear_line
    print '[ ' + 'INFO'.green + " ] Logging into #{vcenter} to get a list of vRealms"
    logger.info "INFO - Logging into #{vcenter} to get a list of vRealms"
    #connect to vCenter
    vim = RbVmomi::VIM.connect :host => vcenter, :user => capUser, :password => capPass, :insecure => true

    #get datacenter
    dc = vim.serviceInstance.find_datacenter

    list_vms(dc.vmFolder)

    vim.close    
  end #opts[:pods].each do |pod|
  @vms.each do |vm|
    vrealms.push vm.split("m")[0]
  end #@vms.each do |vm|
end #unless opts[:pods].nil?

unless opts[:vrealms].nil?
  opts[:vrealms].each do |vrealm|
    vrealms.push vrealm
  end #opts[:vrealms].each do |vrealm|
end #unless opts[:vrealms].nil?

#get rid of any duplicates in vRealms 
vrealms.uniq!

#foreach vRealm
vrealms.each do |vrealm|
  #variables
  nsxAccess = 'false'
  nsxName = "#{vrealm}mgmt-vsm0"
  nsxUser = opts[:user]
  adminPass = get_password(nsxName, 'admin')
  baseUrl = "https://#{nsxName}/api/2.0/services/usermgmt"

  #get session for user
  userUrl = baseUrl.clone
  userUrl.concat "/user/#{nsxUser}"
  userSession = rest_session(userUrl, 'admin', adminPass)

  #Get User
  clear_line
  print '[ ' + 'INFO'.green + " ] Attempting to connect to #{nsxName}"
  logger.info "INFO - Attempting to connect to #{nsxName}"
  loopBreak = 'false'
  while (nsxAccess == 'false' && loopBreak == 'false')
    begin
      userApi = userSession.get
      clear_line
      print '[ ' + 'INFO'.green + " ] Successfully logged into #{nsxName}"
      logger.info "INFO - Successfully logged into #{nsxName}"
      nsxAccess = 'true'
    rescue => e
      if ! e.class =~ 'SocketError'
        if e.response.include? '402'
          clear_line
          print '[ ' + 'INFO'.green + " ] User: #{user} not found on NSX Manager: #{nsxName}"
          nsxUser = ask("Please enter a new user")
          userSession = rest_session(userUrl, 'admin', adminPass)
        elsif e.response.include? '403'
          clear_line
          print '[ ' + 'INFO'.green + " ] Could not login with the Password provided on #{nsxName}"
          clear_line
          adminPass = ask("Please enter the Admin password for #{nsxName}") { |q| q.echo="*"}
          userSession = rest_session(userUrl, 'admin', adminPass)
        else
          puts '[ ' + 'ERROR'.red + " ] Unkown error occured on #{nsxName}. Please look at below error code and try again"
          logger.info "ERROR - Unkown error occured. Please look at below error code and try again. #{e}"
          require 'pp';pp e
        end
      else
        clear_line
        puts '[ ' + 'WARN'.yellow + " ] Unkown error on #{nsxName}:"
        pp e
        loopBreak = 'true'
      end
    end
  end

  if loopBreak == 'false'
    unless userApi.nil? || userApi.nil?
      #build role session
      roleUrl = baseUrl.clone
      roleUrl.concat "/role/#{nsxUser}"
      roleSession = rest_session(roleUrl, 'admin', adminPass)

      #Get Role
      clear_line
      print '[ ' + 'INFO'.green + " ] Getting NSX Role for user #{nsxUser} on #{nsxName}"
      logger.info "INFO - Getting NSX Role for user #{nsxUser}"
      roleApi = roleSession.get
      roleXml = Nokogiri::XML(roleApi)
      role = roleXml.xpath("//role").text
      updateRole = opts[:role]

      #if role is not equal to enerprise_admin update it
      if role == updateRole
        clear_line
        print '[ ' + 'INFO'.green + " ] Role is already set to #{updateRole} on #{nsxName}"
        logger.info "INFO - Role is already set to #{updateRole}"
        updateRole = 'false'
      else
        clear_line
        print '[ ' + 'INFO'.green + " ] Role is set to #{role}. Updating to #{updateRole}"
        roleXml.at("//role").content = updateRole
        updateRole = 'true'
      end

      clear_line
      print '[ ' + 'INFO'.green + " ] Updating Role for user #{nsxUser}"
      logger.info "INFO - Updating Role for user #{nsxUser}"
      begin
        roleSession.put(roleXml.to_xml)
        clear_line
        print '[ ' + 'INFO'.green + " ] Role updated successfully"
        logger.info "INFO - Role updated successfully"
      rescue => e
        puts '[ ' + 'ERROR'.red + " ] Unknown error on #{nsxName}. Please see error response below. Going to next vRealm"
        logger.info "ERROR - Unknown error on #{nsxName}. Please see error response below. #{e}"
        require 'pp';pp e
      end
    end
  end
end

clear_line
puts '[ ' + 'INFO'.green + " ] No more vRealms to check. Script completed."
logger.info "INFO - No more vRealms to check"
