#!/usr/bin/env ruby

require 'highline/import'
require 'rest-client'
require 'trollop'
require 'colorize'
require 'syslog/logger'
require 'yaml'
require 'pp'


#process
pid = Process.pid

#date
time = Time.new
datestamp = time.strftime("%m%d%Y-%s")

#variables
yamldir = '/home/nholloway/scripts/Ruby/files'
yamlall_file = yamldir + '/fid-all.yaml'
yamlall = YAML.load_file(yamlall_file)
fids = yamlall['fids']

#files to write to
vrealmfile = ENV["HOME"] + "/fidsvrealm-#{datestamp}.#{pid}"
ossfile = ENV["HOME"] + "/fidsoss-#{datestamp}.#{pid}"
parentfile = ENV["HOME"] + "/fidsparent-#{datestamp}.#{pid}"

#build empty arrays
vrealm_arr = []
oss_arr = []
parent_arr = []

opts = Trollop::options do
  #required parameters
  opt :vrealm, "vRealm to check for the FID. Ex: dXpYvZ", :type => :string, :required => true

  #optional parameters
  opt :praxis_parent, "Use this option for Praxis Parents"
  opt :praxis_child, "Use this option for Praxis Child vRealms"
  opt :parent_vpc, "Required if Praxis Child", :type => :string
  opt :subscription, "Use this option for Subscription vRealms"
end

#check parameters
Trollop::die :vrealm, "vRealm must be in dXpYvZ formate" unless /^d\d+p\d+(v\d+|oss|tlm)$/.match(opts[:vrealm])
Trollop::die :parent_vpc, "vRealm must be in dXpYvZ formate" unless /^d\d+p\d+(v\d+|oss|tlm)$/.match(opts[:parent_vpc]) if opts[:parent_vpc]

if (opts[:praxis_parent] == false) && (opts[:praxis_child] == false) && (opts[:subscription] == false)
  puts '[ ' + 'ERROR'.red + " ] Must specify a vRealm Type"
  exit
end

if (opts[:praxis_parent]) || (opts[:praxis_child])
  if opts[:subscription]
    puts '[ ' + 'ERROR'.red + " ] Can't do both praxis and subscription"
    exit
  end
end

if (opts[:praxis_parent]) && (opts[:praxis_child])
  puts '[ ' + 'ERROR'.red + " ] Can't be both parent and child"
  exit
end

if (opts[:praxis_child]) && (opts[:parent_vpc].nil?)
  puts '[ ' + 'ERROR'.red + " ] Parent_vpc required when using option for Praxis Child"
  exit
end

#determine which file to use
if opts[:praxis_parent]
  yamlfile = yamldir + '/fid-prxs-parent.yaml'
elsif opts[:praxis_child]
  yamlfile = yamldir + '/fid-prxs-child.yaml'
end

if yamlfile
  yamlload = YAML.load_file(yamlfile)
  prxs_fids = yamlload['fids']
end

unless fids.nil?
  fids.each do |f|
    fnumb = f.first
    fitems = f.last
    if fitems['edges'].include? 'vrealm_priv'
      vrealm_arr.push fnumb
    end
    if fitems['edges'].include? 'oss_priv'
      oss_arr.push fnumb
    end
    if fitems['edges'].include? 'parent_priv'
      parent_arr.push fnumb
    end
  end
end;

unless prxs_fids.nil?
  prxs_fids.each do |f|
    fnumb = f.first
    fitems = f.last
    if fitems['edges'].include? 'vrealm_priv'
      vrealm_arr.push fnumb
    end
    if fitems['edges'].include? 'oss_priv'
      oss_arr.push fnumb
    end
    if fitems['edges'].include? 'parent_priv'
      parent_arr.push fnumb
    end
  end
end;

unless vrealm_arr.empty?
  puts "Checking all fids on vRealm Priv Edge"
  vrealmcmd = "/tools-export/scripts/check_fids.rb -v #{opts[:vrealm]} -f " + vrealm_arr.join(" ") + " -r"
  vrealmout = `#{vrealmcmd}`
end

unless oss_arr.empty?
  puts "Checking all fids on OSS Priv Edge"
  osscmd = "/tools-export/scripts/check_fids.rb -v #{opts[:vrealm]} -f " + oss_arr.join(" ") + " -o"
  ossout = `#{osscmd}`
end

unless parent_arr.empty?
  puts "Checking all fids on Parent Priv Edge"
  parentcmd = "/tools-export/scripts/check_fids.rb -v #{opts[:parent_vpc]} -f " + parent_arr.join(" ") + " -r"
  parentout = `#{parentcmd}`
end

#list out all fids
puts "Here is a list of all FIDs that should be present"
unless fids.nil?
  pp fids
end

unless prxs_fids.nil?
  pp prxs_fids
end

puts "\n\n"
unless vrealm_arr.empty?
  puts '[ ' + 'INFO'.green + " ] Creating file #{vrealmfile} for vRealm Edge Fids"
  file = nil
  file = File.new(vrealmfile, "w+")
  file.write(vrealmout)
  file.close
end

unless oss_arr.empty?
  puts '[ ' + 'INFO'.green + " ] Creating file #{ossfile} for OSS Edge Fids"
  file = nil
  file = File.new(ossfile, "w+")
  file.write(ossout)
  file.close
end

unless parent_arr.empty?
  puts '[ ' + 'INFO'.green + " ] Creating file #{parentfile} for vRealm Parent Edge Fids"
  file = nil
  file = File.new(parentfile, "w+")
  file.write(parentout)
  file.close
end

