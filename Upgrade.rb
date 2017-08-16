#!/usr/bin/env ruby2.4

require 'rubygems'
require 'serialport'
require 'net/http'
require 'net/ftp'
require 'socket'
require 'digest'
$:.unshift File.expand_path('.',__dir__)
require 'DUML.rb'

class Upgrade
    def initialize(filename: "dji_system.bin", targetfile: "dji_system.bin", src: 0x2a, dst: 0x28, path: 2, type: 4, ftp: true, connection:)
        @filename = filename
        if not File.file?(@filename)
            raise "#{@filename} doesn't exists"
        end
        @data = File.read(@filename).unpack("C*")
        @duml = DUML.new(src: src, dst: dst, connection: connection)
        @targetfile = targetfile
        @path = path
        @type = type
        @ftp = ftp
        @connection = connection
    end

    def init_upgrade
        @connection.write(@duml.cmd_enter_upgrade_mode())
        @connection.write(@duml.cmd_report_status())
        @connection.write(@duml.cmd_upgrade_data(filesize: @data.length, path: @path, type: @type))
    end

    def ftp_transfer_file
        ftp = Net::FTP.new('192.168.42.2')
        ftp.passive = true
        ftp.login("root", "Big~9China")
        begin
            firmware = File.new(@filename)
            ftp.putbinaryfile(firmware, "/upgrade/" + @targetfile)
        rescue Net::FTPPermError
            puts "FTP Error"
        end
        ftp.close
    end

    def duml_transfer_file
        @connection.write(@duml.cmd_upgrade_data(filesize: @data.length, path: @path, type: @type))
        # TODO: The reply to this command has the max block size to use for the transfer

        left = @data.length
        index = 0
        while left > 0
            transfer = [ left, 1000 ].min
            @connection.write(@duml.cmd_transfer_upgrade_data(index: index, data: @data[index * 1000, transfer]))

            index += 1
            left -= transfer
        end
    end

    def start_upgrade
        md5 = Digest::MD5.new
        md5 << File.read(@filename)
        @connection.write(@duml.cmd_finish_upgrade_data(md5: md5.digest.unpack("C*")))
    end

    def go
        init_upgrade
        if @ftp
            ftp_transfer_file()
        else
            duml_transfer_file()
        end
        start_upgrade
    end
end

if __FILE__ == $0
    # debugging

    #con = DUML::Connection.new
    #con = DUML::ConnectionSocket.new("localhost", 19003)
    #con = DUML::ConnectionSocket.new("192.168.1.1", 19003)
    con = DUML::ConnectionSerial.new("/dev/tty.usbmodem1425")

    #aircraft = Upgrade.new(connection: con)
    mavic_rc = Upgrade.new(dst: 0x2d, connection: con)
    mavic_rc.go
    #googles =  Upgrade.new(dst: 0x3c, connection: con)
    #spark_rc = Upgrade.new(filename: "fw.tar", src: 0x02, dst: 0x1b, path: 1, ftp: false, connection: con)
    #spark_rc.go
    sleep(120)
end

# vim: expandtab:ts=4:sw=4
