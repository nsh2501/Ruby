#!/usr/bin/env ruby
# Script to monitor overwatch zed ID

require 'rest-client'
require 'json'
require 'trollop'
require 'mail'
require_relative '/home/nholloway/scripts/Ruby/functions/format.rb'

#params
opts = Trollop::options do
  opt :zed_id, "Zombie Action ID to monitor", :type => :string, :required => true
  opt :email, "Email address you would like alerts to be sent to", :type => :string, :required => true
  opt :log_level, "Level of logs", :type => :string, :required => false, :default => 'INFO'
  opt :check_min, "The length of time in between checks in minutes", :type => :int, :required => false, :default => 15
end

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

if (overall_status == 'complete') && (overall_result == 'success')
  send_email(opts[:email], opts[:zed_id], 'success')
  clear_line
  logger.info "INFO - Zombie Action ID Completed"
  print '[ ' + 'INFO'.green + " ] Zombie Action ID Completed"
  exit
end

until (overall_status == 'complete') && (overall_result == 'success') do
  ctime = `date +%H:%M`
  if failedResults.empty?
    clear_line
    logger.info "INFO - No failures detected. Sleeping for #{opts[:check_min]} minutes."
    print '[ ' + 'INFO'.white + " ] No failures detected. Sleeping for #{opts[:check_min]} minutes. Time of last check #{ctime}"
  else
    clear_line
    logger.info "INFO - Failures detected. Sending email"
    print '[ ' + 'INFO'.white + " ] Failures detected. Sending email"
    
    send_email(opts[:email], opts[:zed_id], 'failed')

    clear_line
    logger.info "INFO - Email Sent. Sleeping for #{opts[:check_min]} minutes."
    print '[ ' + 'INFO'.white + " ] Email Sent. Sleeping for #{opts[:check_min]} minutes. Time of last check #{ctime}"
  end
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
