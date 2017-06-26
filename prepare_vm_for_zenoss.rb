#!/usr/bin/env ruby
#This script will attempt to log into each VM, add the zenmonitor user (if not already added), configure sshd if necessary, and configure sudoers 

require 'net/ssh'
#require 'tiny_tds'
require 'colorize'
require 'trollop'
require 'vmware_secret_server'
require 'highline/import'
require 'net/scp'
require 'rbvmomi'

require_relative '/home/nholloway/scripts/Ruby/functions/get_password.rb'
require_relative '/home/nholloway/scripts/Ruby/functions/format.rb'

#options
opts = Trollop::options do 
  opt :vmregex, 'Regex. Example: (d0p1v\d+-mgmt-vcd-[a-f])|(oss-mgmt-puppet)', :type => :string, :required => false
  opt :vms, "List of VMs that you would like to run this against", :type => :strings, :requred => false
  opt :user, "The user to log into the server with. All servers must use the same user", :type => :string, :required => false, :default => 'root'
  opt :verify_only, "Switch. Use this option if you do not want to make any changes on the server", :type => :boolean, :required => false, :default => false
  opt :no_ssh, "Switch. Set this option if you need to use the console to turn on root ssh access", :type => :boolean, :required => false, :default => false
  opt :vcenter, "Specify vCenter of VMs if using no_ssh option. Example: tlm or oss", :type => :string, :required => false
end

if opts[:vmregex].nil? && opts[:vms].nil?
  puts '[ ' + 'ERROR'.red + " ] You must specify either --vmregex or --vms on the command line."
  exit
end

if !opts[:vmregex].nil? && !opts[:vms].nil?
  puts '[ ' + 'ERROR'.red + " ] You must specify either --vmregex or --vms on the command line."
  exit
end

if !opts[:no_ssh_given].nil? && opts[:vcenter].nil?
  puts '[ ' + 'ERROR'.red + " ] You must specify vcenter type when giving the no-ssh option"
  exit
end

#functions 
def ssh_exec!(ssh, command)
  stdout_data = ""
  stderr_data = ""
  exit_code = nil
  exit_signal = nil
  ssh.open_channel do |channel|
    channel.exec(command) do |ch, success|
      unless success
        abort "FAILED: couldn't execute command (ssh.channel.exec)"
      end
      channel.on_data do |ch,data|
        stdout_data+=data
      end

      channel.on_extended_data do |ch,type,data|
        stderr_data+=data
      end

      channel.on_request("exit-status") do |ch,data|
        exit_code = data.read_long
      end

      channel.on_request("exit-signal") do |ch, data|
        exit_signal = data.read_long
      end
    end
  end
  ssh.loop
  [stdout_data, stderr_data, exit_code, exit_signal]
end

def vms_from_file(file, vmregex)
  #gather vms from file 
  vms_array = File.readlines(file)
  vms_array.map! { |line| line.chomp }

  #only get vms that match regex
  vms = vms_array.select do |vm|
    vm.match(vmregex)
  end
  return vms
end

def py_query(user, password, host, database, vmregex)
  client = TinyTds::Client.new username: user, password: password, host: host, database: database, timeout: 90

  #get the session id
  result = client.execute("SELECT TOP 5 id from [Py_collect].sessions order by id desc")
  results = result.each(:symbolize_keys => true, :as => :array, :cache_rows => true, :empty_sets => true) do |rowset| end
  id = results[1][0]

  #get vms from tlm and oss-mgmt-puppet
  tlm_result = client.execute("SELECT name FROM [Py_collect].inv_vsphere_vm WHERE session_id = '#{id}' AND vcenter LIKE '%tlm-mgmt%' AND power_state = 'poweredOn' AND name NOT LIKE '%vc0%'")
  tlm_results = tlm_result.each(:symbolize_keys => true, :as => :array, :cache_rows => true, :empty_sets => true) do |rowset| end

  oss_result = client.execute("SELECT name FROM [Py_collect].inv_vsphere_vm WHERE session_id = '#{id}' AND vcenter LIKE '%oss-mgmt%' AND power_state = 'poweredOn' AND name NOT LIKE '%vc0%'")
  oss_results = oss_result.each(:symbolize_keys => true, :as => :array, :cache_rows => true, :empty_sets => true) do |rowset| end

  #close sql connection
  client.close

  #combine arrays
  db_results = tlm_results.concat oss_results

  #get results that match regex passed ind
  regex_match = []
  db_results.each do |vm|
    if vm[0] =~ vmregex
      regex_match.push vm[0]
    end
  end

  unless regex_match.empty?
    return regex_match
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
        pass = ask("Please enter your AD Password") { |q| q.echo="*"}
    end
  end


  return pass
