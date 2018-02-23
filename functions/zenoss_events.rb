#!/usr/bin/env ruby

#zenoss function (turn into gem at some point soon for training)


def zen_alert_add(auth, severity, device, summary, component, evclasskey, evclass)
  require 'rest-client'


  #get zenoss url from function below
  url = zen_url(device) + '/zport/dmd/evconsole_router'

  #build payload
  payload = {}
  payload['action'] = 'EventsRouter'
  payload['method'] = 'add_event'
  payload['data'] = [{'summary'   => summary,
                    'device' => device,
                    'component' => component.split('(')[0],
                    'severity'  => severity,
                    'evclasskey' => evclasskey,
                    'evclass'    => evclass
                    }]
  payload['tid'] = 1 

  #perform api call
  begin
    response = RestClient::Request.execute(method: :post, url: url,
      headers: {Authorization: auth, content_type: 'application/json'},
      verify_ssl: false,
      payload: payload.to_json)

    clear_line
    print '[ ' + 'INFO'.white + " ] Alert succesfully added to Zenoss for #{device}/#{component}"
    $logger.info "INFO - Alert succesfully added to Zenoss for #{device}/#{component}"

  rescue => e
    clear_line
    puts '[ ' + 'ERROR'.red + " ] Failed to make zenoss call. Please see below error"
    $logger.info "ERROR - Failed to make zenoss call. Please see below error. #{e.response}" if $logger
    puts e.response
  end
  
end

def zen_url(vcenter)
  #variables
  numbers = vcenter.scan(/\d+/).join(' ').split(' ')
  pod_id = 'd' + numbers[0] + 'p' + numbers[1]

  #Zenoss Regions
  us_east=%w(d12p18 d12p21 d3p12 d3p17 d3p4 d4p14 d4p5 d7p7)
  us_west=%w(d0p1 d0p2 d0p23 d0p9 d2p11 d2p13 d2p3)
  emea=%w(d10p15 d11p16 d5p6 d8p8 d9p10)
  stage=%w(d2p2 d4p1)

  #urls
  urls={'STAGE' => 'https://zenoss5.d2p2oss-zenoss-ccenter-us-west.stage.vpc.vmw',
        'EAST' => 'https://zenoss5.d0p1oss-zenoss-ccenter-us-east.prod.vpc.vmw',
        'WEST' => 'https://zenoss5.d0p1oss-zenoss-ccenter-us-west.prod.vpc.vmw',
        'EMEA' => 'https://zenoss5.d0p1oss-zenoss-ccenter-emea-apac.prod.vpc.vmw',
        'GOM' => 'https://zenoss5.d0p1oss-zenoss-ccenter-gom.prod.vpc.vmw'
      }

  #determine region and URL
  case 
  when us_east.include?(pod_id)
    url = urls['EAST']
  when us_west.include?(pod_id)
    url = urls['WEST']
  when emea.include?(pod_id)
    url = urls['EMEA']
  when stage.include?(pod_id)
    url = urls['STAGE']
  else
    puts 'failed to find region'
    raise 'ERROR'
  end
  return url
end