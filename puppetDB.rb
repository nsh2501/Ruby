#!/usr/bin/env ruby
require 'rest-client'
require 'json'
require 'trollop'
require 'colorize'
require 'pp'
require_relative "/home/nholloway/scripts/Ruby/functions/podlist.rb"

#options
opts = Trollop::options do
opt :count, "Will give a count of all VMs in each pod that are in puppetDB", :required => false
opt :get_old, "Will print out a list of nodes that have not checked in, in the last 24 hours", :required => false
opt :print_failed, "Prints out a list of all puppet agent runs that failed on the last run", :required => false
opt :query, "Query string for puppetDB. Example '{\"query\": [\"~\", \"certname\", \"d0p1v5mgmt-vccmt0\"]}'", :type => :string, :require => false
opt :endpoint, "Endpoint to run the query. Example nodes", :type => :string, :required => false
opt :pods, "list of pods to check. Example d0p1 d0p2", :type => :strings, :required => false
opt :rpm_name, "List all versions of a RPM. Example: vmware-vcloud-director", :type => :string, :required => false
opt :lower_than, "List all rpms lower than a specific version. Example: 8.7.1", :type => :string, :required => false
opt :all_pods, "Use this option to include the full podList", :required => false
opt :uptime_hours, "Use this option to search for all systems that have been up greater then this lenght of time. Example 2400", :required => false, :type => :integer
opt :print, "Tells method to print all results. Example: false", :require => false, :type => :boolean, :default => true
opt :certname, "For valid option will limit the query to search for a certname provided. Examples: d0p9v53 or d0p9v54mgmt-vcd-a", :type => :string, :required => false
end

def clear_line ()
print "\r"
print "                                                                                                                   "
print "\r"
end

def pupdb_query(podID, endpoint, query)
  begin
    RestClient::Request.execute(method: :post, url: "https://#{podID}oss-mgmt-puppetdb.prod.vpc.vmw:8081/pdb/query/v4/#{endpoint}",
      headers: {accept: 'application/json', content_type: 'application/json'},
      payload: "#{query}",  
      ssl_ca_file: "/home/nholloway/puppetCerts/#{podID}-ca.pem",
      ssl_client_cert: OpenSSL::X509::Certificate.new(File.read("/home/nholloway/puppetCerts/#{podID}-cert.pem")),
      ssl_client_key: OpenSSL::PKey::RSA.new(File.read("/home/nholloway/puppetCerts/#{podID}-key.pem"))
    )
  rescue => e
    e
  end
end

def print_failed(podID)
begin
  query = '{"query": ["=", "latest_report_status", "failed"]}'
  failedNodes = RestClient::Request.execute(method: :post, url: "https://#{podID}oss-mgmt-puppetdb.prod.vpc.vmw:8081/pdb/query/v4/nodes",
    headers: {accept: 'application/json', content_type: 'application/json'},
    payload: "#{query}",  
    ssl_ca_file: "/home/nholloway/puppetCerts/#{podID}-ca.pem",
    ssl_client_cert: OpenSSL::X509::Certificate.new(File.read("/home/nholloway/puppetCerts/#{podID}-cert.pem")),
    ssl_client_key: OpenSSL::PKey::RSA.new(File.read("/home/nholloway/puppetCerts/#{podID}-key.pem"))
  )
rescue => e
  puts e
end
failedNodes = JSON.parse(failedNodes)
failedNodes.each do |node|
  begin
    query = '{"query": ["and", ["=", "latest_report?", true], ["=", "certname", "' + node['certname'] + '"]]}'
    reports = RestClient::Request.execute(method: :post, url: "https://#{podID}oss-mgmt-puppetdb.prod.vpc.vmw:8081/pdb/query/v4/reports",
      headers: {accept: 'application/json', content_type: 'application/json'},
      payload: "#{query}",  
      ssl_ca_file: "/home/nholloway/puppetCerts/#{podID}-ca.pem",
      ssl_client_cert: OpenSSL::X509::Certificate.new(File.read("/home/nholloway/puppetCerts/#{podID}-cert.pem")),
      ssl_client_key: OpenSSL::PKey::RSA.new(File.read("/home/nholloway/puppetCerts/#{podID}-key.pem"))
    )
  rescue => e
    puts e
  end
  reports = JSON.parse(reports)
  unless reports.nil? || reports.empty?
    reports.each do |report|
      puts "#{report['certname']}"
        unless report['resource_events']['data'].nil? || report['resource_events']['data'].empty?
        report['resource_events']['data'].each do |event|
          unless event['message'].nil? || event['message'].empty?
            puts event['message']
          end
        end
      end
    end 
  else
    puts 'could not find error message'
  end
end 
end