end

def verify_vm_password(user, vm, password)
  begin
    session = Net::SSH.start(vm, user, :password => password, :auth_methods => ['password'], :number_of_password_prompts => 0)
  rescue => e
    clear_line
    puts '[ ' + 'ERROR'.red + " ] Failed to login to #{vm} with password in secret server"
    puts e
    raise 'FAILED'
  end
  if session.nil?
    clear_line
    puts '[ ' + 'ERROR'.red + " ] Could not login with password with password. Please verify password in Secret Server and try again."
    raise 'FAILED'
  else
    return 'SUCCESS'
  end
end

def check_os(vm, user, password)
  Net::SSH.start(vm, user, :password => password, :auth_methods => ['password'], :number_of_password_prompts => 0) do |ssh|
    verify_centos = "cat /etc/redhat-release | awk \'{print $1}\'"
    result = ssh_exec!(ssh, verify_centos)
    unless result[0].chomp == 'CentOS'
      verify_suse = "head -n1 /etc/SuSE-release | awk '{print $1}'"
      result = ssh_exec!(ssh, verify_suse)
    end
  
    if result[0].chomp != 'CentOS' && result[0].chomp != 'SUSE'
      clear_line
      puts '[ ' + 'ERROR'.red + " ] Could not determine the OS. Skipping this VM."
      raise 'ERROR'
    else
      return result[0].chomp
    end
  end
end

def sshd_config_chk(user, vm, password, os, verify_only)
  Net::SSH.start(vm, user, :password => password, :auth_methods => ['password'], :number_of_password_prompts => 0) do |ssh|
    if os == 'CentOS'
      verify_version_cmd = 'cat /etc/redhat-release'
      result = ssh_exec!(ssh, verify_version_cmd)
      os_version = result[0].scan(/\d+/)[0]
      if os_version != 7
        restart_sshd_cmd = 'service sshd restart'
      else
        restart_sshd_cmd = 'systemctl restart sshd.service'
      end  
    else
      restart_sshd_cmd = 'service sshd restart'
    end
    if user == 'root'
      verify_sshd_maxsession_cmd = 'grep -q \'^MaxSessions\' /etc/ssh/sshd_config'
      remove_line_sshd_cfg = 'sed -i \'/^MaxSessions/d\' /etc/ssh/sshd_config'
    else
      verify_sshd_maxsession_cmd = 'sudo grep -q \'^MaxSessions\' /etc/ssh/sshd_config'
      remove_line_sshd_cfg = 'sudo sed -i \'/^MaxSessions/d\' /etc/ssh/sshd_config'
      restart_sshd_cmd = 'sudo ' + restart_sshd_cmd
    end

    result = ssh_exec!(ssh, verify_sshd_maxsession_cmd)
    if result[2] != 0
      clear_line
      print '[ ' + 'INFO'.green + " ] SSHD config is correct."
      return 'SUCCESS'
    end

    if verify_only == true
      clear_line
      puts '[ ' + 'WARN'.yellow + " ] SSHD config needs to be modified on #{vm}"
      raise 'FAILED'
    end

    clear_line
    print '[ ' + 'INFO'.green + " ] Removing MaxSessions from sshd_config"
    result = ssh_exec!(ssh, remove_line_sshd_cfg)
    if result[2] == 0
      clear_line
      print '[ ' + 'INFO'.green + " ] Successfully removed MaxSessions from sshd_confg. Restarting service"
    else
      clear_line
      puts '[ ' + 'ERROR'.red + " ] Failed to remove line from sshd_config on #{vm}. Please see below error"
      puts result
      raise 'FAILED'
    end

    clear_line
    print '[ ' + 'INFO'.green + " ] Restarting sshd now."
    result = ssh_exec!(ssh, restart_sshd_cmd)
    if result[2] == 0
      clear_line
      print '[ ' + 'INFO'.green + " ] Successfully restarted sshd."
      return 'SUCCESS'
    else
      clear_line
      puts '[ ' + 'ERROR'.red + " ] Failed to restart sshd"
      raise 'FAILED'
    end
  end
end

