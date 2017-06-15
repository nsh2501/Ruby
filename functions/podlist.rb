#!/usr/bin/env ruby

#functions
def f_pod_list (domain)

  case domain
  when 'prod'
    podList = [
      'd0p1', 
      'd0p2',
      'd2p3',
      'd3p4',
      'd4p5',
      'd5p6',
      'd7p7',
      'd8p8',
      'd0p9',
      'd9p10',
      'd3p12',
      'd2p13',
      'd4p14',
      'd10p15',
      'd11p16',
      'd3p17',
      'd12p21',
      'd0p23'
    ]
  when 'stage'
    podList = [
      'd2p2',
      'd4p1'
    ]
  end
  
  podList
end