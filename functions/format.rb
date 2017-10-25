require 'colorize'

def clear_line ()
  print "\r"
  print "                                                                                                                                       "
  print "\r"
end

def config_logger (log_level, script_name)
  #process ID
  pid = Process.pid

  if log_level == 'DEBUG'
    require 'logger'
    log_file = ENV['HOME'] + "/#{script_name}.log"
    logger = Logger.new(log_file)
    logger.progname = script_name
    logger.formatter = proc do |severity, datetime, progname, msg|
      date_format = datetime.strftime("%b %e %k:%M:%S")
      "#{date_format} #{ENV['HOSTNAME']} #{progname}[#{pid}]: #{msg}\n"
    end
    logger.level = Kernel.const_get 'Logger::' + log_level
    logger.info "INFO - Logging Initalized"
    clear_line
    puts '[ ' + 'INFO'.white + " ] Logging started, search for #{script_name}[#{pid}] in #{log_file} for logs"
  else
    require 'syslog/logger'
    logger = Syslog::Logger.new script_name
    logger.level = Kernel.const_get 'Logger::INFO'
    logger.info "INFO - Logging Initalized"
    clear_line
    puts '[ ' + 'INFO'.white + " ] Logging started, search for #{script_name}[#{pid}] in /var/log/messages for logs"
  end #end log_level

  return logger
end