def verify_puppet(user, vm, password)
  Net::SSH.start(vm, user, :password => password, :auth_methods => ['password'], :number_of_password_prompts => 0) do |ssh|
    clear_line
    print '[ ' + 'INFO'.green + " ] Verifying if Ops puppet is installed/configured on #{vm}."
    if user == 'root'
      verify_puppet = 'grep -q -i PuppetCodeVer /etc/issue'
    else
      verify_puppet = 'sudo grep -q -i PuppetCodeVer /etc/issue'
    end
    result_cmd = ssh_exec!(ssh, verify_puppet)
    if result_cmd[2] == 0
      clear_line
      puts '[ ' + 'INFO'.green + " ] Puppet found on #{vm}. Skipping the other checks."
      raise 'true'
    else
      clear_line
      print '[ ' + 'INFO'.green + " ] Puppet not found on #{vm}. Continuing with other checks"
      return 'false'
    end
  end
end

def zenmonitor_user (user, vm, password, zen_password, verify_only)
  add_user = false
  Net::SSH.start(vm, user, :password => password, :auth_methods => ['password'], :number_of_password_prompts => 0) do |ssh|
    #verify if zenmonitor user exists and create it if necessary
    clear_line
    print '[ ' + 'INFO'.green + " ] Verifying if the user zenmonitor exists."
    verify_zenmonitor = 'grep -q -i zenmonitor /etc/passwd'
    if user != 'root'
      verify_zenmonitor = 'sudo ' + verify_zenmonitor
    end
    result_cmd = ssh_exec!(ssh, verify_zenmonitor)
    if result_cmd[2] == 0
      clear_line
      print '[ ' + 'INFO'.green + " ] zenmonitor user exists on server"
    else
      clear_line
      print '[ ' + 'INFO'.green + " ] zenmonitor needs to be added on server"
      add_user = true
    end

    if verify_only == false && add_user == true
      clear_line
      print '[ ' + 'INFO'.green + " ] Adding zenmonitor user"
      #add user
      add_zenmonitor_cmd = 'adduser zenmonitor'
      result = ssh_exec!(ssh, add_zenmonitor_cmd)
      if result[2] == 0
        clear_line
        print '[ ' + 'INFO'.green + " ] Zenmonitor user successfully added."
      else
        clear_line
        puts '[ ' + 'ERROR'.red + " ] Failed to add zenmonitor user. Error was #{result[0]}"
        raise 'FAILED'
      end
      #set password
      set_pass_cmd = "echo #{zen_password} | passwd --stdin zenmonitor"
      result = ssh_exec!(ssh, set_pass_cmd)
      if result[2] == 0
        clear_line
        print '[ ' + 'INFO'.green + " ] Successfully set password for zenmonitor"
      else
        clear_line
        puts '[ ' + 'WARN'.yellow + " ] Failed to set password on #{vm} for user zenmonitor but will continue"
      end
    end
  end
  return 'SUCCESS'
end

def sudo_installed(user, vm, password, os, verify_only)
  Net::SSH.start(vm, user, :password => password, :auth_methods => ['password'], :number_of_password_prompts => 0) do |ssh|
    clear_line
    print '[ ' + 'INFO'.green + " ] Checking to see if sudo package is installed"
    if user == 'root'
      verify_sudo_cmd = 'rpm -qa | grep -i sudo'
      install_sudo_cmd = 'yum install -y sudo'
    else
      verify_sudo_cmd = 'sudo rpm -qa | grep -i sudo'
      install_sudo_cmd = 'sudo yum install -y sudo'
    end
    result = ssh_exec!(ssh, verify_sudo_cmd)

    if result[2] == 0
      clear_line
      print '[ ' + 'INFO'.green + " ] Sudo is installed"
      return 'TRUE'
    else
      if verify_only != true
        clear_line
        print '[ ' + 'INFO'.green + " ] Sudoers is not installed"
        if os == 'CentOS'
          clear_line
          print '[ ' + 'INFO'.green + " ] Installing sudo now."
          result = ssh_exec!(ssh, install_sudo_cmd)
          if result[2] == 0
            clear_line
            print '[ ' + 'INFO'.green + " ] Successfully installed Sudo"
            return 'TRUE'
          else
            clear_line
            puts '[ ' + 'ERROR'.red + " ] Ran into below error when installing sudo on #{vm}"
            puts "#{result}"
            raise 'FALSE'
          end
        else
          clear_line
          puts '[ ' + 'ERROR'.red + " ] SUDO is not installed on #{vm}. This script only supports auto installs on CentOS."
          raise 'FALSE'
        end
      else
        clear_line
        puts '[ ' + 'WARN'.yellow + " ] Sudo not installed #{vm} and verify only set to true."
        return 'FALSE'
      end
    end
  end
