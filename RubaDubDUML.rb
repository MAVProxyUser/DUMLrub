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
require 'serialport'
require 'net/http'
require 'net/ftp'
$:.unshift File.expand_path('.',__dir__)
require 'DUML.rb'

# Ruby CRC code adapted from: 
# https://github.com/zachhale/ruby-crc16/blob/master/crc16.rb
# DJI CRC table from:
# https://github.com/dji-sdk/Guidance-SDK/blob/master/examples/uart_example/crc16.cpp
# const unsigned short CRC_INIT = 0x3692; //0x7000;  //dji naza
# Initial seed confirmed:
# https://github.com/mefistotelis/phantom-firmware-tools/issues/25#issue-215926316

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
            exit
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

        baud_rate = 115200  
        data_bits = 8  
        stop_bits = 1  
        parity = SerialPort::NONE  

        puts "Connecting to serial: #{port_str}"
        sp = SerialPort.new(port_str, baud_rate, data_bits, stop_bits, parity)  

        puts "To debug, if you have root: busybox tail -f /ftp/upgrade/dji/log/upgrade00.log | grep -v sys_up_status_push_threa"

        duml = DUML.new(0x2a, 0x28)

        # Enter upgrade mode (delete old file if exists) - 0x7:received cmd to request enter upgrade mode, peer_id=0xa01, this_host=0x801
        upgradeMode = duml.gen(0x40, 0x00, 0x07, [ 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 ])
        sp.write upgradeMode
        #puts "0x7:received cmd to request enter upgrade mode, peer_id=0xa01, this_host=0x801"
        sleep(2)

        # This *can* be skipped
        # Enable Reporting - report status:  0:0 
        enableReporting = duml.gen(0x40, 0x00, 0x0C, [ 0x00 ])
        #sp.write enableReporting
        #puts "report status:  0:0"
        # sleep(2)

        # Drop upgrade package. 
        ftp = Net::FTP.new('192.168.42.2')
        ftp.passive = true
        ftp.login("RubaDubDUML","IsDaRealest!" )
        puts "Logged into the FTPD"
        begin
            firmware = File.new(filename)
            puts "Dropping the hot sauce"
            if type == "nfz"
                ftp.putbinaryfile(firmware, "/upgrade/data_copy.bin")
            else
                ftp.putbinaryfile(firmware, "/upgrade/dji_system.bin")
            end
            puts "File upload is done"
        rescue Net::FTPPermError
            puts "Weird FTP problem... unable to put the firmware .bin file"
        end
        ftp.close

        # Send image size - 0x8:whole image size: YYYYYYYY, path = 2, type = 4
        # 551A04B12A286B5740000800YYYYYYYY0000000000000204XXXX
        # YYYYYYYY - file size in little endian
        # XXXX - CRC 

        puts "Getting size of file #{filename}"
        filesize = File.size?("#{filename}")
        #puts "File size is #{filesize}"
 
        # At this point the buffer should be as follows. This is a comparison of code notes in pyduml by hdnes. 
        # 55 1A 04 B1 2A 28 6B 57 40 00 08 00 YY YY YY YY 00 00 00 00 00 00 02 04 XX XX

        if type == "nfz"
            # ‘data_copy.bin’ -  "00 00 00 00 00 00 02 08"
            imageSizePlusType = duml.gen(0x40, 0x00, 0x08, [ 0x00 ] + [ filesize ].pack("L<").unpack("CCCC") + [ 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x02, 0x08 ])
        else
            # ‘dji_system.bin’ - "00 00 00 00 00 00 02 04"
            imageSizePlusType = duml.gen(0x40, 0x00, 0x08, [ 0x00 ] + [ filesize ].pack("L<").unpack("CCCC") + [ 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x02, 0x04 ])
        end

        sp.write imageSizePlusType
        puts "0x8:whole image size: #{filesize}, path = 2, type = 4"
        sleep(2)

        # File Verification and Start Upgrade - "0xa:Receive transfer complete message."
        startUpgrade = duml.gen(0x40, 0x00, 0x0a, [ 0x00, 0x66, 0x02, 0xC2, 0x6E, 0xD0, 0x72, 0x95, 0x81, 0x24, 0x68, 0x53, 0xD7, 0xC9, 0x88, 0xA4, 0xAE ])
        sp.write startUpgrade
        puts "0xa:Receive transfer complete message."
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
