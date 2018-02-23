#!/usr/bin/env ruby

#this script will accept a list of vRealms and then get each resource pool and 'monitor' it from the database
require 'trollop'
require 'base64'
require 'json'
require 'rest-client'
require 'sqlite3'


require_relative '/home/nholloway/scripts/Ruby/functions/format.rb'
require_relative '/home/nholloway/scripts/Ruby/functions/password_functions.rb'
require_relative '/home/nholloway/scripts/Ruby/functions/rbvmomi_methods.rb'
require_relative '/home/nholloway/scripts/Ruby/functions/zenoss_events.rb'

#Trollop options
opts = Trollop::options do
  #opt :vrealms, "List of vRealms to monitor", :type => :strings, :required => true
  opt :log_level, "Log level to output", :type => :string, :requried => false, :default => 'INFO'
end

#trollop die statements
#opts[:vrealms].each do |vrealm|
#  Trollop::die :vrealm, "vRealm must be in dXpYvZ format" unless /^d\d+p\d+v\d+$/.match(vrealm)
#end
Trollop::die :log_level, "Must be set to INFO or DEBUG" unless /(INFO|DEBUG)/.match(opts[:log_level])

#db_functions
def db_new(db_location)
  db = SQLite3::Database.new db_location
  return db
end

def db_create_active_alarms(db_location)
  db = SQLite3::Database.new db_location
  rows = db.execute <<-SQL
    CREATE TABLE active_alarms (
      name varchar(255),
      vcenter varchar(50),
      cpu_allocation int
    );
  SQL
end

def db_query(db, name)
  query = "SELECT * FROM active_alarms WHERE name = \'#{name}\'"
  rows = db.execute(query)
  return rows
end

def db_insert(db, name, vcenter, cpu_allocation)
  db.execute("INSERT INTO active_alarms (name, vcenter, cpu_allocation) VALUES (?, ?, ?)", ["#{name}", "#{vcenter}", cpu_allocation])
end

def db_delete(db, name)
  db.execute("DELETE FROM active_alarms WHERE name = ?", ["#{name}"])
end

#variables
script_name = 'monitor_cpu_alloc_rps.rb'
rsps_prop = %w(name config.cpuAllocation)
rsp_matches = []
rsp_not_found = []
cpu_allocation_not_unlimited = []
cpu_allocation_unlimited = []
domain = ENV['HOSTNAME'].split('.')[1]
full_domain = domain + '.vpc.vmw'
db_location = '/home/nholloway/scripts/Ruby/databases/active_alerts.db'
@rsp_master_list = []

#configure logging
$logger = config_logger(opts[:log_level], script_name)

#vcenter list
$logger.info "INFO - Domain: #{domain}"
if domain == 'prod'
  @ad_user = 'AD\cap-p1osswinjump'
  @ad_pass = 'e$1*n3$Q4'
  auth = 'Basic ' + Base64.encode64( 'secret-systems:eeCair6Mu3mie0ahphup' ).chomp
  zenoss_url = 'https://zenoss5.d0p1oss-zenoss-ccenter-gom.prod.vpc.vmw/zport/dmd/evconsole_router'
  vcenter_list = %w(d3p4v8mgmt-vc0 d7p7v27mgmt-vc0 d7p7v37mgmt-vc0 d7p7v13mgmt-vc0 d7p7v14mgmt-vc0 d7p7v20mgmt-vc0 d2p13v17mgmt-vc0 d2p13v16mgmt-vc0)

  #resource pool list prod
  rsp_list = []
  rsp_list.push('PFE-EXCHANGE-VA1 (753dfe29-fce6-48fa-9a88-7beabda4a959)')
  rsp_list.push('PFE-EXCHANGE-NJ1 (819b53c2-48ed-46b3-a0b8-99ec3ba78ce7)')
  rsp_list.push('HCX-IX')
  rsp_list.push('MIT-NJ-DEVTEST (0e328ed4-c473-44a1-84e2-196006b28b99)')
  rsp_list.push('MIT-NJ-PROD (b9e2b22a-6124-48d8-8f53-b45727d488b6)')
  rsp_list.push('MIT-EXP (5d656449-6cb5-41dc-b9a2-fe8039b8678e)')
  rsp_list.push('MIT-CA-2 (83468dd1-a553-4f14-a717-0c29293f3a20)')
  rsp_list.push('MIT-CA-1 (20c34676-5591-4958-8db8-a0c7cacb44cb)')
