def get_password(resource, username)
  resource_pass = `/tools-export/Scripts/functions/pmpcli_rest #{resource} #{username}`.chomp
  if resource_pass == ""
    #puts "Password not found for #{resource}, using default.".yellow
    resource_pass = 'm0n3yb0vin3'
  end
  return resource_pass
end
