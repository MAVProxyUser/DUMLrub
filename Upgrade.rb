#!/usr/bin/env ruby

require 'rubygems'
require 'rubygems/package'
require 'net/ftp'
require 'digest'
require 'colorize'
$:.unshift File.expand_path('.',__dir__)
require 'DUML.rb'

class Upgrade
    def initialize(filename = "dji_system.bin", src = 0x2a, dst = 0x28, path = 2, type = 4, connection = nil, debug = false)
        @filename = filename
        if not File.file?(@filename)
            raise "#{@filename} doesn't exists"
        end
        @data = File.read(@filename).unpack("C*")
        @duml = DUML.new(src, dst, connection, 1.0, debug)
        @path = path
        @type = type
        @debug = debug
    end

    def upgrade_status(msg)
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
        @duml.register_handler(0x00, 0x42) do |msg| upgrade_status(msg); end

	devinfo = @duml.cmd_query_device_info()
        if devinfo.nil?
            puts "There is no devinfo reply!?"
        else
         	puts ("Talking to: " + devinfo.yellow)
        end
	version = @duml.cmd_dev_ver_get()[:full]
        if version.nil?
            puts "There is no version reply!?"
        else
	        puts ("          " + version.yellow)
	end

        # Get the cfg.sig file of the last upgrade to parse out the version string.
        # It's a full-featured IM*H file, but I got lazy and just regex'ed the version string out of it...
        reply = @duml.cmd_common_get_cfg_file(1)
        puts ("            " + reply.scan( /<firmware formal="([^"]*)">/).first.last).yellow

        # Here we go...
        @duml.cmd_enter_upgrade_mode()

        # Request upgrade progress notifications
        @duml.cmd_report_status()

        reply = @duml.cmd_upgrade_data(@data.length, @path, @type)
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
        @duml.cmd_finish_upgrade_data(md5.digest.unpack("C*"))

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
        reply = @duml.cmd_common_get_cfg_file(1)
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
        max_transfer_size = max_transfer_size[0]
        index = 0
        while left > 0
            transfer = [ left, max_transfer_size ].min
            @duml.cmd_transfer_upgrade_data(index, @data[index * max_transfer_size, transfer])

            index += 1
            left -= transfer
        end
        puts "File Sent"
    end
end

def upgrade_file_info(path)
    f = File.new(path)
    t = Gem::Package::TarReader.new(f)
    t.each() do |entry|
        name = entry.full_name()
        if name.match( /\.cfg\.sig$/ )
            data = entry.read()
            device_id = data.scan( /<device id="([^"]*)">/).first.last
            formal_version = data.scan( /<firmware formal="([^"]*)">/).first.last

            return device_id, formal_version
        end
    end
    return nil, nil
end

if __FILE__ == $0
    # debugging

    dev, ver = upgrade_file_info("dji_system.bin")
    puts "%s -> %s" % [ dev, ver ]

    #con = DUML::Connection.new
    #con = DUML::ConnectionSocket.new("localhost", 19003)
    #con = DUML::ConnectionSocket.new("192.168.1.1", 19003)
    con = DUML::ConnectionSerial.new(ARGV[0])

    #aircraft = Upgrade.new("dji_system.bin", 0x2a, 0x28, 2, 4, con, false)
    #aircraft.go
    mavic_rc = Upgrade.new("dji_system.bin", 0x2a, 0x2d, 2, 4, con, false)
    mavic_rc.go
    #googles = Upgrade.new("dji_system.bin", 0x2a, 0x3c, 2, 4, con, false)
    #spark_rc = Upgrade.new("fw.tar", 0x02, 0x1b, 1, 4, con, false)
    #spark_rc.go
end

# vim: expandtab:ts=4:sw=4