def get_old(podID)
query = nil
yesterday = (DateTime.now - 1).to_time
begin
  nodes = RestClient::Request.execute(method: :post, url: "https://#{podID}oss-mgmt-puppetdb.prod.vpc.vmw:8081/pdb/query/v4/nodes",
    headers: {accept: 'application/json', content_type: 'application/json'},
    payload: "#{query}",  
    ssl_ca_file: "/home/nholloway/puppetCerts/#{podID}-ca.pem",
    ssl_client_cert: OpenSSL::X509::Certificate.new(File.read("/home/nholloway/puppetCerts/#{podID}-cert.pem")),
    ssl_client_key: OpenSSL::PKey::RSA.new(File.read("/home/nholloway/puppetCerts/#{podID}-key.pem"))
  )
rescue => e
  puts e
end
oldArray = {}
nodes = JSON.parse(nodes)
nodes.each do |x|
  unless x['report_timestamp'].nil?
    rtime = Time.parse(x['report_timestamp'])
    if yesterday > rtime
      oldArray["#{x['certname']}"] = "#{x['report_timestamp']}"
    end
  end
  if x['report_timestamp'].nil?
    oldArray["#{x['certname']}"] = "Nil Timestamp"
  end
end
  oldArray
end

#variables
domain = ENV["HOSTNAME"].split(".")[1]
if opts[:pods].nil?
podList = f_pod_list(domain)
else
podList = opts[:pods]
end

if opts[:count] == true
total = 0
podList.each do |pod|
  count = JSON.parse(pupdb_query(pod, 'nodes', ' ')).count
  puts "#{pod} - #{count}"
  total += count
end
puts "Total Count: #{total}"
end

if opts[:get_old] == true
  oldArray = {}
  podList.each do |pod|
    clear_line
    print '[ ' + 'INFO'.green + " ]Checking #{pod} for nodes that have not checked in in the last 24 hours"
    tArray = get_old(pod)
    unless tArray.empty?
      oldArray = tArray.merge(oldArray)
    end
  end
  puts "\n\n"
  pp oldArray
  puts "\n"
  puts '[ ' + 'INFO'.green + " ] Total number of nodes that haven't checked in, in the last day: #{oldArray.count}"
end

if opts[:print_failed] == true
  podList.each do |pod|
    puts '[ ' + 'INFO'.green + " ] Checking #{pod} for failed nodes"
    print_failed(pod)
  end
end

unless opts[:query].nil?
  podList.each do |pod|
    puts '[ ' + 'INFO'.green + " ] Running query on #{pod}"
    results = JSON.parse(pupdb_query(pod, opts[:endpoint], opts[:query]))
    puts JSON.pretty_generate(results)
  end
end

unless opts[:rpm_name].nil?
rpm_results = []
if opts[:certname].nil?
  query = '{"query": ["=", "path", ["rpms", "' + opts[:rpm_name] + '"]]}'
else
  query = '{"query": ["and", ["~", "certname", "' + opts[:certname] + '"], ["=", "path", ["rpms", "' + opts[:rpm_name] + '"]]]}'
end
endpoint = 'fact-contents'
podList.each do |pod|
  rpm_results += JSON.parse(pupdb_query(pod, endpoint, query))
end
if rpm_results.nil? || rpm_results.empty?
  puts "No results came from the below query"
  puts query
else
  rpm_versions = {}
  rpm_results.each do |line|
    rpm_versions["#{line['certname']}"] = line['value']
  end
  if opts[:lower_than].nil?
    pp rpm_versions
  else
    rpm_master_ver = Gem::Version.new(opts[:lower_than])
    rpm_lower = {}
    rpm_versions.each do |hname, version|
      rpm_version = Gem::Version.new(version)
      if rpm_version < rpm_master_ver
        rpm_lower[hname] = version
      end
    end
    if rpm_lower.empty?
      puts '[ ' + 'INFO'.green + " ] No VMs found with a lower version"
    else
      pp rpm_lower
    end
  end
end
end

unless opts[:uptime_hours].nil?
if opts[:certname].nil?
  query = '{"query": [">=", "value", ' + "#{opts[:uptime_hours]}" + ']}"'
else
  query = '{"query": ["and", ["~", "certname", "' + "#{opts[:certname]}" + '"], [">=", "value", ' + "#{opts[:uptime_hours]}" + ']]}"'
end
endpoint = 'facts/uptime_hours'
podArray = {}
total_count = 0
podList.each do |pod|
  clear_line
  print '[ ' + 'INFO'.green + " ] Running query against #{pod}"
  results = JSON.parse(pupdb_query(pod, endpoint, query))
  unless results.nil?
    podArray[pod] = "#{results.count}"
    total_count += results.count
    array = {}
    results.each do |line|
      array["#{line['certname']}"] = "#{line['value']}"
    end
    if opts[:print] == true
      puts ''
      pp array
      puts ''

    end
  end
end
clear_line
podArray['Total'] = total_count
pp podArray
end




















