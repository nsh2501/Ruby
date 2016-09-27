# -*- encoding : utf-8 -*-
#
# ***********************************************************
#  Copyright (c) 2016 VMware, Inc.  All rights reserved.
# **********************************************************
#

#!/usr/bin/env ruby
require 'net/ssh'
require 'openssl'
require 'base64'

  hostname='d9p10v35mgmt-sso-a'
  username='root'
  password='K0r05QWXv3Qk'
  sso_password='vmware'
  warndays ||= 14
  warnsec = warndays.to_i * 24 * 60 * 60
  begin
    ssh_conn = Net::SSH.start(hostname, username, :password => password, :paranoid => false)
    entries = ssh_conn.exec!("ldapsearch -x -w #{sso_password} -h localhost -D 'cn=Administrator,cn=Users,dc=vsphere,dc=local' -p 11711 -b 'cn=ServiceRegistrations,cn=LookupService,cn=local,cn=Sites,cn=Configuration,dc=vsphere,dc=local' -LLL '(objectclass=vmwLKUPServiceEndpoint)' -o ldif-wrap=no vmwLKUPURI vmwLKUPSslTrustAnchor").split(/\n/)
    certs = {}
    entries.each do |entry|
      svcinfo = entry.match "dn: cn=Endpoint(.*),cn=(.*),cn=ServiceRegistrations"
      if svcinfo
        @svc = svcinfo[2]
        @ep = svcinfo[1]
        certs[@svc] = {} unless certs[@svc]
        certs[@svc][@ep] = {} unless certs[@svc][@ep]
      end
      trust = entry.match "vmwLKUPSslTrustAnchor:: (.*)"
      if trust
        cert = OpenSSL::X509::Certificate.new Base64.decode64(trust[1])
        certs[@svc][@ep][:enddate] = cert.not_after
      end
      uri = entry.match "vmwLKUPURI: (.*)"
      if uri
        certs[@svc][@ep][:uri] = uri[1]
      end
    end
  rescue
    certs = {}
    entries = []
  end

  it "SSO should return service registrations :" do
    expect(entries.count).to be > 0
  end

  it "SSO should have certificate information for services: " do
    expect(certs.count).to be > 0
  end

  certs.each do |svc, eps|
    eps.each do |ep, h|    
      it "Certificate for service #{svc} endpoint #{ep} should not be expired\nURI: #{h[:uri]} : " do
        expect(h[:enddate] < Time.now.utc).to be(false)
      end

      it "Certificate for service #{svc} endpoint #{ep} should not expire within #{warndays} days\nURI: #{h[:uri]} : " do
        expect(h[:enddate] < (Time.now.utc + warnsec)).to be(false)
      end
      if (h[:enddate] < (Time.now.utc + warnsec))
        it "Certificate for service #{svc} endpoint #{ep} expiration #{h[:enddate]}\nURI: #{h[:uri]} : " do
          expect(true).to be(false)
        end
      end
    end
  end