end

def sudo_config(user, vm, password, os, verify_only)
  Net::SSH.start(vm, user, :password => password, :auth_methods => ['password'], :number_of_password_prompts => 0) do |ssh|
    clear_line
    print '[ ' + 'INFO'.green + " ] Verifying sudoers config on #{vm}"
    if user == 'roo'
      sudoers_cmd = 'grep -q ^#includedir /etc/sudoers.d' + ' /etc/sudoers'
      add_sudoers_cmd = 'echo \'#includedir /etc/sudoers.d\' | tee -a /etc/sudoers'

    else
      sudoers_cmd = 'sudo grep -q ^#includedir /etc/sudoers.d' + ' /etc/sudoers'
      add_sudoers_cmd = 'echo \'#includedir /etc/sudoers.d\' | sudo tee -a /etc/sudoers'
    end
    result = ssh_exec!(ssh, sudoers_cmd)
    if result[2] == 0
      clear_line
      print '[ ' + 'INFO'.green + " ] Sudoers Config File looks good"
      return 'SUCCESS'
    else
      if verify_only == false
        clear_line
        print '[ ' + 'INFO'.green + " ] Sudoers config not found. Adding line to config file"
        result = ssh_exec!(ssh, add_sudoers_cmd)
        if result[2] == 0
          clear_line
          print '[ ' + 'INFO'.green + " ] Successfully added sudoers config"
          return 'SUCCESS'
        else
          clear_line
          puts '[ ' + 'ERROR'.red + " ] Failed to modify sudoers config. Below is the error messages"
          puts result
          raise 'FAILED'
        end
      else
        clear_line
        puts '[ ' + 'WARN'.yellow + " ] Sudoers config not correct on #{vm}. Not correcting as verify_only option set"
        raise 'FAILED'
      end
    end
  end
end

def zen_sudo_cfg(user, vm, password, os, verify_only, zen_md5sum, zen_sudo_cfg_source_file)
  Net::SSH.start(vm, user, :password => password, :auth_methods => ['password'], :number_of_password_prompts => 0) do |ssh|
    clear_line
    print '[ ' + 'INFO'.green + " ] Verifying sudo config for user zenmonitor"

    #verify user == root else use sudo commands
    if user == 'root'
      verify_zen_cfg = 'md5sum /etc/sudoers.d/25_zenmonitor | awk \'{print $1}\''
      create_folder = 'mkdir -p /etc/sudoers.d; chown root:root /etc/sudoers.d; chmod 550 /etc/sudoers.d/'
      update_perm_zen_cfg = 'chown root:root /etc/sudoers.d/25_zenmonitor; chmod 440 /etc/sudoers.d/25_zenmonitor'
    else
      verify_zen_cfg = 'sudo md5sum /etc/sudoers.d/25_zenmonitor | awk \'{print $1}\''
      create_folder = 'sudo mkdir -p /etc/sudoers.d;sudo chown root:root /etc/sudoers.d;sudo chmod 550 /etc/sudoers.d/'
      update_perm_zen_cfg = 'sudo chown root:root /etc/sudoers.d/25_zenmonitor;sudo chmod 440 /etc/sudoers.d/25_zenmonitor'
    end

    #run command
    result = ssh_exec!(ssh, verify_zen_cfg)

    #check to see if md5sum matches the one on file
    if result[0].chomp == zen_md5sum
      clear_line
      print '[ ' + 'INFO'.green + " ] User zenmonitor config is correct"
      return 'SUCCESS'
    else
      if verify_only == true
        clear_line
        puts '[ ' + 'WARN'.yellow + " ] Zenmonitor sudo config not correct on #{vm}. Not fixing as verify_only is set"
        raise 'FAILED'
      else
        clear_line
        #create folder
        ssh_exec!(ssh, create_folder)
        print '[ ' + 'INFO'.green + " ] Adding zenmonitor sudoers config."
        Net::SCP.start(vm, user, :password => password) do |scp|
          begin
            scp.upload! zen_sudo_cfg_source_file, '/etc/sudoers.d/25_zenmonitor'
            clear_line
            print '[ ' + 'INFO'.green + " ] Zenmonitor sudo config has been successfully uploaded"
            ssh_exec!(ssh, update_perm_zen_cfg)
            return 'SUCCESS'
          rescue => e
            clear_line
            puts '[ ' + 'WARN'.yellow + " ] Failed to upload zen monitor config on #{vm}. See error below"
            puts e
            raise 'FAILED'
          end
        end
      end
    end
  end
