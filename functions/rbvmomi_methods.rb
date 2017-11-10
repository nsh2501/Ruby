require 'rbvmomi'
require_relative '/home/nholloway/scripts/Ruby/functions/format.rb'


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


def get_vmhosts(vim, dc, host_prop=nil)
  host_prop = %w(name parent runtime.connectionState) if host_prop.nil?

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
                RbVmomi::VIM.SelectionSpec(:name => 'tsDatacenterHostFolder'),
                RbVmomi::VIM.SelectionSpec(:name => 'tsClusterHost'),
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
              :name => 'tsClusterHost',
              :type => 'ClusterComputeResource',
              :path => 'host',
              :skip => false,
              :selectSet => []
            ),
          ]
        ],
        :propSet => [
          { :type => 'HostSystem', :pathSet => host_prop },
        ]
      )


  result = vim.serviceContent.propertyCollector.RetrieveProperties(:specSet => [filterSpec])
end

def get_vm(vim, dc, vm_prop=nil)
  vm_prop = %w(name runtime.powerState summary.guest.toolsStatus) if vm_prop.nil?

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
          { :type => 'VirtualMachine', :pathSet => vm_prop },
        ]
      )


  result = vim.serviceContent.propertyCollector.RetrieveProperties(:specSet => [filterSpec])
end

def get_vm_2(vim, vm_prop=nil)
  vm_prop = %w(name runtime.powerState summary.guest.toolsStatus) if vm_prop.nil?

  pc = vim.serviceInstance.content.propertyCollector                                                                                                                               
  viewmgr = vim.serviceInstance.content.viewManager
  rootFolder = vim.serviceInstance.content.rootFolder
  vmview = viewmgr.CreateContainerView({:container => rootFolder,                                                                                                                                  
                                        :type => ['VirtualMachine'],                                                                                                                                            
                                        :recursive => true})
  filterSpec = RbVmomi::VIM.PropertyFilterSpec(                                                                                                                                                    
                :objectSet => [                                                                                                                                                                              
                :obj => vmview,                                                                                                                                                                          
                :skip => true,                                                                                                                                                                           
                :selectSet => [                                                                                                                                                                          
                    RbVmomi::VIM.TraversalSpec(                                                                                                                                                          
                        :name => "traverseEntities",                                                                                                                                                     
                        :type => "ContainerView",                                                                                                                                                        
                        :path => "view",                                                                                                                                                                 
                        :skip => false                                                                                                                                                                   
                    )]                                                                                                                                                                                   
            ],                                                                                                                                                                                           
            :propSet => [                                                                                                                                                                                
                { :type => 'VirtualMachine', :pathSet => vm_prop}                                                                                                                                                     
            ]                                                                                                                                                                                            
        )                                                                                                                                                                                                
  result = pc.RetrieveProperties(:specSet => [filterSpec])
end

##### NOT DONE YET ######
def get_powered_on_vms(vim, vm_prop=nil)
  vm_list = get_vm_2(vim, vm_prop)

end

def get_resource_pool(vim, rsp_prop=nil)
  rsp_prop = %w(name) if rsp_prop.nil?

  pc = vim.serviceInstance.content.propertyCollector                                                                                                                               
  viewmgr = vim.serviceInstance.content.viewManager
  rootFolder = vim.serviceInstance.content.rootFolder
  vmview = viewmgr.CreateContainerView({:container => rootFolder,                                                                                                                                  
                                        :type => ['ResourcePool'],                                                                                                                                            
                                        :recursive => true})
  filterSpec = RbVmomi::VIM.PropertyFilterSpec(                                                                                                                                                    
                :objectSet => [                                                                                                                                                                              
                :obj => vmview,                                                                                                                                                                          
                :skip => true,                                                                                                                                                                           
                :selectSet => [                                                                                                                                                                          
                    RbVmomi::VIM.TraversalSpec(                                                                                                                                                          
                        :name => "traverseEntities",                                                                                                                                                     
                        :type => "ContainerView",                                                                                                                                                        
                        :path => "view",                                                                                                                                                                 
                        :skip => false                                                                                                                                                                   
                    )]                                                                                                                                                                                   
            ],                                                                                                                                                                                           
            :propSet => [                                                                                                                                                                                
                { :type => 'ResourcePool', :pathSet => rsp_prop}                                                                                                                                                     
            ]                                                                                                                                                                                            
        )                                                                                                                                                                                                
result = pc.RetrieveProperties(:specSet => [filterSpec])

end

def get_connected_hosts(vim, dc, host_prop=nil)
  vmhosts = get_vmhosts(vim, dc, host_prop)
  connected_hosts = vmhosts.select { |vmhost| vmhost.propSet.find { |prop| prop.name == 'runtime.connectionState'}.val == 'connected' }
  return connected_hosts
end

def take_snapshot(vm, name, snap_memory, snap_quiesce, logger)
  vm_name = vm.propSet.find { |prop| prop.name == 'name' }.val
  begin
    clear_line
    logger.info "INFO - Taking snapshot for #{vm_name}"
    print '[ ' + 'INFO'.white + " ] Taking snapshot for #{vm_name}"
    vm.obj.CreateSnapshot_Task(name: name, description: ' ', memory: snap_memory, quiesce: snap_quiesce).wait_for_completion
    return 'SUCCESS'
  rescue => e
    clear_line
    logger.info "ERROR - Snapshot for #{vm_name} failed!"
    puts '[ ' + 'ERROR'.red + " ] Snapshot for #{vm_name} failed! Please see error below"
    puts e.message
    return 'FAILED'
  end
end

def get_tasks(vim, entity, recursion, amount)
  #create TaskFilterSPec
  filter = RbVmomi::VIM.TaskFilterSpec(
    :entity => RbVmomi::VIM.TaskFilterSpecByEntity(
      :entity => entity,
      :recursion => RbVmomi::VIM.TaskFilterSpecRecursionOption(recursion)
    )
  )

  #Create task collector
  tasks_collector = vim.serviceContent.taskManager.CreateCollectorForTasks(:filter => filter)

  #get tasks
  tasks = tasks_collector.ReadNextTasks(:maxCount => amount)

  return tasks
end







