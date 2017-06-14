require 'vmware_secret_server'

def get_password(adpass, secret, ss_url, domain)
  ss_connection = Vmware_secret_server::Session.new(ss_url, 'ad', adpass)
  ss_password = ss_connection.get_password(secret)
  if ss_password.is_a? Exception
    clear_line
    puts '[ ' + 'ERROR'.red + " ] Could not get password for #{secret} in Secret Server. Error is #{ss_password.message}"
    return 'ERROR'
  else 
    clear_line
    print '[ ' + 'INFO'.green + " ] Successfully pulled password from Secret Server for #{secret}"
    return ss_password
  end
end