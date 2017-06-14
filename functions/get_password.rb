require 'vmware_secret_server'

def get_password(adpass, secret, domain)
  case domain
  when 'prod'
    ss_url = "https://d0p1oss-mgmt-secret-web0.prod.vpc.vmw/SecretServer/webservices/SSWebservice.asmx?wsdl"
  when 'stage'
    ss_url = "https://d2p2oss-mgmt-secret-web0.stage.vpc.vmw/SecretServer/webservices/SSWebservice.asmx?wsdl"
  else
    puts '[ ' + 'ERROR'.red + " ] Unkown domain. #{domain}"
  end
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