#!/usr/bin/env ruby

require 'highline/import'
require 'net/ssh'
require 'trollop'
require 'colorize'
require 'json'
require 'rest-client'
require 'pg'


require_relative '/home/nholloway/scripts/Ruby/functions/format.rb'
require_relative '/home/nholloway/scripts/Ruby/functions/password_functions.rb'
require_relative '/home/nholloway/scripts/Ruby/functions/rbvmomi_methods.rb'
require_relative '/home/nholloway/scripts/Ruby/functions/vcenter_list_v2.rb'
require_relative '/home/nholloway/scripts/Ruby/functions/podlist.rb'

#cli params
opts = Trollop::options do
  opt :vrealms, "vRealms to run the presto update on", :type => :strings, :required => false
  opt :pods, "Perform update on all pods versus a single vRealm", :type => :ints, :required => false
  opt :all_pods, "Update presto for every component on all pods", :type => :boolean, :required => false, :default => false
  opt :target_nsx_version, "Target NSX Version. Example 6.2.8", :type => :string, :required => false, :default => '6.2.8'
  opt :target_nsx_build, "Target NSX build. Example 5901733", :type => :string, :required => false, :default => '5901733'
  opt :nsx_cpu_count, "Number of CPU's for NSX", :type => :string, :required => false, :default => '4'
  opt :nsx_cpu_core, "Number of CPU core's for NSX", :type => :string, :required => false, :default => '1.0'
  opt :nsx_mem, "Amount of memory for NSX", :type => :string, :required => false, :default => '16'
  opt :log_level, "Set level of logging", :type => :string, :required => false, :default => 'INFO'
  opt :presto_db, "VM Name for prestodb", :type => :string, :required => false, :default => 'd0p1tlm-prestodb-a'
  opt :verify_only, "If true will only verify and make no changes", :type => :boolean, :requied => false, :default => true
  opt :target_vcenter_build, "Target VC Build for VSUPG", :type => :string, :required => false, :default => '5318203'
  opt :target_esxi_build, "Target ESXI Build for VSUPG", :type => :string, :required => false, :default => '5572656'
  opt :daas_target_esxi_build, "Target DaaS ESXI Build for VSUPG", :type => :string, :required => false, :default => '5580970'
end

#trollop die conditions
Trollop::die :pods, "You can't specify pods option with vrealms" if opts[:pods_given] && opts[:vrealms_given]
Trollop::die :all_pods, "You can't specify all_pods option with vrealms" if opts[:all_pods_given] && opts[:vrealms_given]
Trollop::die :all_pods, "You can't specify all_pods option with pods" if opts[:all_pods_given] && opts[:pods_given]



#functions
def update_query(pg, logger, fqdn, table, id, column, value)
  clear_line
  logger.info "INFO - Updating Resource #{fqdn}, Column: #{column}, with #{value}"
  print '[ ' + 'INFO'.white + " ] Updating Resource #{fqdn}, Column: #{column}, with #{value}"

  #start the update
  begin
    update_query = pg.exec("UPDATE #{table} SET #{column} = '#{value}' WHERE id = '#{id}';")
    clear_line
    logger.info "INFO - Update Successful"
    print '[ ' + 'INFO'.white + " ] Update Successful"
  rescue => e
    clear_line
    logger.info "ERROR - Update failed for #{fqdn}, Column: #{column}, with #{value}"
    puts '[ ' + 'ERROR'.red + " ] Update failed for #{fqdn}, Column: #{column}, with #{value}"
  end
end

#variables
ad_user = 'AD\\' + `whoami`.chomp
user = `whoami`.chomp
ad_pass = get_adPass
script_name = 'updatePresto.rb'
domain = ENV['HOSTNAME'].split('.')[1]
db_port = 5432
db_name = 'presto_production'
db_user = 'postgres'
nsx_ver_relationship_id = "1108"
nsx_build_relationship_id = "1109"

#logging
logger = config_logger(opts[:log_level].upcase, script_name)

#script output if debug
logger.debug "DEBUG - opts: #{opts}"
logger.debug "DEBUG - ad_user: #{ad_user}"