end

def zenmonitor_user(user, vm, password, zen_password, verify_only)
  Net::SSH.start(vm, user, :password => password, :auth_methods => ['password'], :number_of_password_prompts => 0) do |ssh|
    #variables
    add_zen_user = true
    set_user_pass = true

    if user == 'root'
      verify_zen_user_cmd = 'grep -q -i zenmonitor /etc/passwd'
      add_zen_user_cmd = 'useradd -s `which bash` -d /home/zenmonitor zenmonitor; echo \'' + zen_password + '\' | passwd --stdin zenmonitor; chage -M 99999 zenmonitor'
      create_dirs_cmd = 'mkdir -p /home/zenmonitor/.ssh;chown zenmonitor: -R /home/zenmonitor; chmod 700 /home/zenmonitor/.ssh'
    else
      verify_zen_user_cmd = 'sudo grep -q -i zenmonitor /etc/passwd'
      add_zen_user_cmd = 'sudo useradd -s `which bash` -d /home/zenmonitor zenmonitor; echo \'' + zen_password + '\' | sudo passwd --stdin zenmonitor;sudo chage -M 99999 zenmonitor'
      create_dirs_cmd = 'sudo mkdir -p /home/zenmonitor/.ssh;sudo chown zenmonitor: -R /home/zenmonitor;sudo chmod 700 /home/zenmonitor/.ssh'
    end

    result = ssh_exec!(ssh, verify_zen_user_cmd)

    if result[2] == 0
      clear_line
      print '[ ' + 'INFO'.green + " ] Zenmonitor user exists"
      add_zen_user = false
      return 'SUCCESS'
    end

    if verify_only == true
      if add_zen_user == true
        clear_line
        puts '[ ' + 'WARN'.yellow + " ] Zenmonitor user does not exist on #{vm} and will need to be added. Not performing this action as verify_only is set to true"
        raise 'FAILED'
      else
        return 'SUCCESS'
      end
    else
      if add_zen_user == false
        return 'SUCCESS'
      else
        clear_line
        print '[ ' + 'INFO'.green + " ] Adding zenmonitor user"
        result = ssh_exec!(ssh, add_zen_user_cmd)
        if result[2] == 0
          clear_line
          print '[ ' + 'INFO'.green + " ] User zenmonitor created successfully"
          ssh_exec!(ssh, create_dirs_cmd)
          return 'SUCCESS'
        else
          clear_line
          puts '[ ' + 'ERROR'.red + " ] Failed to add user zenmonitor on #{vm}. Please see below error"
          puts result
          raise 'FAILED'
        end
      end
    end
  end
end

def zen_ssh_key(user, vm, password, zen_pub_key, zen_pub_key_md5sum, verify_only)
  Net::SSH.start(vm, user, :password => password, :auth_methods => ['password'], :number_of_password_prompts => 0) do |ssh|
    add_zen_ssh_key = false
    md5sum_server = nil

    #check if authorized key file exists if so then get md5sum
    md5sum_cmd = 'md5sum /home/zenmonitor/.ssh/authorized_keys'
    result = ssh_exec!(ssh, md5sum_cmd)
    if result[2] == 0
      md5sum_server = result[0].split(' ')[0]
    end

    #check if md5sum matches from source file
    if md5sum_server == zen_pub_key_md5sum
      clear_line
      print '[ ' + 'INFO'.green + " ] md5sum matches source"
      return 'SUCCESS'
    else
      clear_line
      print '[ ' + 'WARN'.yellow + " ] md5sum does not match. Replacing file."
      add_zen_ssh_key = true
    end

    if verify_only == true
      clear_line
      puts '[ ' + 'WARN'.yellow + " ] Zenmonitor authorized_keys needs to be updated on #{vm}. No action being taken as verify_only is true"
      raise 'FAILED'
    end

    if add_zen_ssh_key == true
      Net::SCP.start(vm, user, :password => password) do |scp|
        begin
          scp.upload! zen_pub_key, '/home/zenmonitor/.ssh/authorized_keys'
          clear_line
          print '[ ' + 'INFO'.green + " ] File uploaded successfully. Modifying permissions now."
        rescue => e
          clear_line
          puts '[ ' + 'ERROR'.red + " ] Unknown error occured when performing scp on zenmonitor ssh key. Please see below error"
          puts e
          raise 'FAILED'
        end
        modify_perms = 'chmod 600 /home/zenmonitor/.ssh/authorized_keys'
        result = ssh_exec!(ssh, modify_perms)
        if result[2] == 0
          clear_line
          print '[ ' + 'INFO'.green + " ] Modified pemissions of zenmonitor ssh authorized keys folder"
          return 'SUCCESS'
        else
          clear_line
          puts '[ ' + 'ERROR'.red + " ] Failed to modify permissions on authorized keys folder for #{vm}. Please see belos."
          puts result
          raise 'FAILED'
        end
      end
    end
  end
