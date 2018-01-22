#!/usr/bin/env ruby
#script to test the API on each NSP

require 'rest-client'
require 'json'
require 'net/ssh'

require_relative '/home/nholloway/scripts/Ruby/functions/format.rb'
require_relative '/home/nholloway/scripts/Ruby/functions/password_functions.rb'

#functions
def get_sys_sum(vm, user, password)
  begin
    response = RestClient::Request.execute(method: :post, url: "https://#{vm}:9443/api/1.0/appliance-management/jsonrpc/summary",
      headers: {accept: 'application/json', content_type: 'application/json'},
      payload: {'method' => 'getSystemSummary', 'id' => 'getSystemSummary'}.to_json,
      verify_ssl: false,
      user: user,
      password: password
    )
    $success.push(vm)
    return JSON.parse(response)
  rescue => e
    puts 'Failed to connect to NSP API. Please see below error message.'
    puts e
    $failed.push(vm)
  end
end

def get_comp_sum(vm, user, password)
  begin
    response = RestClient::Request.execute(method: :post, url: "https://#{vm}:9443/api/1.0/appliance-management/jsonrpc/summary",
      headers: {accept: 'application/json', content_type: 'application/json'},
      payload: {'method' => 'getComponentsSummary', 'id' => 'getComponentsSummary'}.to_json,
      verify_ssl: false,
      user: user,
      password: password
    )
    $success.push(vm)
    return JSON.parse(response)
  rescue => e
    puts 'Failed to connect to NSP API for #{vm}. Please see below error message.'
    puts e
    $failed.push(vm)
  end
end

#variables
vms = []
$failed = []
$success = []
ad_pass = get_adPass

#get nsp vms from file
file = File.new('/tools-export/Scripts/Ruby/outputs/vmList', 'r')
while (line = file.gets)
  if line =~ /nsp/
    vms.push(line)
  end
end
file.close

#remove newline characgters
vms.map! { |x| x.chomp }


#get paswword for each NSP VM, test pass via SSH, then connect to API
vms.each do |vm|
  #get-password begin
  begin
    ssh_pass = get_password(ad_pass, "admin@#{vm}", 'prod')
  rescue
    clear_line
    print '[ ' + 'INFO'.yellow + " ] Could not get password from Secret Server for #{vm}."
    clear_line
    ssh_pass = 'm0n3yb0vin3'
  end

  #test ssh
  verify_ssh_pass(vm, 'admin', ssh_pass)

  #test api call
  get_sys_sum(vm, 'admin', ssh_pass)
  get_comp_sum(vm, 'admin', ssh_pass)
end #vms.each

#failed vms
puts '[ ' + 'INFO'.white + " ] Failed list:"
puts $failed


#success list
puts '[ ' + 'INFO'.white + " ] Succdess list"
puts $success