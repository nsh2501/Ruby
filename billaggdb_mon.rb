#!/usr/local/bin/ruby
#script to check billagg DB 

#functions 
require 'pg'
require 'date'

#variables
error_found = false
yesterday = Time.now - 86400

#connect to DB
begin
  conn = PG::Connection.open(:dbname => 'billing', :host => '10.2.3.126', :user => 'billing', :password => 'vmware')

  #get results
  qresult = conn.exec_params('select subscription_id, report_begin, report_end, status_id from subscriptions where subscription_id in (422,423,424)')

  #find any subscriopts that are aborted
  unless error_found
    #find any subscriptions that are set to aborted status
    aborted_status = qresult.select { |result| result['status_id'] == '8' }

    #if found then set error_found to true
    unless aborted_status.empty?
      error_found = true
    end
  end

  #if still no errors verify dates on each one to make sure not more than 1 day behind
  unless error_found
    qresult.each do |result|
      report_end = DateTime.parse(result['report_end']).to_time
      if yesterday > report_end
        error_found = true
      end
    end
  end
rescue =>e 
  puts 'Critical Could not connect to Database or something'
  exit 2
end

#if errors found exit with 1 else exit 0
if error_found
  puts 'Critical'
  exit 2
else
  puts 'OK'
end  