#get list of VM's if pods or all_pods is true
if opts[:pods_given] || opts[:all_pods_given]
  clear_line
  print '[ ' + 'INFO'.white + " ] Gathering list of pods"
  logger.info "INFO - Gathering list of pods"
  if opts[:all_pods_given]
    pod_list = f_pod_list(domain)
  else
    all_pods = f_pod_list(domain)
    pod_list = []
    opts[:pods].each do |pod|
      match = all_pods.find { |x| x.match (/p#{pod}$/)}
      pod_list.push(match)
    end
  end

  logger.debug "DEBUG - List of pods. pod_list: #{pod_list}"
  logger.info "INFO - Gathering list of vRealms"
  clear_line
  print '[ ' + 'INFO'.white + " ] Gathering list of vRealms in pods specified"
  
  #get list of vcenters and convert to vRealms
  vrealm_list = f_get_vcenter_list(logger, pod: pod_list, ad_user: ad_user, ad_pass: ad_pass, type: 'vpc')
  #remove mght-vc0 fro vrealm_list
  vrealm_list.each { |vm| vm.gsub!('mgmt-vc0', '') }
  opts[:vrealms] = vrealm_list
  logger.debug "DEBUG - List of vrealms gathered. vrealms: vrealm_list"
end

#connecting to Presto db
clear_line
logger.info "INFO - Connecting to presto db on #{opts[:presto_db]}"
print '[ ' + 'INFO'.white + " ] Connecting to presto db on #{opts[:presto_db]}"
logger.debug "DEBUG - Presto db host: #{opts[:presto_d]}, Port: #{db_port}, DB name: #{db_name}, DB user: #{db_user}"

begin
  pg = PG::Connection.new(:host => opts[:presto_db], :port => db_port, :dbname => db_name, :user => db_user)
rescue => e
  clear_line
  puts '[ ' + 'ERROR'.red + " ] Failed to log into #{opts[:presto_db]}. Please see error message below"
  puts e.messabge
  exit
end

#check/update presto for each vrealm
opts[:vrealms].each do |vrealm|
  #update presto for each vrealm found
  clear_line
  logger.info "INFO - Gathering resources in presto for each vrealm #{vrealm}"
  print '[ ' + 'INFO'.white + " ] Gathering resources in presto for each vrealm #{vrealm}"

  #dynamic values for vrealm
  update_hash = {}
  vcenter_hostname = vrealm.gsub(/v\d+/, 'tlm-mgmt-vc0.prod.vpc.vmw')
  datacenter_name = vrealm.gsub(/v\d+/, '')
  cluster_name = vrealm.gsub(/v\d+/, 'mgmt')
  vcda_vm_name = vrealm + 'mgmt-vcd-a'
  vcdb_vm_name = vrealm + 'mgmt-vcd-b'
  vcddb_vm_name = vrealm + 'mgmt-vcddb'
  vcdnfs_vm_name = vrealm + 'mgmt-vcd-nfs'
  vsm_vm_name = vrealm + 'mgmt-vsm0'
  nsx_build = []
  nsx_ver = []

  rs = pg.exec("SELECT * FROM resources WHERE fqdn LIKE '%#{vrealm}%';")
  vcda = rs.select { |x| x['fqdn'].match(/#{vrealm}mgmt-vcd-a.prod.vpc.vmw$/) };
  vcdb = rs.select { |x| x['fqdn'].match(/#{vrealm}mgmt-vcd-b.prod.vpc.vmw$/) };
  vcddb = rs.select { |x| x['fqdn'].match(/#{vrealm}mgmt-vcddb.prod.vpc.vmw$/) };
  vcdnfs = rs.select { |x| x['fqdn'].match(/#{vrealm}mgmt-vcd-nfs.prod.vpc.vmw/) };
  vsm = rs.select { |x| x['fqdn'].match(/#{vrealm}mgmt-vsm0.prod.vpc.vmw/) };
  nspb = rs.select { |x| x['fqdn'].match(/#{vrealm}mgmt-nsp-b.prod.vpc.vmw/) };
  vsupg = rs.select { |x| x['fqdn'].match(/#{vrealm}mgmt-vc0-vsupg/) };

  #NSX Custom attributes
  rs_custom_attribute_values = pg.exec("SELECT * FROM custom_attribute_values WHERE instance_customizable_id = '#{vsm[0]['id']}'")

  unless rs_custom_attribute_values.count == 0
    nsx_build = rs_custom_attribute_values.select { |attribute| attribute['custom_attribute_relationship_id'] == nsx_build_relationship_id  }
    nsx_ver = rs_custom_attribute_values.select { |attribute| attribute['custom_attribute_relationship_id'] == nsx_ver_relationship_id  }
  end


  #if nspb is found then display warning
  unless nspb.empty?
    clear_line
    logger.info "WARN - Found nsp-b resource on #{vrealm}"
    puts '[ ' + 'WARN'.yellow + " ] Found nsp-b resource on #{vrealm}"
  end #end unless nspb.empty?

  #verifying info gathered
  clear_line
  logger.info "INFO - Checking values and updating where necessary for #{vrealm}"
  print '[ ' + 'INFO'.white + " ] Checking values and updating where necessary for #{vrealm}"
   
  #vcda
  if !vcda.empty?
    logger.debug "DEBUG - VCDA Resource: vcenter - #{vcda[0]['vcenter_hostname']}, Calculated #{vcenter_hostname}"
    logger.debug "DEBUG - VCDA Resource: Cluster - #{vcda[0]['cluster_name']}, Calculated #{cluster_name}"
    logger.debug "DEBUG - VCDA Resource: DataCenter - #{vcda[0]['datacenter_name']}, Calculated #{datacenter_name}"
    logger.debug "DEBUG - VCDA Resource: VM Name - #{vcda[0]['vm_name']}, Calculated #{vcda_vm_name}"
    if (vcda[0]['vcenter_hostname'] == vcenter_hostname) && (vcda[0]['datacenter_name'] == datacenter_name)  \
      && (vcda[0]['cluster_name'] == cluster_name) && (vcda[0]['vm_name'] == vcda_vm_name)
      clear_line
      logger.info "INFO - VCDA Resource matches - #{vrealm}"
      print '[ ' + 'INFO'.white + " ] VCD-a Resource is correct - #{vrealm}"
      update_hash[:vcda] = false
    else
      clear_line
      logger.info "INFO - VCDA Resource does not match - #{vrealm}"
      print '[ ' + 'INFO'.white + " ] VCDA Resource needs updating - #{vrealm}"
      update_hash[:vcda] = true
    end #if vcda
  else
    clear_line
    logger.info "ERROR - Could not find VCDA Resource on #{vrealm}"
  end

  #vcdb
  if !vcdb.empty?
    logger.debug "DEBUG - VCDB Resource: vcenter - #{vcdb[0]['vcenter_hostname']}, Calculated #{vcenter_hostname}"
    logger.debug "DEBUG - VCDB Resource: Cluster - #{vcdb[0]['cluster_name']}, Calculated #{cluster_name}"
    logger.debug "DEBUG - VCDB Resource: DataCenter - #{vcdb[0]['datacenter_name']}, Calculated #{datacenter_name}"
    logger.debug "DEBUG - VCDB Resource: VM Name - #{vcdb[0]['vm_name']}, Calculated #{vcdb_vm_name}"
    if (vcdb[0]['vcenter_hostname'] == vcenter_hostname) && (vcdb[0]['datacenter_name'] == datacenter_name)  \
      && (vcdb[0]['cluster_name'] == cluster_name) && (vcdb[0]['vm_name'] == vcdb_vm_name)
      clear_line
      logger.info "INFO - VCDB Resource matches - #{vrealm}"
      print '[ ' + 'INFO'.white + " ] VCDB Resource is correct - #{vrealm}"
      update_hash[:vcdb] = false
    else
      clear_line
      logger.info "INFO - VCDB Resource does not match - #{vrealm}"
      print '[ ' + 'INFO'.white + " ] VCDB Resource needs updating - #{vrealm}"
      update_hash[:vcdb] = true
    end #if vcdb
  else
    clear_line
    logger.info "ERROR - Could not find VCDB Resource on #{vrealm}"
  end

  #vcddb
  if !vcddb.empty?
    logger.debug "DEBUG - VCDDB Resource: vcenter -  #{vcddb[0]['vcenter_hostname']}, Calculated #{vcenter_hostname}"
    logger.debug "DEBUG - VCDDB Resource: Cluster -  #{vcddb[0]['cluster_name']}, Calculated #{cluster_name}"
    logger.debug "DEBUG - VCDDB Resource: DataCenter -  #{vcddb[0]['datacenter_name']}, Calculated #{datacenter_name}"
    logger.debug "DEBUG - VCDDB Resource: VM Name -  #{vcddb[0]['vm_name']}, Calculated #{vcddb_vm_name}"
    if (vcddb[0]['vcenter_hostname'] == vcenter_hostname) && (vcddb[0]['datacenter_name'] == datacenter_name)  \
      && (vcddb[0]['cluster_name'] == cluster_name) && (vcddb[0]['vm_name'] == vcddb_vm_name)
      clear_line
      logger.info "INFO - VCDDB Resource matches - #{vrealm}"
      print '[ ' + 'INFO'.white + " ] VCDDB Resource is correct - #{vrealm}"
      update_hash[:vcddb] = false
    else
      clear_line
      logger.info "INFO - VCDDB Resource does not match - #{vrealm}"
      print '[ ' + 'INFO'.white + " ] VCDDB Resource needs updating - #{vrealm}"
      update_hash[:vcddb] = true
    end #if vcddb
  else
    clear_line
    logger.info "ERROR - Could not find VCDDB Resource on #{vrealm}"
  end

  #vcdnfs
  if !vcdnfs.empty?
    logger.debug "DEBUG - VCDNFS Resource: vcenter -  #{vcdnfs[0]['vcenter_hostname']}, Calculated #{vcenter_hostname}"
    logger.debug "DEBUG - VCDNFS Resource: Cluster -  #{vcdnfs[0]['cluster_name']}, Calculated #{cluster_name}"
    logger.debug "DEBUG - VCDNFS Resource: DataCenter -  #{vcdnfs[0]['datacenter_name']}, Calculated #{datacenter_name}"
    logger.debug "DEBUG - VCDNFS Resource: VM Name -  #{vcdnfs[0]['vm_name']}, Calculated #{vcdnfs_vm_name}"
    if (vcdnfs[0]['vcenter_hostname'] == vcenter_hostname) && (vcdnfs[0]['datacenter_name'] == datacenter_name)  \
      && (vcdnfs[0]['cluster_name'] == cluster_name) && (vcdnfs[0]['vm_name'] == vcdnfs_vm_name)
      clear_line
      logger.info "INFO - VCDNFS Resource matches - #{vrealm}"
      print '[ ' + 'INFO'.white + " ] VCDNFS Resource is correct - #{vrealm}"
      update_hash[:vcdnfs] = false
    else
      clear_line
      logger.info "INFO - VCDNFS Resource does not match - #{vrealm}"
      print '[ ' + 'INFO'.white + " ] VCDNFS Resource needs updating - #{vrealm}"
      update_hash[:vcdnfs] = true
    end #if vcdnfs
  else
    clear_line
    logger.info "ERROR - Could not find VCDNFS Resource on #{vrealm}"
  end

  #vsupg
  if !vsupg.empty?
    logger.debug "DEBUG - VSUPG Resource: VC Build -  #{vsupg[0]['target_vcenter_build']}, Imported #{opts[:target_vcenter_build]}"
    logger.debug "DEBUG - VSUPG Resource: ESXI Build -  #{vsupg[0]['target_esxi_build']}, Imported Default: #{opts[:target_esxi_build]}, DaaS: #{opts[:daas_target_esxi_build]}"
    if (vsupg[0]['target_vcenter_build'] == opts[:target_vcenter_build])
      if (vsupg[0]['target_esxi_build'] == opts[:target_esxi_build]) || (vsupg[0]['target_esxi_build'] == opts[:daas_target_esxi_build])
        clear_line
        logger.info "INFO - VSUPG VC Resource matches - #{vrealm}"
        print '[ ' + 'INFO'.white + " ] VSUPG VC Resource is correct - #{vrealm}"
        update_hash[:vsupg] = false
      else
        clear_line
        logger.info "INFO - VSUPG Resource does not match - #{vrealm}"
        print '[ ' + 'INFO'.white + " ] VSUPG Resource needs updating - #{vrealm}"
        update_hash[:vsupg] = true
      end
    else
      clear_line
      logger.info "INFO - VSUPG Resource does not match - #{vrealm}"
      print '[ ' + 'INFO'.white + " ] VSUPG Resource needs updating - #{vrealm}"
      update_hash[:vsupg] = true
    end #if vsupg
  else
    clear_line
    logger.info "ERROR - Could not find VSUPG Resource on #{vrealm}"
  end

  #vsm
  if !vsm.empty?
    logger.debug "DEBUG - VSM Resource: vcenter -  #{vsm[0]['vcenter_hostname']}, Calculated #{vcenter_hostname}"
    logger.debug "DEBUG - VSM Resource: Cluster -  #{vsm[0]['cluster_name']}, Calculated #{cluster_name}"
    logger.debug "DEBUG - VSM Resource: DataCenter -  #{vsm[0]['datacenter_name']}, Calculated #{datacenter_name}"
    logger.debug "DEBUG - VSM Resource: VM Name -  #{vsm[0]['vm_name']}, Calculated #{vsm_vm_name}"
    logger.debug "DEBUG - VSM Resource: Target CPU - #{vsm[0]['target_cpu']}, Inputed #{opts[:nsx_cpu_count]}"
    logger.debug "DEBUG - VSM Resource: Target Cores - #{vsm[0]['target_cores_per_socket']}, Inputed #{opts[:nsx_cpu_core]}"
    logger.debug "DEBUG - VSM Resource: Target Memory(GB) - #{vsm[0]['target_memory']}, Inputed #{opts[:nsx_mem]}"

    if nsx_ver.empty? || nsx_ver.nil?
      logger.debug "DEBUG - VSM Resource: Target Version - nil, Inputed #{opts[:target_nsx_version]}"
      update_hash[:nsx_ver] = true
    else
      logger.debug "DEBUG - VSM Resource: Target Version - #{nsx_ver[0]['value']}, Inputed #{opts[:target_nsx_version]}"
      if nsx_ver[0]['value'] == opts[:target_nsx_version]
        clear_line
        logger.info "INFO - NSX Version Resource matches - #{vrealm}"
        update_hash[:nsx_ver] = false
      else
        clear_line
        logger.info "INFO - NSX Version Resource does not match - #{vrealm}"
        update_hash[:nsx_ver] = true
      end #if nsx_ver[0]['value'] == opts[:target_nsx_version]
    end #if nsx_ver.empty? || nsx_ver.nil?

    if nsx_build.empty? || nsx_build.nil?
      logger.debug "DEBUG - VSM Resource: Target Version - nil, Inputed #{opts[:target_nsx_build]}"
      update_hash[:nsx_build] = true
    else
      logger.debug "DEBUG - VSM Resource: Target Build - #{nsx_build[0]['value']}, Inputed #{opts[:target_nsx_build]}"
      if nsx_build[0]['value'] == opts[:target_nsx_build]
        clear_line
        logger.info "INFO - NSX Build Resource matches - #{vrealm}"
        update_hash[:nsx_build] = false
      else
        clear_line
        logger.info "INFO - NSX Build Resource does not match - #{vrealm}"
        update_hash[:nsx_build] = true
      end #if nsx_build[0]['value'] == opts[:target_nsx_build]
    end #if nsx_build.empty? || nsx_build.nil?

    if (vsm[0]['vcenter_hostname'] == vcenter_hostname) && (vsm[0]['datacenter_name'] == datacenter_name)  \
      && (vsm[0]['cluster_name'] == cluster_name) && (vsm[0]['vm_name'] == vsm_vm_name)
      clear_line
      logger.info "INFO - VSM Resource matches - #{vrealm}"
      print '[ ' + 'INFO'.white + " ] VSM Resource is correct - #{vrealm}"
      update_hash[:vsm] = false
    else
      clear_line
      logger.info "INFO - VSM Resource does not match - #{vrealm}"
      print '[ ' + 'INFO'.white + " ] VSM Resource needs updating - #{vrealm}"
      update_hash[:vsm] = true
    end #if vsm
  else
    clear_line
    logger.info "ERROR - Could not find VSM Resource on #{vrealm}"
  end

  logger.debug "DEBUG - Update hash: #{update_hash}"

  #split update hash
  update_hash.select! { |x,y| y == true }
  if opts[:verify_only] == true
    if update_hash.empty?
      clear_line
      logger.info "INFO - No changes needed #{vrealm}"
      puts '[ ' + 'INFO'.white + " ] No changes needed on #{vrealm}"
    else
      clear_line
      logger.info "INFO - Verify only set. No changes being made on #{vrealm}"
      puts '[ ' + 'WARN'.yellow + " ] Verify only set. No changes being made on #{vrealm}"
    end
  else
    #update vcda if needed
    if !vcda.empty?
      update_query(pg, logger, vcda[0]['fqdn'], 'resources', vcda[0]['id'], 'vm_name', vcda_vm_name) unless vcda[0]['vm_name'] == vcda_vm_name
      update_query(pg, logger, vcda[0]['fqdn'], 'resources', vcda[0]['id'], 'vcenter_hostname', vcenter_hostname) unless vcda[0]['vcenter_hostname'] == vcenter_hostname
      update_query(pg, logger, vcda[0]['fqdn'], 'resources', vcda[0]['id'], 'datacenter_name', datacenter_name) unless vcda[0]['datacenter_name'] == datacenter_name
      update_query(pg, logger, vcda[0]['fqdn'], 'resources', vcda[0]['id'], 'cluster_name', cluster_name) unless vcda[0]['cluster_name'] == cluster_name
    end

    #update vcdb if needed
    if !vcdb.empty?
      update_query(pg, logger, vcdb[0]['fqdn'], 'resources', vcdb[0]['id'], 'vm_name', vcdb_vm_name) unless vcdb[0]['vm_name'] == vcdb_vm_name
      update_query(pg, logger, vcdb[0]['fqdn'], 'resources', vcdb[0]['id'], 'vcenter_hostname', vcenter_hostname) unless vcdb[0]['vcenter_hostname'] == vcenter_hostname
      update_query(pg, logger, vcdb[0]['fqdn'], 'resources', vcdb[0]['id'], 'datacenter_name', datacenter_name) unless vcdb[0]['datacenter_name'] == datacenter_name
      update_query(pg, logger, vcdb[0]['fqdn'], 'resources', vcdb[0]['id'], 'cluster_name', cluster_name) unless vcdb[0]['cluster_name'] == cluster_name
    end

    #update vcddb if needed
    if !vcddb.empty?
      update_query(pg, logger, vcddb[0]['fqdn'], 'resources', vcddb[0]['id'], 'vm_name', vcddb_vm_name) unless vcddb[0]['vm_name'] == vcddb_vm_name
      update_query(pg, logger, vcddb[0]['fqdn'], 'resources', vcddb[0]['id'], 'vcenter_hostname', vcenter_hostname) unless vcddb[0]['vcenter_hostname'] == vcenter_hostname
      update_query(pg, logger, vcddb[0]['fqdn'], 'resources', vcddb[0]['id'], 'datacenter_name', datacenter_name) unless vcddb[0]['datacenter_name'] == datacenter_name
      update_query(pg, logger, vcddb[0]['fqdn'], 'resources', vcddb[0]['id'], 'cluster_name', cluster_name) unless vcddb[0]['cluster_name'] == cluster_name
    end

    #update vcdnfs if needed
    if !vcdnfs.empty?
      update_query(pg, logger, vcdnfs[0]['fqdn'], 'resources', vcdnfs[0]['id'], 'vm_name', vcdnfs_vm_name) unless vcdnfs[0]['vm_name'] == vcdnfs_vm_name
      update_query(pg, logger, vcdnfs[0]['fqdn'], 'resources', vcdnfs[0]['id'], 'vcenter_hostname', vcenter_hostname) unless vcdnfs[0]['vcenter_hostname'] == vcenter_hostname
      update_query(pg, logger, vcdnfs[0]['fqdn'], 'resources', vcdnfs[0]['id'], 'datacenter_name', datacenter_name) unless vcdnfs[0]['datacenter_name'] == datacenter_name
      update_query(pg, logger, vcdnfs[0]['fqdn'], 'resources', vcdnfs[0]['id'], 'cluster_name', cluster_name) unless vcdnfs[0]['cluster_name'] == cluster_name
    end

    #update vsm if needed
    if !vsm.empty?
      update_query(pg, logger, vsm[0]['fqdn'], 'resources', vsm[0]['id'], 'vm_name', vsm_vm_name) unless vsm[0]['vm_name'] == vsm_vm_name
      update_query(pg, logger, vsm[0]['fqdn'], 'resources', vsm[0]['id'], 'vcenter_hostname', vcenter_hostname) unless vsm[0]['vcenter_hostname'] == vcenter_hostname
      update_query(pg, logger, vsm[0]['fqdn'], 'resources', vsm[0]['id'], 'datacenter_name', datacenter_name) unless vsm[0]['datacenter_name'] == datacenter_name
      update_query(pg, logger, vsm[0]['fqdn'], 'resources', vsm[0]['id'], 'cluster_name', cluster_name) unless vsm[0]['cluster_name'] == cluster_name
      update_query(pg, logger, vsm[0]['fqdn'], 'resources', vsm[0]['id'], 'target_cpu', opts[:nsx_cpu_count]) unless vsm[0]['target_cpu'] == opts[:nsx_cpu_count]
      update_query(pg, logger, vsm[0]['fqdn'], 'resources', vsm[0]['id'], 'target_cores_per_socket', opts[:nsx_cpu_core]) unless vsm[0]['target_cores_per_socket'] == opts[:nsx_cpu_core]
      update_query(pg, logger, vsm[0]['fqdn'], 'resources', vsm[0]['id'], 'target_memory', opts[:nsx_mem]) unless vsm[0]['target_memory'] == opts[:nsx_cpu_core]

      if nsx_ver.nil? || nsx_ver.empty?
        clear_line
        logger.info "INFO - Performing insert on NSX Version #{vsm[0]['fqdn']}"
        print '[ ' + 'INFO'.white + " ] Performing insert on NSX Version on #{vsm[0]['fqdn']}"
        insert_query = "INSERT INTO custom_attribute_values (instance_customizable_id, instance_customizable_type, custom_attribute_relationship_id, value, created_at, updated_at, modified_by) VALUES ('#{vsm[0]['id']}', 'Resource', '#{nsx_ver_relationship_id}', '#{opts[:target_nsx_version]}', current_timestamp, current_timestamp, '#{user}')"
        begin
          pg.exec(insert_query)
          clear_line
          logger.info "INFO - Insert for NSX Version is Successful"
          print '[ ' + 'INFO'.white + " ] Insert for NSX Version is Successful"
        rescue => e
          clear_line
          logger.info "ERROR - Failed insert for NSX Version"
          puts '[ ' + 'ERROR'.red + " ] Failed insert for NSX Version"
          puts e
        end #begin
      else
        update_query(pg, logger, vsm[0]['fqdn'], 'custom_attribute_values', nsx_ver[0]['id'], 'value', opts[:target_nsx_version]) unless nsx_ver[0]['value'] == opts[:target_nsx_version]
      end #if nsx_ver.nil? or nsx_ver.empty?

      if nsx_build.nil? || nsx_build.empty?
        clear_line
        logger.info "INFO - Performing insert on NSX Build #{vsm[0]['fqdn']}"
        print '[ ' + 'INFO'.white + " ] Performing insert on NSX Build on #{vsm[0]['fqdn']}"
        insert_query = "INSERT INTO custom_attribute_values (instance_customizable_id, instance_customizable_type, custom_attribute_relationship_id, value, created_at, updated_at, modified_by) VALUES ('#{vsm[0]['id']}', 'Resource', '#{nsx_build_relationship_id}', '#{opts[:target_nsx_build]}', current_timestamp, current_timestamp, '#{user}')"
        begin
          pg.exec(insert_query)
          clear_line
          logger.info "INFO - Insert for NSX Build is Successful"
          print '[ ' + 'INFO'.white + " ] Insert for NSX Build is Successful"
        rescue => e
          clear_line
          logger.info "ERROR - Failed insert for NSX Build"
          puts '[ ' + 'ERROR'.red + " ] Failed insert for NSX Build"
          puts e
        end #begin
      else
        update_query(pg, logger, vsm[0]['fqdn'], 'custom_attribute_values', nsx_build[0]['id'], 'value', opts[:target_nsx_build]) unless nsx_build[0]['value'] == opts[:target_nsx_build]
      end #if nsx_build.nil? or nsx_build.empty?
    end


    #update VSUPG vCenter Build if needed
    if !vsupg.empty?
      update_query(pg, logger, vsupg[0]['fqdn'], 'resources', vsupg[0]['id'], 'target_vcenter_build', opts[:target_vcenter_build]) unless vsupg[0]['target_vcenter_build'] == opts[:target_vcenter_build]

      #update VSUPG ESXI Build if needed
      unless (vsupg[0]['target_esxi_build'] == opts[:target_esxi_build]) || (vsupg[0]['target_esxi_build'] == opts[:daas_target_esxi_build])
        update_query(pg, logger, vsupg[0]['fqdn'], 'resources', vsupg[0]['id'], 'target_esxi_build', opts[:target_esxi_build]) unless vsupg[0]['target_esxi_build'] == opts[:target_esxi_build]      
      end
    end

    clear_line
    logger.info "INFO - Completed updates on #{vrealm}"
    puts '[ ' + 'INFO'.white + " ] Completed updates on #{vrealm}"
  end #if opts[:verify_only] == true
end #end opts[:vrealms.each]














