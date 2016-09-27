#!/usr/bin/env ruby
require 'rbvmomi'
require 'highline/import'
require 'net/ssh'
require 'trollop'
require 'colorize'


user = `whoami`.chomp
user.concat '@ad.prod.vpc.vmw'
adPass = ask("Enter your AD password: ") { |q| q.echo="*"};

#connect to vCenter
vim = RbVmomi::VIM.connect :host => vc, :user => user, :password => adPass, :insecure => true

#get datacenter
dc = vim.serviceInstance.find_datacenter

vms = []
def list_vms(folder)
  children = folder.children.find_all
  children.each do |child|
    if child.class == RbVmomi::VIM::VirtualMachine
      if child.runtime.powerState == 'poweredOn' && child.config.name =~ /vc0/
        @vms.push child.name
        print '                                                                                                                                                                      '
          print "\r"
          print "[ " + "INFO".white + " ] #{child.name} added to inventory"
          print "\r"
      end
    elsif child.class == RbVmomi::VIM::Folder
      list_vms(child)
    end
  end
end