end

def connect_viserver(viserver, user, password)
  begin
    vim = RbVmomi::VIM.connect :host => viserver, :user => user, :password => password, :insecure => true
    return vim
  rescue => e
    clear_line
    puts '[ ' + 'ERROR'.red + " ] Failed to log into #{viserver}. Please see below message"
    puts e.message
    raise 'FAILED'
  end
end

def list_vms(folder)
  children = folder.children.find_all
  children.each do |child|
    if child.class == RbVmomi::VIM::VirtualMachine
      if child.runtime.powerState == 'poweredOn'
        @vms.push child
        clear_line
        print "[ " + "INFO".green + " ] #{child.name} added to inventory"
      end
    elsif child.class == RbVmomi::VIM::Folder
      list_vms(child)
    end
  end
end

def vim_wait(vim, vm, auth, process)
  pid = process[:pid]
  while process[:exitCode].nil? do
    clear_line
    print '[ ' + 'INFO'.green + " ] Waiting for process to end. Sleeping 5 seconds"
    sleep(5)
    clear_line
    print '[ ' + 'INFO'.green + " ] Checking on process again"
    process = vim.serviceContent.guestOperationsManager.processManager.ListProcessesInGuest(:vm => vm, :auth => auth, :pids => [pid]).first
  end

  return process[:exitCode]
end

#verify if root user needs to be permitted to login via SSH
def verify_root_ssh(vim, vm, auth)
  clear_line
  print '[ ' + 'INFO'.green + " ] Checking to see if root_ssh is disabled"

  #create spec to run command
  spec = { :programPath => '/bin/grep', :arguments => '"^PermitRootLogin no" /etc/ssh/sshd_config' }

  #run command through GuestOps
  pid = vim.serviceContent.guestOperationsManager.processManager.StartProgramInGuest(:vm => vm, :auth => auth, :spec => spec)

  #list process of command and get exit code
  process = vim.serviceContent.guestOperationsManager.processManager.ListProcessesInGuest(:vm => vm, :auth => auth, :pids => [pid]).first

  exit_code = vim_wait(vim, vm, auth, process)

  if exit_code == 0 
    return 'DISABLED'
  else
    return 'ENABLED'
  end
end

#set PermitRootLogin to yes in sshd_config and restart sshd
def config_root_ssh(vim, vm, auth, state)
  clear_line
  print '[ ' + 'INFO'.green + " ] Configuring root ssh access. Setting to state #{state}."
  if state == 'enabled'
    programpath = '/bin/sed'
    arguments = '-i \'s/\(^PermitRootLogin no\)/PermitRootLogin yes/g\' /etc/ssh/sshd_config'
  elsif state == 'disabled'
    programpath = '/bin/sed'
    arguments = '-i \'s/\(^PermitRootLogin yes\)/PermitRootLogin no/g\' /etc/ssh/sshd_config'
  else
    clear_line
    puts '[ ' + 'ERROR'.red + " ] Invalid state set for configure_root_ssh. State: #{state}"
    raise 'ERROR'
  end
  spec = { :programPath => programpath, :arguments => arguments }

  #run command through GuestOps
  pid = vim.serviceContent.guestOperationsManager.processManager.StartProgramInGuest(:vm => vm, :auth => auth, :spec => spec)  

  #list process of command and get exit code
  process = vim.serviceContent.guestOperationsManager.processManager.ListProcessesInGuest(:vm => vm, :auth => auth, :pids => [pid]).first

  exit_code = vim_wait(vim, vm, auth, process)

  #restart sshd
  print '[ ' + 'INFO'.green + " ] Restarting the sshd service"
  spec = { :programPath => '/sbin/service', :arguments => 'sshd restart' }

  #run command through GuestOps
  pid = vim.serviceContent.guestOperationsManager.processManager.StartProgramInGuest(:vm => vm, :auth => auth, :spec => spec)  

  #list process of command and get exit code
  process = vim.serviceContent.guestOperationsManager.processManager.ListProcessesInGuest(:vm => vm, :auth => auth, :pids => [pid]).first

  exit_code = vim_wait(vim, vm, auth, process)

  if exit_code == 0
    clear_line
    print '[ ' + 'INFO'.green + " ] Succesfully restart SSHD"
    return 'SUCCESS'
  else
    clear_line
    puts '[ ' + 'ERROR'.red + " ] Failed to succesfully restart sshd on #{vm}."
    raise 'ERROR'
  end
