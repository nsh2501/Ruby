require 'rbvmomi'


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

def get_inv_info(vim, dc, host_prop=nil, vm_prop=nil)
  host_prop = %w(name parent runtime.connectionState) unless !host_prop.nil?
  vm_prop = %w(name runtime.powerState summary.guest.toolsStatus) unless !vm_prop.nil?

  filterSpec = RbVmomi::VIM.PropertyFilterSpec(
        :objectSet => [
          :obj => dc,
          :selectSet => [
            RbVmomi::VIM.TraversalSpec(
              :name => 'tsFolder',
              :type => 'Folder',
              :path => 'childEntity',
              :skip => false,
              :selectSet => [
                RbVmomi::VIM.SelectionSpec(:name => 'tsFolder'),
                RbVmomi::VIM.SelectionSpec(:name => 'tsDatacenterVmFolder'),
                RbVmomi::VIM.SelectionSpec(:name => 'tsDatacenterHostFolder'),
                RbVmomi::VIM.SelectionSpec(:name => 'tsClusterRP'),
                RbVmomi::VIM.SelectionSpec(:name => 'tsClusterHost'),
                RbVmomi::VIM.SelectionSpec(:name => 'tsVapp'),
              ]
            ),
            RbVmomi::VIM.TraversalSpec(
              :name => 'tsDatacenterVmFolder',
              :type => 'Datacenter',
              :path => 'vmFolder',
              :skip => false,
              :selectSet => [
                RbVmomi::VIM.SelectionSpec(:name => 'tsFolder')
              ]
            ),
            RbVmomi::VIM.TraversalSpec(
              :name => 'tsDatacenterHostFolder',
              :type => 'Datacenter',
              :path => 'hostFolder',
              :skip => false,
              :selectSet => [
                RbVmomi::VIM.SelectionSpec(:name => 'tsFolder')
              ]
            ),
            RbVmomi::VIM.TraversalSpec(
              :name => 'tsClusterRP',
              :type => 'ClusterComputeResource',
              :path => 'resourcePool',
              :skip => false,
              :selectSet => [
                RbVmomi::VIM.SelectionSpec(:name => 'tsRP'),
                RbVmomi::VIM.SelectionSpec(:name => 'tsVapp'),
              ]
            ),
            RbVmomi::VIM.TraversalSpec(
              :name => 'tsClusterHost',
              :type => 'ClusterComputeResource',
              :path => 'host',
              :skip => false,
              :selectSet => []
            ),
            RbVmomi::VIM.TraversalSpec(
              :name => 'tsRP',
              :type => 'ResourcePool',
              :path => 'resourcePool',
              :skip => false,
              :selectSet => [
                RbVmomi::VIM.SelectionSpec(:name => 'tsRP'),
                RbVmomi::VIM.SelectionSpec(:name => 'tsVapp'),
              ]
            ),
            RbVmomi::VIM.TraversalSpec(
              :name => 'tsVapp',
              :type => 'VirtualApp',
              :path => 'vm',
              :skip => false,
              :selectSet => []
            ),
          ]
        ],
        :propSet => [
          { :type => 'Folder', :pathSet => ['name', 'parent'] },
          { :type => 'Datacenter', :pathSet => ['name', 'parent'] },
          { :type => 'ClusterComputeResource', 
            :pathSet => %w(name parent summary.effectiveCpu summary.effectiveMemory) 
          },
          { :type => 'ResourcePool', :pathSet => ['name', 'parent'] },
          { :type => 'VirtualApp', :pathSet => ['name', 'parent', 'vm']},
          { :type => 'HostSystem', :pathSet => host_prop },
          { :type => 'VirtualMachine', :pathSet => vm_prop },
        ]
      )


  result = vim.serviceContent.propertyCollector.RetrieveProperties(:specSet => [filterSpec])
end