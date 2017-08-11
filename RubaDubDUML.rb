#!/usr/bin/env ruby
# RubaDubDUML.rb - tool to push DJI firmware files to P4, Spark, I2, or Mavic
# Props to hdnes, for his start on pyduml, from which this was based. 
# 
# To debug (via root access) use: busybox tail -f /ftp/upgrade/dji/log/upgrade00.log 
#
# To execute: 
# Run from command line
# $ ruby RubaDubDUML.rb /dev/tty.usbmodem1445 dji_system.bin
#
# Or import into your ruby code.  
# irb(main):002:0> require "./RubaDubDUML.rb"
# imported code
# => true
# irb(main):003:0> exploit = PwnSauce.new
# => #<PwnSauce:0x007fd85f04b548>
# irb(main):004:0> exploit.pwn("/dev/tty.usbmodemXX", "dji_system.bin")

require 'rubygems'
require 'net/http'
$:.unshift File.expand_path('.',__dir__)
require 'Upgrade.rb'

class PwnSauce

    def pwn(port_str, filename, type)

        # TODO: Add windows device check         

        # Product ID: 0x001f
        # Vendor ID:    0x2ca3
        devicecheck = %x[/usr/sbin/system_profiler SPUSBDataType | grep "DJI:" -A19]
        
        if devicecheck.include? "2ca3"
            puts "found DJI Aircraft\n"
        else
            puts "Plug in your drone... and try again\n"
            #exit
        end

        #     Auto Find serial? 
        #     Product ID: 0x001f
        #     Vendor ID: 0x2ca3
        #     Version: ff.ff
        #     Serial Number: 0123456789ABCDEF
        #     Speed: Up to 480 Mb/sec
        #     Manufacturer: DJI
        #     Location ID: 0x14300000 / 18
        # you can find this via # system_profiler SPUSBDataType
        # 
        # sh-3.2# ls -al /dev/tty.usbmodem1435 
        # crw-rw-rw-  1 root  wheel   19,  46 Jul 12 23:40 /dev/tty.usbmodem1435
        # note the 0x143... and usbmodem143...

        puts "Connecting to serial: #{port_str}"
        output = UpgradeOutputSerial.new(port_str)

        puts "To debug, if you have root: busybox tail -f /ftp/upgrade/dji/log/upgrade00.log | grep -v sys_up_status_push_threa"

        upgrade = Upgrade.new(filename: filename, connection: output)
        upgrade.go

        Net::HTTP.start("www.openpilotlegacy.org") do |http| resp = http.get("/RubaDubDUML.txt") end # Old Beta Release Leak Control... you can remove this
    end

end

# Check if run from command line, or as an import
if __FILE__ == $0
    puts "Running: #{$0} from command line"
    puts "Using: #{$*[0]} for serial port"
    exploit = PwnSauce.new
    exploit.pwn("#{$*[0]}", "#{$*[1]}", "")
else 
    puts "imported RubaDubDUML code"
end

# vim: expandtab:ts=4:sw=4
