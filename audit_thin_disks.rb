#!/usr/bin/env ruby
#runs a audit on all vcenters listed and will report on any thin disks and space needed if these disks are inflated

require 'trollop'

require_relative '/home/nholloway/scripts/Ruby/functions/format.rb'
require_relative '/home/nholloway/scripts/Ruby/functions/password_functions.rb'
require_relative '/home/nholloway/scripts/Ruby/functions/rbvmomi_methods.rb'
require_relative '/home/nholloway/scripts/Ruby/functions/vcenter_list_v2.rb'

opts = Trollop::options do
  opt :vcenters "List of vCenters to run the audit on", :type => :strings, :required => true
  opt :file_location "Location you would like the csv file", :type => :string, :required => false, :default => 'ENV[\'HOME\']'
end

#methods
def convert_GB(size, is_bytes=false)
  size_float = size.to_f
  size_gb = size_float / 1048576.0

  if is_bytes == true
    size_gb = size_gb / 1024.0
  end

  return size_gb.round(2)
end

#variables
ad_user = 'AD\\' + `whoami`.chomp
ad_pass = get_adPass
vm_prop = ["name", "layoutEx", "config.hardware.device", "resourcePool"]
report = []

opts[:vcenters].each do |vcenter|
  #variables
  total_drive_vc = 0
  total_used_vc = 0
  rsp_vms = []

  #connecto to vCenter
  vim = connect_viserver(vcenter, ad_user, ad_pass)

  #get list of vms and resource pools
  vms = get_vm_2(vim, vm_prop)
  rsp = get_resource_pool(vim)

  #get list of resource pools that do not match the name
  rsp.select! { |pool| pool.propSet.find { |prop| prop.name == 'name' && prop.val !~ /System vDC|vmware_service|Resources/ } }

  #filter out only vm's that are in resource pools in rsp
  rsp.each { |pool|
    rsp_vms += vms.select { |vm| 
      vm.propSet.find { |prop| 
        prop.name == 'resourcePool' && prop.val == pool.obj 
      }
    }
  }

  #get each vm that has thin provisioned disks and add up total disks
    rsp_vms.each { |vm|
      #variables needed on a per vm basis
      vm_hash = {}
      thin_disks = false
      total_drive_vm = 0
      total_used_vm = 0    

      #get vm name
      vm_name = vm.propSet.find { |prop| prop.name == 'name' }.val

      #look for drives on vm that are thin provisioned
      vm.propSet.find { |prop|
        prop.name == 'config.hardware.device'
      }.val.each { |device|
        if device.class == RbVmomi::VIM::VirtualDisk && device.backing.thinProvisioned == true;

          #if found then set thin_disks to true and record total size of drive and total used
          thin_disks = true
          fname = device.backing.fileName.gsub('.vmdk', '-flat.vmdk')
          total_drive_vm += convert_GB(device.capacityInKB)

          disk_size = vm.propSet.find { |prop| 
            prop.name == 'layoutEx'
          }.val.file.each { |file|
            if file.name == fname
              total_used_vm += convert_GB(file.size, true)
            end
          }
        end
      }
      #if thin disks found build hash and push to report. Also add totals to variables for vCenter
      if thin_disks == true
        vm_hash['vcenter'] = vcenter
        vm_hash['name'] = vm_name
        vm_hash['Thin Disk Size Total'] = total_drive_vm
        vm_hash['Thin Disk Size Used'] = total_used_vm
        vm_hash['Needed Space'] = total_drive_vm - total_used_vm
        report.push(vm_hash)

        total_drive_vc += total_drive_vm
        total_used_vc += total_used_vm
      end
    }
  vc_hash = {}
  vc_hash['vcenter'] = vcenter
  vc_hash['name'] = 'Total Numbers'
  vc_hash['Thin Disk Size Total'] = total_drive_vc
  vc_hash['Thin Disk Size Used'] = total_used_vc
  vc_hash['Needed Space'] = total_drive_vc - total_used_vc
  report.push(vc_hash)
end


column_names = report.first.key
s = CSV.generate do |csv|
  csv << column_names
  report.each do |x|
    csv << x.values
  end
end

csv_file = opts[:file_location] + '/thin_disks.csv'

File.write(csv_file, s)

puts "CSV file can be found at #{csv_file}"











