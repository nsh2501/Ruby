#!/usr/bin/env ruby
#pasword functions

require 'vmware_secret_server'
require 'highline/import'
require 'json'
require 'net/ssh'

require_relative '/home/nholloway/scripts/Ruby/functions/format.rb'

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
    raise 'ERROR'
  else 
    clear_line
    print '[ ' + 'INFO'.green + " ] Successfully pulled password from Secret Server for #{secret}"
    return ss_password
  end
end


def get_adPass
  if File.file?("#{ENV['HOME']}/.secretserver/ss_creds")
    jPass = `base64 -d ~/.secretserver/ss_creds`
    pArray = JSON.parse(jPass)
    ad_pass_ask = pArray['AD PASSWORD']
  else
    ad_pass_ask = ask("Enter your AD Password: ") { |q| q.echo="*"};
  end
  localVM = ENV['HOSTNAME']
  runuser = `whoami`.chomp
  adPass = verifyAD_Pass(localVM, runuser, ad_pass_ask)
end

def verifyAD_Pass(vm, user, pass)
  access = 'false'
  clear_line
  print '[ ' + 'INFO'.green + " ] Verifying AD Password"
  while access == 'false'
    begin
      session = Net::SSH.start(vm, user, :password => pass, :auth_methods => ['password'], :number_of_password_prompts => 0)
      access = 'true'
      clear_line
      print '[ ' + 'INFO'.green + " ] AD Authentication successful"
      session.close
    rescue Net::SSH::AuthenticationFailed 
        clear_line
        puts '[ ' + 'WARN'.yellow + " ] Failed to authenticate to #{vm} with password provided."
        pass = ask("Please enter your AD Password") { |q| q.echo="*"}
    end
  end
  return pass
end
