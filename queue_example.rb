require_relative '/home/nholloway/scripts/Ruby/functions/format.rb'
require_relative '/home/nholloway/scripts/Ruby/functions/get_password.rb'
require_relative '/home/nholloway/scripts/Ruby/functions/rbvmomi_methods.rb'
require_relative '/home/nholloway/scripts/Ruby/functions/get_vcenterlist.rb'

vcenters = f_get_vcenter_list('prod', 'mgmt')
num_workers = 5

@vim_inv = []
queue = Queue.new
threads = num_workers.times.map do
 Thread.new do
   until (vcenter = queue.pop) == :END
     vim = connect_viserver(vcenter, @ad_user, @ad_pass)
     dc = vim.serviceInstance.find_datacenter
     vim_inv = get_inv_info(vim, dc, nil, nil)
     @vim_inv.push(*vim_inv)
     vim.close
     puts "Done with #{vcenter}"
   end
 end
end


vcenters.each { |vcenter| queue << vcenter };
num_workers.times { queue << :END };
threads.each(&:join)