elsif domain == 'stage'
  @ad_user = 'AD\\' + `whoami`.chomp
  @ad_pass = get_adPass
  auth = 'Basic ' + Base64.encode64( 'secret-systems:M0n3yb0vin3!' ).chomp
  zenoss_url = 'https://zenoss5.d2p2oss-zenoss-ccenter-us-west.stage.vpc.vmw/zport/dmd/evconsole_router'
  vcenter_list = %w(d2p2v13mgmt-vc0 d2p2tlm-mgmt-vc0 d2p2oss-mgmt-vc0 d2p2v14mgmt-vc0 d2p2v1mgmt-vc0 d2p2v12mgmt-vc0)

  #resource pool list stage
  rsp_list = ['System vDC (82b82863-abe4-42a1-a3a5-1ba3ea4b0c94)']
else
  $logger.info "ERROR - Could not determine domain. Domain: #{domain}"
  clear_line
  puts '[ ' + 'ERROR'.red + " ] Could not determine domain. Domain: #{domain}"
end

$logger.info "INFO - Script Options passed: vCenters: #{vcenter_list}"
$logger.info "INFO - Resource Pool #{rsp_list}"

#actions to perform for each vCenter
vcenter_list.each do |vcenter|
  clear_line
  print '[ ' + 'INFO'.white + " ] Connecting to vCenter: #{vcenter}"
  $logger.info "INFO - Connecting to vCenter #{vcenter}"
  vim = connect_viserver(vcenter, @ad_user, @ad_pass)
  rsps = get_resource_pool(vim, rsps_prop)
  rsps.each do |rsp|
    name = rsp.propSet.find { |prop| prop.name == 'name' }.val
    cpu_alloc = rsp.propSet.find { |prop| prop.name == 'config.cpuAllocation' }.val.limit
    hash = {'vcenter' => vcenter, 'name' => name, 'cpu_alloc' => cpu_alloc }
    @rsp_master_list.push(hash)
  end
  vim.close
  clear_line
  print '[ ' + 'INFO'.white + " ] Done collecting Resource Pools from #{vcenter}"
  $logger.info "INFO - Done collecting Resource Pools from #{vcenter}. Found #{rsps.count} Resource Pools." 
end

#find all resource pools 
clear_line
print '[ ' + 'INFO'.white + " ] Gathering list of Resource Pools that match list"
$logger.info "INFO - Gathering list of Resource Pools that match list"

rsp_list.each do |resource|
  x = @rsp_master_list.find { |rsp| rsp["name"] == resource }
  if (x)
    rsp_matches.push(x)
  else
    rsp_not_found.push(x)
  end
end

#build list of all Resource Pools not set to unlimted
clear_line
print '[ ' + 'INFO'.white + " ] Find all Resource pools that are not set to Unlimited"
$logger.info "INFO - Find all Resource pools that are not set to Unlimited"
cpu_allocation_not_unlimited = rsp_matches.select { |rsp| rsp["cpu_alloc"] != -1 }

#build list that are not alarming
cpu_allocation_unlimited = rsp_matches.select { |rsp| rsp["cpu_alloc"] == -1 }

#send to zenoss for each resource pool that is not set to unlimited
cpu_allocation_not_unlimited.each do |rsp|
  vcenter = rsp['vcenter'] + '.' + full_domain
  summary = 'CPU Allocation not set to unlimited: KB-XXXXX'
  component = rsp['name']
  evclasskey = 'KeyText'
  evclass = '/vSphere'
  zen_alert_add(auth, 5, vcenter, summary, component, evclasskey, evclass)
end


#check database and update if needed
#create db if needed
db_create_active_alarms(db_location) unless File.exists?(db_location)

#initialize database
db = db_new(db_location)

#go through each one that is alaraming and udpate if necessary
cpu_allocation_not_unlimited.each do |rsp|
  name = rsp['name']
  vcenter = rsp['vcenter']
  cpu_allocation = rsp['cpu_alloc']
  query = db_query(db, name)
  #if query is empty insert into it, else perform an update
  if query.empty?
    db_insert(db, name, vcenter, cpu_allocation)
  end
end

#remove all entries that are in DB that do not currently have an alarm
cpu_allocation_unlimited.each do |rsp|
  name = rsp['name']
  vcenter = rsp['vcenter']
  cpu_allocation = rsp['cpu_alloc']
  query = db_query(db, name)
  #if query return results update Zenoss and DB
  unless query.empty?
    vcenter = rsp['vcenter'] + '.' + full_domain
    summary = 'CPU Allocation not set to unlimited: KB-XXXXX'
    component = rsp['name']
    evclasskey = 'KeyText'
    evclass = '/vSphere'
    zen_alert_add(auth, 0, vcenter, summary, component, evclasskey, evclass)

    #remove from DB
    db_delete(db, name)
  end
end