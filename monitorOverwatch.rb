#!/usr/bin/env ruby
# Script to monitor overwatch zed ID

require 'rest-client'
require 'json'
require 'trollop'
require 'mail'
require 'active_support/time'
require_relative '/home/nholloway/scripts/Ruby/functions/format.rb'
require_relative '/home/nholloway/scripts/Ruby/functions/password_functions.rb'
require_relative '/home/nholloway/scripts/Ruby/functions/rbvmomi_methods.rb'

#params
opts = Trollop::options do
  opt :zed_id, "Zombie Action ID to monitor", :type => :string, :required => true
  opt :email, "Email address you would like alerts to be sent to", :type => :string, :required => true
  opt :log_level, "Level of logs", :type => :string, :required => false, :default => 'INFO'
  opt :check_min, "The length of time in between checks in minutes", :type => :int, :required => false, :default => 15
  opt :check_vcenter, "Set to true if you would like to monitor maintenance mode tasks in vCenter", :type => :boolean, :required => false, :default => false
  opt :vrealm, "Needed only if check-vcenter is set to true", :type => :string, :required => false
end

#validation
Trollop::die :vrealm, "Must enter a vrealm if check_vcenter is true" if (opts[:check_vcenter] == true) && (opts[:vrealm_given].nil?)

#functions
def send_email (email, zaid, status)
  to_email = email
  from_email= 'linjump@mail.vca.vmware.com'
  subject = "Zombie Action #{zaid}"
  content_type = 'text/html; charset=UTF-8'
  if status == 'failed'
    email_body = "Zombie Action ID: #{zaid} has issues. Please check now"
  elsif status == 'starting'
    email_body = "Started monitoring of Zombie Action ID: #{zaid}."
  elsif status == 'maint'
    email_body = "Detected a long running maintenance mode on Zombe Action ID: #{zaid}"
  else
    email_body = "Zombie Action ID: #{zaid} has been completed. Good Job!"
  end

  Mail.deliver do
    to "#{to_email}"
    from "#{from_email}"
    subject "#{subject}"
    content_type "#{content_type}"
    body "#{email_body}"
  end
end

#variables
ad_user = 'AD\\' + `whoami`.chomp
script_name = 'monitorOverwatch.rb'
check_length = opts[:check_min] * 60
vcenter = opts[:vrealm] + mgmt-vc0

#Get AD Pass if check_vcdtner is true
if opts[:check_vcenter]
  ad_pass = get_adPass
end

#logging
logger = config_logger(opts[:log_level].upcase, script_name)

#options to log Level
logger.info "INFO - opts: #{opts}"
logger.info "INFO - User: #{ad_user}"

#get zombie instance_id
begin
  results = RestClient::Request.execute(method: :get, url: "http://10.2.3.35:8080/engine_zapi/v1/zed/action/instance/#{opts[:zed_id]}?details=true",
    headers: {accept: 'application/json'})  
rescue => e
  clear_line
  logger.info "ERROR - Could not get Zombie Action ID: #{opts[:zed_id]}. Error message below."
  logger.info "ERROR - #{e.message}"
  puts '[ ' + 'ERROR'.red + " ] Could not get Zombie Action ID: #{opts[:zed_id]}. Error message below."
  puts e.message
  exit
end

clear_line
logger.info "INFO - Got the zombie instance id. Gathering status"
print '[ ' + 'INFO'.white + " ] Got the zombie instance id. Gathering status"

resultsJSON = JSON.parse(results);
resultsSTR = results.to_s;
failedResults = resultsSTR.scan(/failure/)
overall_status = resultsJSON['response']['entity']['status']
overall_result = resultsJSON['response']['entity']['result']

send_email(opts[:email], opts[:zed_id], 'starting')

until (overall_status == 'complete') && (overall_result == 'success') do
  ctime = `date +%H:%M`
  if failedResults.empty?
    clear_line
    logger.info "INFO - No failures detected."
    print '[ ' + 'INFO'.white + " ] No failures detected."
  else
    clear_line
    logger.info "INFO - Failures detected. Sending email"
    print '[ ' + 'INFO'.white + " ] Failures detected. Sending email"
    
    send_email(opts[:email], opts[:zed_id], 'failed')

    clear_line
    logger.info "INFO - Email Sent."
    print '[ ' + 'INFO'.white + " ] Email Sent."
  end

  #check vCenter if email was not already sent out and is set to true
  if (opts[:vcenter]) && (failedResults.empty?)
    clear_line
    logger.info "INFO - Checking #{opts[:vrealm]} for enter maintenance mode tasks"
    print '[ ' + 'INFO'.white + " ] Checking #{opts[:vrealm]} for enter maintenance mode tasks"

    #connect to vCenter and get tasks
    vim = connect_viserver(vcenter, ad_user, ad_pass)
    dc = vim.serviceInstance.find_datacenter
    tasks = get_tasks(vim, dc, 'children', 100)

    #select only maintenance mode tasks
    maint = tasks.select { |task| (task[:descriptionId] == 'HostSystem.enterMaintenanceMode') && (task[:state] != 'success')};

    unless maint.empty?
      send_maint_email = false
      go through each 
      maint.each do |task|
        if task[:startTime] < (Time.now - opts[:check_min].minutes)
          send_maint_email = true
        end
      end
      #send email if needed
      if send_maint_email
        clear_line
        logger.info "INFO - Found long running maintenance mode. Sending email"
        print '[ ' + 'INFO'.white + " ] Found long running maintenance mode. Sending email"
        send_email(opts[:email], opts[:zed_id], 'maint')
      end
    end
    vim.close
  end
  #sleep for specified minuntes
  clear_line
  logger.info "INFO - Sleeping for #{opts[:check_min]} minutes. Time of last check #{ctime}"
  print '[ ' + 'INFO'.white + " ] Sleeping for #{opts[:check_min]} minutes. Time of last check #{ctime}"

  sleep(check_length)
  clear_line
  logger.info "INFO - Getting results again from zombie"
  print '[ ' + 'INFO'.white + " ] Getting results again from zombie"

  results = RestClient::Request.execute(method: :get,
    url: "http://10.2.3.35:8080/engine_zapi/v1/zed/action/instance/#{opts[:zed_id]}?details=true",
    headers: {accept: 'application/json'})  

  resultsJSON = JSON.parse(results);
  resultsSTR = results.to_s;
  failedResults = resultsSTR.scan(/failure/)
  overall_status = resultsJSON['response']['entity']['status']
  overall_result = resultsJSON['response']['entity']['result']
end

send_email(opts[:email], opts[:zed_id], 'success')
clear_line
logger.info "INFO - Zombie Action ID Completed"
print '[ ' + 'INFO'.green + " ] Zombie Action ID Completed"
