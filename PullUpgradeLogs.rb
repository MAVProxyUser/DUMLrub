#!/usr/bin/env ruby

require 'rubygems'
$:.unshift File.expand_path('.',__dir__)
require 'DUML.rb'

port = $*[0]
if port == nil
    puts "Usage: PullUpgradeLogs.rb <serial port>"
    exit
end

dst = 0x00
con = DUML::ConnectionSerial.new(port)
@duml = DUML.new(0x2a, dst, con, 5.0, false)

# Probe for the correct device
[0x28, 0x2d, 0x3c].each do |d|
    if @duml.cmd_dev_ping(0x2a, d, 0.05) != nil
        dst = d
        break
    end
end
puts "dst = 0x%02x" % dst

reply = @duml.cmd_common_get_cfg_file(2, 0x2a, dst)
if reply && reply.length > 0
    File.open("upgrade_logs.tar.gz", "w+") { |file| file.write(reply) }
    puts "Logs written to upgrade_logs.tar.gz"
else
    puts "Failed to fetch the upgrade logs"
end

# vim: expandtab:ts=4:sw=4
