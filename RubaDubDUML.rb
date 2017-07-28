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

# Ruby CRC code adapted from: 
# https://github.com/zachhale/ruby-crc16/blob/master/crc16.rb
# DJI CRC table from:
# https://github.com/dji-sdk/Guidance-SDK/blob/master/examples/uart_example/crc16.cpp
# const unsigned short CRC_INIT = 0x3692; //0x7000;  //dji naza
# Initial seed confirmed:
# https://github.com/mefistotelis/phantom-firmware-tools/issues/25#issue-215926316

class PwnSauce
    def crc16(buf)
        crc_lookup = [
            0x0000, 0x1189, 0x2312, 0x329b, 0x4624, 0x57ad, 0x6536, 0x74bf,
            0x8c48, 0x9dc1, 0xaf5a, 0xbed3, 0xca6c, 0xdbe5, 0xe97e, 0xf8f7, 
            0x1081, 0x0108, 0x3393, 0x221a, 0x56a5, 0x472c, 0x75b7, 0x643e,
            0x9cc9, 0x8d40, 0xbfdb, 0xae52, 0xdaed, 0xcb64, 0xf9ff, 0xe876,
            0x2102, 0x308b, 0x0210, 0x1399, 0x6726, 0x76af, 0x4434, 0x55bd,
            0xad4a, 0xbcc3, 0x8e58, 0x9fd1, 0xeb6e, 0xfae7, 0xc87c, 0xd9f5,
            0x3183, 0x200a, 0x1291, 0x0318, 0x77a7, 0x662e, 0x54b5, 0x453c,
            0xbdcb, 0xac42, 0x9ed9, 0x8f50, 0xfbef, 0xea66, 0xd8fd, 0xc974,
            0x4204, 0x538d, 0x6116, 0x709f, 0x0420, 0x15a9, 0x2732, 0x36bb,
            0xce4c, 0xdfc5, 0xed5e, 0xfcd7, 0x8868, 0x99e1, 0xab7a, 0xbaf3,
            0x5285, 0x430c, 0x7197, 0x601e, 0x14a1, 0x0528, 0x37b3, 0x263a,
            0xdecd, 0xcf44, 0xfddf, 0xec56, 0x98e9, 0x8960, 0xbbfb, 0xaa72,
            0x6306, 0x728f, 0x4014, 0x519d, 0x2522, 0x34ab, 0x0630, 0x17b9,
            0xef4e, 0xfec7, 0xcc5c, 0xddd5, 0xa96a, 0xb8e3, 0x8a78, 0x9bf1,
            0x7387, 0x620e, 0x5095, 0x411c, 0x35a3, 0x242a, 0x16b1, 0x0738,
            0xffcf, 0xee46, 0xdcdd, 0xcd54, 0xb9eb, 0xa862, 0x9af9, 0x8b70,
            0x8408, 0x9581, 0xa71a, 0xb693, 0xc22c, 0xd3a5, 0xe13e, 0xf0b7,
            0x0840, 0x19c9, 0x2b52, 0x3adb, 0x4e64, 0x5fed, 0x6d76, 0x7cff,
            0x9489, 0x8500, 0xb79b, 0xa612, 0xd2ad, 0xc324, 0xf1bf, 0xe036,
            0x18c1, 0x0948, 0x3bd3, 0x2a5a, 0x5ee5, 0x4f6c, 0x7df7, 0x6c7e,
            0xa50a, 0xb483, 0x8618, 0x9791, 0xe32e, 0xf2a7, 0xc03c, 0xd1b5,
            0x2942, 0x38cb, 0x0a50, 0x1bd9, 0x6f66, 0x7eef, 0x4c74, 0x5dfd,
            0xb58b, 0xa402, 0x9699, 0x8710, 0xf3af, 0xe226, 0xd0bd, 0xc134,
            0x39c3, 0x284a, 0x1ad1, 0x0b58, 0x7fe7, 0x6e6e, 0x5cf5, 0x4d7c,
            0xc60c, 0xd785, 0xe51e, 0xf497, 0x8028, 0x91a1, 0xa33a, 0xb2b3,
            0x4a44, 0x5bcd, 0x6956, 0x78df, 0x0c60, 0x1de9, 0x2f72, 0x3efb,
            0xd68d, 0xc704, 0xf59f, 0xe416, 0x90a9, 0x8120, 0xb3bb, 0xa232,
            0x5ac5, 0x4b4c, 0x79d7, 0x685e, 0x1ce1, 0x0d68, 0x3ff3, 0x2e7a,
            0xe70e, 0xf687, 0xc41c, 0xd595, 0xa12a, 0xb0a3, 0x8238, 0x93b1,
            0x6b46, 0x7acf, 0x4854, 0x59dd, 0x2d62, 0x3ceb, 0x0e70, 0x1ff9,
            0xf78f, 0xe606, 0xd49d, 0xc514, 0xb1ab, 0xa022, 0x92b9, 0x8330, 
            0x7bc7, 0x6a4e, 0x58d5, 0x495c, 0x3de3, 0x2c6a, 0x1ef1, 0x0f78]
        crc = 0x3692
        buf.each_byte do |b|
            crc = ((crc >> 8) & 0xff) ^ crc_lookup[(crc ^ b) & 0xff]
        end
        crc
    end

    def pwn(port_str, filename)

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

        puts "To debug, if you have root: busybox tail -f /ftp/upgrade/dji/log/upgrade00.log" 

        # Enter upgrade mode (delete old file if exists) - 0x7:received cmd to request enter upgrade mode, peer_id=0xa01, this_host=0x801
        upgradeMode = "\x55\x16\x04\xFC\x2A\x28\x65\x57\x40\x00\x07\x00\x00\x00\x00\x00\x00\x00\x00\x00\x27\xD3"
        sp.write upgradeMode
        #puts "0x7:received cmd to request enter upgrade mode, peer_id=0xa01, this_host=0x801"
        sleep(2)

        # This *can* be skipped
        # Enable Reporting - report status:  0:0 
        enableReporting = "\x55\x0E\x04\x66\x2A\x28\x68\x57\x40\x00\x0C\x00\x88\x20"
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
            ftp.putbinaryfile(firmware, "/upgrade/dji_system.bin")
        #    puts ftp.ls("/upgrade/dji_system.bin")
            puts "File upload is done"
        rescue Net::FTPPermError
            puts "Werid FTP problem... unable to put the firmware .bin file"
        end
        ftp.close

        # Send image size - 0x8:whole image size: YYYYYYYY, path = 2, type = 4
        # 551A04B12A286B5740000800YYYYYYYY0000000000000204XXXX
        # YYYYYYYY - file size in little endian
        # XXXX - CRC 

        puts "Getting size of file #{filename}"
        filesize = File.size?("#{filename}")
        #puts "File size is #{filesize}"
 
        size = Array(filesize).pack('V') # Jump through hoops to pack the Fixnum as a String! Must do the same for crc
        size = size.to_s.force_encoding('UTF-8') 

        # At this point the buffer should be as follows. This is a comparison of code notes in pyduml by hdnes. 
        # 55 1A 04 B1 2A 28 6B 57 40 00 08 00 YY YY YY YY 00 00 00 00 00 00 02 04 XX XX

        imageSizePlusType_preCRC =  "\x55\x1A\x04\xB1\x2A\x28\x6B\x57\x40\x00\x08\x00" + size + "\x00\x00\x00\x00\x00\x00\x02\x04" 
        # ‘dji_system.bin’ - "00 00 00 00 00 00 02 04"
        # ‘data_copy.bin’ -  "00 00 00 00 00 00 02 08"

        crc = crc16(imageSizePlusType_preCRC) # jumping through same hoop we did for size 
        crc = Array(crc).pack('V')
        crc = crc.to_s.force_encoding('UTF-8')

        imageSizePlusType = imageSizePlusType_preCRC + crc
        sp.write imageSizePlusType
        puts "0x8:whole image size: #{filesize}, path = 2, type = 4"
        sleep(2)

        # File Verification and Start Upgrade - "0xa:Receive transfer complete message."
        startUpgrade = "\x55\x1E\x04\x8A\x2A\x28\xF6\x57\x40\x00\x0A\x00\x66\x02\xC2\x6E\xD0\x72\x95\x81\x24\x68\x53\xD7\xC9\x88\xA4\xAE\x7A\xE4"
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
    exploit.pwn("#{$*[0]}", "#{$*[1]}")
else 
    puts "imported RubaDubDUML code"
end

