#!/usr/bin/env ruby2.4

require 'rubygems'
require 'serialport'
require 'net/http'
require 'net/ftp'
require 'socket'
require 'digest'
require 'colorize'
$:.unshift File.expand_path('.',__dir__)
require 'DUML.rb'

class Upgrade
    def initialize(filename: "dji_system.bin", src: 0x2a, dst: 0x28, path: 2, type: 4, connection:, debug: false)
        @filename = filename
        if not File.file?(@filename)
            raise "#{@filename} doesn't exists"
        end
        @data = File.read(@filename).unpack("C*")
        @duml = DUML.new(src: src, dst: dst, connection: connection, timeout: 1.0, debug: debug)
        @path = path
        @type = type
        @debug = debug
    end

    def upgrade_status(msg:)
        case msg.payload[0]
        when 1
            print "  Upgrade not yet started\r"
        when 3
            print "  Upgrade in progress: %2d %%\r" % msg.payload[1]
        when 4
            puts "Upgrade complete, status %02x %02x" % [ msg.payload[1], msg.payload[2] ]
            #@duml.cmd_stop_push() <-- Can't do this from this context, it locks up the read thread.
            @done = true
        end
        puts if @debug
        $stdout.flush
    end

    def go
        @done = false;

        # Register a callback to get upgrade progress notification
        @duml.register_handler(set: 0x00, id: 0x42) do |msg| upgrade_status(msg: msg); end

        puts ("Talking to: " + @duml.cmd_query_device_info()).yellow
        puts ("            " + @duml.cmd_dev_ver_get()).yellow

        # Get the cfg.sig file of the last upgrade to parse out the version string.
        # It's a full-featured IM*H file, but I got lazy and just regex'ed the version string out of it...
        reply = @duml.cmd_common_get_cfg_file(type: 1)
        puts ("            " + reply.scan( /<firmware formal="([^"]*)">/).first.last).yellow

        # Here we go...
        @duml.cmd_enter_upgrade_mode()

        # Request upgrade progress notifications
        @duml.cmd_report_status()

        reply = @duml.cmd_upgrade_data(filesize: @data.length, path: @path, type: @type)
        if reply == nil
            puts "Error...".red
            exit
        elsif reply[:ftp] == true
            ftp_transfer_file(reply[:address], reply[:port], reply[:targetfile])
        else
            duml_transfer_file(reply[:transfer_size])
        end

        md5 = Digest::MD5.new
        md5 << File.read(@filename)
        @duml.cmd_finish_upgrade_data(md5: md5.digest.unpack("C*"))

        # Sleep until the progress callback tells us we're done.
        # TODO: a timeout would be nice...
        # TODO: a condition/wait would be also be nicer than a sleep() in a loop...
        loop do
            sleep(1)
            break if @done
        end

        # We no longer need the upgrade progress notifications
        @duml.cmd_stop_push()

        # Read out the version after the upgrade.
        reply = @duml.cmd_common_get_cfg_file(type: 1)
        puts ("Currently running: " + reply.scan( /<firmware formal="([^"]*)">/).first.last).yellow
    end

    def ftp_transfer_file(address, port, targetfile)
        puts "Transfering upgrade data over ftp: %s:%d -> %s" % [ address, port, targetfile ]
        ftp = Net::FTP.new(address, port)
        ftp.passive = true
        ftp.login("root", "Big~9China")
        begin
            firmware = File.new(@filename)
            ftp.putbinaryfile(firmware, targetfile)
        rescue Net::FTPPermError
            puts "FTP Error"
        end
        ftp.close
    end

    def duml_transfer_file(max_transfer_size)
        puts "Transferring upgrade data over duml messages"
        left = @data.length
        index = 0
        while left > 0
            transfer = [ left, max_transfer_size ].min
            @duml.cmd_transfer_upgrade_data(index: index, data: @data[index * max_transfer_size, transfer])

            index += 1
            left -= transfer
        end
    end
end

if __FILE__ == $0
    # debugging

    #con = DUML::Connection.new
    #con = DUML::ConnectionSocket.new("localhost", 19003)
    #con = DUML::ConnectionSocket.new("192.168.1.1", 19003)
    con = DUML::ConnectionSerial.new("/dev/tty.usbmodem1425")

    #aircraft = Upgrade.new(connection: con, debug: false)
    #aircraft.go
    mavic_rc = Upgrade.new(dst: 0x2d, connection: con, debug: false)
    mavic_rc.go
    #googles =  Upgrade.new(dst: 0x3c, connection: con)
    #spark_rc = Upgrade.new(filename: "fw.tar", src: 0x02, dst: 0x1b, path: 1, connection: con)
    #spark_rc.go
end

# vim: expandtab:ts=4:sw=4
