#!/usr/bin/env ruby

require 'rubygems'
$:.unshift File.expand_path('.',__dir__)
require 'DUML.rb'

port = $*[0]
if port == nil
    puts "Usage: PullUpgradeLogs.rb <serial port>"
    exit
end

con = DUML::ConnectionSerial.new(port)
@duml = DUML.new("1001", "0000", con, 5.0, false)

# Probe for the correct device
["0801", "1301", "2801"].each do |d|
    if @duml.cmd_dev_ping("1001", d, 0.05) != nil
        @duml.dst = d
        break
    end
end
puts "dst = %s" % @duml.dst

reply = @duml.cmd_common_get_cfg_file(2)
if reply && reply.length > 0
    File.open("upgrade_logs.tar.gz", "w+") { |file| file.write(reply) }
    puts "Logs written to upgrade_logs.tar.gz"
else
    puts "Failed to fetch the upgrade logs"
end

# vim: expandtab:ts=4:sw=4
