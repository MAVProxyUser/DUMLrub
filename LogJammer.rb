#!/usr/bin/env ruby

$:.unshift File.expand_path('.',__dir__)
require 'PullFtpFile.rb'

#puts "Please connect your DJI drone, verify the RNDIS is up, and press <enter>"
#gets

pullFtpFile = PullFtpFile.new

log = pullFtpFile.get("/upgrade/dji/log/upgrade00.log")
puts log 
File.open("upgrade00_logjam.txt", "w+") { |file| file.write(log) }
puts "file written to upgrade00_logjam.txt"