end

#validate guest os credentials
def verify_user_creds(vim, vm, auth)
  begin
    #receives error if creds are wrong, otherwise returns nil
    vim.serviceContent.guestOperationsManager.authManager.ValidateCredentialsInGuest(:vm => vm, :auth => auth)
    clear_line
    print '[ ' + 'INFO'.green + " ] Credentials are valid on #{vm.name}"
    return 'SUCCESS'
  rescue => e
    clear_line
    puts '[ ' + 'ERROR'.red + " ] Failed to validate credentials on #{vm.name}. Please see below error message."
    puts e.message
    raise 'ERROR'
  end
end

#variables
sqluser = 'dbmonitor'
sqlpass = 'Gqt51093g8'
sqlhost = 'd0p1tlm-opsrep'
sqldb = 'py_collector'
runuser = `whoami`.chomp
localVM = ENV['HOSTNAME']
domain = localVM.split('.')[1]
full_domain = localVM.split('.')[1..-1].join('.')
numbers = localVM.scan(/\d+/)
ad_pass_ask = ask("Enter the AD password for the user #{runuser}: ") { |q| q.echo="*"};
adPass = verifyAD_Pass(localVM, runuser, ad_pass_ask)
zen_sudo_md5sum = '8f76df75ff79d3a278ea1289f65dc60c'
zen_password = 'pae4daiv3zahW'
vm_user = opts[:user]
vm_input_file = '/tools-export/scripts/Ruby/outputs/vmList'
zen_sudo_cfg_source_file = '/home/nholloway/scripts/Ruby/files/25_zenmonitor'
podlist = []
#setting root_ssh_enable to false so script does not try to set it back to false
root_ssh_enable = false

#determine environment and correct ssh key
case domain
  when 'psd'
    zen_pub_key = '/home/nholloway/scripts/Ruby/files/psd_zen.pub'
    zen_pub_key_md5sum = `md5sum #{zen_pub_key}`
    zen_pub_key_md5sum = zen_pub_key_md5sum.chomp.split(' ')[0]
  when 'prod'
    zen_pub_key = '/home/nholloway/scripts/Ruby/files/prod_zen.pub'
    zen_pub_key_md5sum = `md5sum #{zen_pub_key}`
    zen_pub_key_md5sum = zen_pub_key_md5sum.chomp.split(' ')[0]
  when 'stage'
    zen_pub_key = '/home/nholloway/scripts/Ruby/files/stage_zen.pub'
    zen_pub_key_md5sum = `md5sum #{zen_pub_key}`
    zen_pub_key_md5sum = zen_pub_key_md5sum.chomp.split(' ')[0]
  when 'se'
    zen_pub_key = '/home/nholloway/scripts/Ruby/files/int_zen.pub'
    zen_pub_key_md5sum = `md5sum #{zen_pub_key}`
    zen_pub_key_md5sum = zen_pub_key_md5sum.chomp.split(' ')[0]
else
  puts '[ ' + 'ERROR'.red + " ] Do not recognize environment #{domain}"
  exit
end


#if vmregex option get list of servers from py_collector otherwise get list of servers that were put in on the command line
if opts[:vmregex].nil?
  vm_list = opts[:vms]
else
  vmregex = Regexp.new opts[:vmregex]
    vm_list = vms_from_file(vm_input_file, vmregex)
end

if vm_list.nil? || vm_list.empty?
  clear_line
  puts '[' + 'WARN'.yellow + "[ No VMs in the array. If using a regex please verify the regex"
