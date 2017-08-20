#!/usr/bin/env ruby

require 'rubygems'
$:.unshift File.expand_path('.',__dir__)
require 'DUML.rb'

dst = 0x28 # Aircraft
dst = 0x2d # RC

con = DUML::ConnectionSerial.new("/dev/tty.usbmodem1425")
@duml = DUML.new(0x2a, dst, con, 1.0, false)
reply = @duml.cmd_common_get_cfg_file(2)
File.open("upgrade_logs.tar.gz", "w+") { |file| file.write(reply) }
puts "Logs written to upgrade_logs.tar.gz"

# vim: expandtab:ts=4:sw=4