else
  #get list of pods
  vm_list.each do |vm|
    numbers = vm.scan(/\d+/)
    podlist.push "d#{numbers[0]}p#{numbers[1]}"
  end

  #remove any duplicates in podlist
  podlist.uniq!

  podlist.each do |pod| 

    #connect to vCenter and get list of VM's if no_ssh is specified
    if opts[:no_ssh_given]
      vcenter = pod + opts[:vcenter] + '-mgmt-vc0'
      
      #connect to tlm and oss vcenters
      begin
        vim = connect_viserver(vcenter, "AD\\#{runuser}", adPass)
        vi_connect = 'SUCCESS'
      rescue
        vi_connect = 'FAILED'
      end
      next if vi_connect.match('FAILED')

      #get list of vms
      dc = vim.serviceInstance.find_datacenter
      @vms = []
      list_vms(dc.vmFolder)
      vim_vms = @vms.clone
      @vms = []
    end

    #get list of vm's for each pod
    pod_vm_list = vm_list.select { |x| x.match(/#{pod}/) }

    pod_vm_list.each do |vm|
      vmname = vm.split('.')[0]
      secret = opts[:user] + '@' + vmname

      begin
        #verify if password is in secret server
        ss_password = get_password(adPass, secret, domain)

        #use GuestOps (console) if no_ssh is set
        if opts[:no_ssh_given]
          #build guest os creds
          auth = RbVmomi::VIM::NamePasswordAuthentication ({
            :interactiveSession => false,
            :username => opts[:user],
            :password => ss_password 
          })

          vim_vm = vim_vms.find { |x| x.name.match(/^#{vm}$/) }
          if vim_vm.nil?
            clear_line
            puts '[ ' + 'ERROR'.red + " ] Did not find a vm matching #{vm} in #{vcenter}"
          end
          next if vim_vm.nil?
          verify_user_creds(vim, vim_vm, auth)
          root_ssh_enabled = verify_root_ssh(vim, vim_vm, auth)
          if root_ssh_enabled == 'DISABLED'
            if opts[:verify_only]
              clear_line
              puts '[ ' + 'WARN'.yellow + " ] Root Login disabled. Not enabling as verify_only is set"
              raise 'FAILED'
            else
              clear_line
              print '[ ' + 'INFO'.green + " ] Root login disabled. Enabling now"
              root_ssh_enable = config_root_ssh(vim, vim_vm, auth, 'enabled')
            end
          end
        end

        #verify password in secret server works on server
        vm_con = verify_vm_password(vm_user, vmname, ss_password)

        #verify if Ops Puppet server is installed 
        puppet_configured = verify_puppet(vm_user, vmname, ss_password)

        #verify OS of VM
        os = check_os(vm, vm_user, ss_password)

        #verify sshd
        sshd_config_result = sshd_config_chk(vm_user, vm, ss_password, os, opts[:verify_only])

        #verify sudo is installed and install it if necessary
        sudoers = sudo_installed(vm_user, vm, ss_password, os, opts[:verify_only])

        #verify sudo config
        sudo_cfg = sudo_config(vm_user, vm, ss_password, os, opts[:verify_only])

        #verify/add zenmonitor config
        zen_cfg_result = zen_sudo_cfg(vm_user, vm, ss_password, os, opts[:verify_only], zen_sudo_md5sum, zen_sudo_cfg_source_file)

        #verify zenmonitor user/password/ssh keys
        zen_user_result = zenmonitor_user(vm_user, vm, ss_password, zen_password, opts[:verify_only])

        #connect to zenmonitor via ssh and verify/add authorized keys file
        zen_ssh_key_result = zen_ssh_key('zenmonitor', vm, zen_password, zen_pub_key, zen_pub_key_md5sum, opts[:verify_only])

        clear_line
        puts '[ ' + 'INFO'.green + " ] #{vm} is ready for zenoss"
      rescue => e 
        #no rescue code needed at this moment
      ensure 
        #ensure root ssh login is disabled if it was enabled
        if root_ssh_enable == 'SUCCESS'
          clear_line
          print '[ ' + 'INFO'.green + " ] Setting root ssh to disabled on #{vm}"
          config_root_ssh(vim, vim_vm, auth, 'disabled')
        end
      end
    end
    clear_line  
    puts '[ ' + 'INFO'.green + " ] Completed all VM's in #{pod}"
  end
end









