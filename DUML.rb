#!/usr/bin/env ruby

require 'rubygems'
require 'colorize'
require 'serialport'
require 'socket'

# Ruby CRC code adapted from:
# https://github.com/zachhale/ruby-crc16/blob/master/crc16.rb
# DJI CRC table from:
# https://github.com/dji-sdk/Guidance-SDK/blob/master/examples/uart_example/crc16.cpp
# const unsigned short CRC_INIT = 0x3692; //0x7000;  //dji naza
# Initial seed confirmed:
# https://github.com/mefistotelis/phantom-firmware-tools/issues/25#issue-215926316
# header crc code adapted from:
# comm_serial2pcap.py
# https://github.com/mefistotelis/phantom-firmware-tools/issues/25#issuecomment-306052129

class DUML
    attr_accessor :src, :dst, :timeout, :debug

    class Connection
        attr_accessor :debug

        def write(msg)
            puts ("    " + msg.to_s).green if @debug
        end

        def read(len)
            sleep(3600)
            return ARGF.read(len)
        end
    end

    class ConnectionRetry < DUML::Connection
        def read(len)
            buf = nil
            loop do
                if @con == nil
                    begin
                        open_connection
                        puts "Connection restored." if @debug
                    rescue
                        @count += 1
                        if @count == 20
                            puts "Waited long enough for the connection to restore..."
                            exit
                        end
                        sleep(1)
                        next
                    end
                end
                buf = @con.read(len)
                if buf == nil
                    puts "Connection lost..." if @debug
                    @con = nil
                    @count = 0
                    next
                else
                    break
                end
            end
            return buf
        end

        def write(msg)
            loop do
                if @con != nil
                    super(msg)
                    @con.write(msg.raw)
                    break
                else
                    sleep(1)
                    next
                end
            end
        end
    end

    class ConnectionSerial < DUML::ConnectionRetry
        def initialize(port)
            @port = port
            open_connection
        end

        def open_connection
            baud_rate = 115200
            data_bits = 8
            stop_bits = 1
            parity = SerialPort::NONE

            @con = SerialPort.new(@port, baud_rate, data_bits, stop_bits, parity)
        end
    end

    class ConnectionSocket < DUML::ConnectionRetry
        def initialize(hostname, port)
            @hostname = hostname
            @port = port
            open_connection
        end

        def open_connection
            @con = TCPSocket.open(@hostname, @port)
        end
    end


    class Msg
        attr_accessor :src, :dst, :seq_no, :attributes, :set, :id, :payload

        @@seq_no = 0x1234

        def self.addr_to_hex(a)
            if not a.is_a?(String)
                return a
            end
            if a.length != 4
                raise
            end
            return (a[0..1].to_i & 0x1f) | ((a[2..3].to_i & 0x07) << 5)
        end

        def self.addr_to_dec(a)
            if a.is_a?(String)
                return a
            end
            return "%02d%02d" % [ a & 0x1f, a >> 5 ]
        end

        def initialize(src = "1001", dst = "0801", attributes = 0x00, set = 0x00, id = 0x00, payload = [], seq_no = @@seq_no)
            src = Msg.addr_to_hex(src)
            dst = Msg.addr_to_hex(dst)
            @src = src; @dst = dst; @seq_no = seq_no; @attributes = attributes
            @set = set; @id = id; @payload = payload
            @@seq_no += 1
        end

        def self.from_bytes(buf)
            data = buf.unpack("CS<CCCS<CCC")
            Msg.new(data[3], data[4], data[6], data[7], data[8], buf[11..-3].unpack("C*"), data[5])
        end

        def raw
            length = 13 + @payload.length
            buf = [ 0x55, length & 0xff, 0x04 | length >> 8 ].pack("CCC")
            buf += [ DUML.crc_hdr(buf), @src, @dst, @seq_no, @attributes, @set, @id ].pack("CCCS<CCC")
            buf += payload.pack("C*")
            buf += [ DUML.crc16(buf) ].pack("S<")
            buf
        end

        def to_s
            out = "from: %s   to: %s   seq_no: %5d   attr: %02x   set: %02x   id: %02x   payload:" %
                [ Msg.addr_to_dec(@src), Msg.addr_to_dec(@dst), @seq_no, @attributes, @set, @id ]
            @payload.each_entry { |b| out += " %02x" % b }
            out
        end

        def to_s_short
            out = "%s -> %s (%d) %02x %02x %02x" %
                [ Msg.addr_to_dec(@src), Msg.addr_to_dec(@dst), @seq_no, @attributes, @set, @id ]
            out
        end
    end

    def initialize(src = "1001", dst = "0801", connection = nil, timeout = 5, debug = true)
        @src = src; @dst = dst; @connection = connection
        @timeout = timeout; @debug = debug

        if @connection != nil
            @connection.debug = @debug
            @requests = {}
            @handlers = {}
            @requests_mutex = Mutex.new

            @read_thread = Thread.new{read_from_connection(@connection)}
            @read_thread.abort_on_exception = true
            #read_from_connection(@connection)
        end
    end

    def self.crc16(buf)
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

    def self.crc_hdr(buf)
        crc_lookup = [
            0x00, 0x5E, 0xBC, 0xE2, 0x61, 0x3F, 0xDD, 0x83,
            0xC2, 0x9C, 0x7E, 0x20, 0xA3, 0xFD, 0x1F, 0x41,
            0x9D, 0xC3, 0x21, 0x7F, 0xFC, 0xA2, 0x40, 0x1E,
            0x5F, 0x01, 0xE3, 0xBD, 0x3E, 0x60, 0x82, 0xDC,
            0x23, 0x7D, 0x9F, 0xC1, 0x42, 0x1C, 0xFE, 0xA0,
            0xE1, 0xBF, 0x5D, 0x03, 0x80, 0xDE, 0x3C, 0x62,
            0xBE, 0xE0, 0x02, 0x5C, 0xDF, 0x81, 0x63, 0x3D,
            0x7C, 0x22, 0xC0, 0x9E, 0x1D, 0x43, 0xA1, 0xFF,
            0x46, 0x18, 0xFA, 0xA4, 0x27, 0x79, 0x9B, 0xC5,
            0x84, 0xDA, 0x38, 0x66, 0xE5, 0xBB, 0x59, 0x07,
            0xDB, 0x85, 0x67, 0x39, 0xBA, 0xE4, 0x06, 0x58,
            0x19, 0x47, 0xA5, 0xFB, 0x78, 0x26, 0xC4, 0x9A,
            0x65, 0x3B, 0xD9, 0x87, 0x04, 0x5A, 0xB8, 0xE6,
            0xA7, 0xF9, 0x1B, 0x45, 0xC6, 0x98, 0x7A, 0x24,
            0xF8, 0xA6, 0x44, 0x1A, 0x99, 0xC7, 0x25, 0x7B,
            0x3A, 0x64, 0x86, 0xD8, 0x5B, 0x05, 0xE7, 0xB9,
            0x8C, 0xD2, 0x30, 0x6E, 0xED, 0xB3, 0x51, 0x0F,
            0x4E, 0x10, 0xF2, 0xAC, 0x2F, 0x71, 0x93, 0xCD,
            0x11, 0x4F, 0xAD, 0xF3, 0x70, 0x2E, 0xCC, 0x92,
            0xD3, 0x8D, 0x6F, 0x31, 0xB2, 0xEC, 0x0E, 0x50,
            0xAF, 0xF1, 0x13, 0x4D, 0xCE, 0x90, 0x72, 0x2C,
            0x6D, 0x33, 0xD1, 0x8F, 0x0C, 0x52, 0xB0, 0xEE,
            0x32, 0x6C, 0x8E, 0xD0, 0x53, 0x0D, 0xEF, 0xB1,
            0xF0, 0xAE, 0x4C, 0x12, 0x91, 0xCF, 0x2D, 0x73,
            0xCA, 0x94, 0x76, 0x28, 0xAB, 0xF5, 0x17, 0x49,
            0x08, 0x56, 0xB4, 0xEA, 0x69, 0x37, 0xD5, 0x8B,
            0x57, 0x09, 0xEB, 0xB5, 0x36, 0x68, 0x8A, 0xD4,
            0x95, 0xCB, 0x29, 0x77, 0xF4, 0xAA, 0x48, 0x16,
            0xE9, 0xB7, 0x55, 0x0B, 0x88, 0xD6, 0x34, 0x6A,
            0x2B, 0x75, 0x97, 0xC9, 0x4A, 0x14, 0xF6, 0xA8,
            0x74, 0x2A, 0xC8, 0x96, 0x15, 0x4B, 0xA9, 0xF7,
            0xB6, 0xE8, 0x0A, 0x54, 0xD7, 0x89, 0x6B, 0x35]

        crc = 0x77
        buf.each_byte do |b|
            crc = crc_lookup[(crc ^ b) & 0xff]
        end
        crc
    end

    # -------------------------------------------------------------------------------------------------------------

    def cmd_dev_ping(src = @src, dst = @dst, timeout = @timeout) # 0x00
        reply = send(Msg.new(src, dst, 0x40, 0x00, 0x00), timeout)
        return reply
    end

    def cmd_dev_ver_get(src = @src, dst = @dst, timeout = @timeout) # 0x01
        reply = send(Msg.new(src, dst, 0x40, 0x00, 0x01), timeout)
        # 00 12 57 4d 32 32 30 20 52 43 20 56 65 72 2e 41 00 00 17 00 05 01 17 00 05 01 01 00 00 80 00
        # WM220 RC Ver.A                                        23  0  5  1 23  0  5  1  1  0  0 128 0
        # 00 12 57 4d 32 32 30 20 41 43 20 56 65 72 2e 41 00 00 14 00 05 01 14 00 05 01 01 00 00 80 00
        # WM220 AC Ver.A                                        20  0  5  1 20  0  5  1  1  0  0 128 0
        versions = {}
        if reply
            ver_ldr = reply.payload[18..21]
            ver_app = reply.payload[22..25]
            versions[:loader] = ("%02d.%02d.%02d.%02d" % [ ver_ldr[3], ver_ldr[2], ver_ldr[1], ver_ldr[0] ])
            versions[:app]    = ("%02d.%02d.%02d.%02d" % [ ver_app[3], ver_app[2], ver_app[1], ver_app[0] ])
            versions[:string] = reply.payload[2..16].pack("C*")
            versions[:full]   = versions[:string] + "  Loader: " + versions[:loader] + "  App: " + versions[:app]
        end
        return versions
    end

    def cmd_enter_upgrade_mode() # 0x07
        reply = send(Msg.new(@src, @dst, 0x40, 0x00, 0x07,
            [ 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 ]))
        # reply payload: 00 03 0f
        return reply
    end

    def cmd_upgrade_data(filesize, path = 0, type = 0) # 0x08
        reply = send(Msg.new(@src, @dst, 0x40, 0x00, 0x08,
                [ 0x00 ] + [ filesize ].pack("L<").unpack("CCCC") + [ 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, path, type ]))

        # payload mavic/mavic rc:
        # 00 02 2a a8 c0 15 00 2f 75 70 67 72 61 64 65 2f 64 6a 69 5f 73 79 73 74 65 6d 2e 62 69 6e 00
        #    IP IP IP IP PR    /  u  p  g  r  a  d  e  /  d  j  i  _  s  y  s  t  e  m  .  b  i  n
        # payload spark rc:
        # 00 e8 03
        #    SZ SZ

        if reply == nil
            return nil
        elsif (reply.payload.length == 3) || (reply.payload.length == 5)
            transfer_size = reply.payload[1..2].pack("C*").unpack("S<")
            return { transfer_size: transfer_size, ftp: false }
        elsif reply.payload.length == 263
            address = "%d.%d.%d.%d" % reply.payload[1..4].reverse
            port = "%d" % reply.payload[5]
            targetfile = reply.payload[7..-1].pack("C*").strip
            return { address: address, port: port, targetfile: targetfile, ftp: true }
        else
            puts ("Unsupported reply: " + reply.to_s).red
            return reply
        end
    end

    def cmd_transfer_upgrade_data(index, data, enc = 0) # 0x09
        send(Msg.new(@src, @dst, 0x00, 0x00, 0x09,
            [ enc ] + [ index ].pack("L<").unpack("CCCC") + [ data.length ].pack("S<").unpack("CC") + data))
    end

    def cmd_finish_upgrade_data(md5) # 0x0a
        reply = send(Msg.new(@src, @dst, 0x40, 0x00, 0x0a,
            [ 0x00 ] + md5))
        return reply
    end

    def cmd_report_status() # 0x0c
        reply = send(Msg.new(@src, @dst, 0x40, 0x00, 0x0c, [ 0x00 ]))
        # reply payload: 00 00 01 00 00 00
        return reply
    end

    def cmd_stop_push() # 0x41
        reply = send(Msg.new(@src, @dst, 0x40, 0x00, 0x41, [ 0x04 ]))
        return reply
    end

    def cmd_set_date(time, src = @src, dst = @dst, timeeout = @timeout) # 0x4a
        t = [ time.year, time.month, time.day, time.hour, time.min, time.sec ]
        reply = send(Msg.new(src, dst, 0x40, 0x00, 0x4a, t.pack("S<CCCCC").unpack("C*")), timeout)
        return reply
    end

    def cmd_get_date() # 0x4b
        # TODO: Parse the reply
        reply = send(Msg.new(src, dst, 0x40, 0x00, 0x4b, [ 0x00 ]), timeout)
        return reply
    end

    def cmd_common_get_cfg_file(type, src = @src, dst = @dst, timeout = @timeout) # 0x4f
        buf = ""
        remaining = 0xffffffff
        length = 0xffffffff
        offset = 0
        loop do
            reply = send(Msg.new(src, dst, 0x40, 0x00, 0x4f,
                                 [ type, offset, length ].pack("CL<L<").unpack("C*")), timeout)

            break if reply == nil
            remaining = reply.payload[5..8].pack("C*").unpack("L<")[0]
            length = reply.payload[1..4].pack("C*").unpack("L<")[0]
            offset += length
            buf += reply.payload[9..-1].pack("C*")
            break if remaining == 0
        end

        return buf
    end

    def cmd_query_device_info(src = @src, dst = @dst, timeout = @timeout) # 0xff
        reply = send(Msg.new(src, dst, 0x40, 0x00, 0xff), timeout)
        if reply != nil
            return reply.payload[1..-1].pack("C*")
        else
            return nil
        end
    end

    # -------------------------------------------------------------------------------------------------------------

    def send(msg, timeout = @timeout)
        if msg.attributes == 0x40
            req = {}
            req[:condition] = ConditionVariable.new
            @requests_mutex.synchronize do
                @requests[msg.seq_no] = req
                @connection.write(msg)
                req[:condition].wait(@requests_mutex, timeout)
                @requests.delete(msg.seq_no)

                recv_msg = req[:msg]
                if recv_msg == nil
                    puts ("<< TIMEOUT waiting for reply: " + msg.to_s_short + " >>").yellow if @debug
                end

                return recv_msg
            end
        else
            @connection.write(msg)
            return nil
        end
    end

    def register_handler(set, id, &block) # TODO: Add src & dst
        handler = {}
        handler[:block] = block
        @requests_mutex.synchronize do
            @handlers[ [ set, id ] ] = handler
        end
    end

    private

    def handle_incoming_message(msg)
        puts ("IN: " + msg.to_s).red if @debug

        if msg.attributes & 0x80 == 0x80 # It's a reply
            @requests_mutex.synchronize do
                req = @requests[msg.seq_no]
                if req != nil
                    req[:msg] = msg
                    req[:condition].signal
                else
                    puts "Unsolicited reply ? " + msg.to_s if @debug
                end
            end
        elsif (msg.attributes == 0x40) || (msg.attributes == 0x00)
            handler = nil
            @requests_mutex.synchronize do
                handler = @handlers[ [ msg.set, msg.id ] ] # TODO: Add src & dst
            end
            if handler != nil
                handler[:block].call(msg)
            end
        else
            puts "Weird message received: ".blue if @debug
        end
    end

    def read_from_connection(con)
        puts "Start reading from port" if @debug
        required_bytes = 4 # 0x55, length, proto+length & crc
        buf = []
        while true # TODO: Add a way to stop this thread

            # Attempt to read as many bytes as we currently require.
            if required_bytes > 0
                buf += con.read(required_bytes).unpack("C*")
            end

            # Do we have a start-of-frame ?
            if buf[0] != 0x55
                buf = buf[1..-1]
                required_bytes = [ 0, 4 - buf.length ].max
                next
            end

            # First byte is 0x55 and we have at least 4 bytes.
            # A potential header is complete -> validate length, protocol & header crc.
            if buf.length == 4
                length = buf[1] + (buf[2] & 0x03) * 256
                protocol = buf[2] >> 2
                if protocol != 1
                    # Wrong protocol or this 0x55 was not a start-of-frame.
                    # Skip the first byte (0x55) and start over looking for the next 0x55
                    buf = buf[1..-1]
                    required_bytes = [ 0, 4 - buf.length ].max
                    puts "Wrong protocol %02x" % protocol if @debug
                    next
                end

                if DUML::crc_hdr(buf[0..2].pack("C*")) != buf[3]
                    # Header CRC doesn't match.. This 0x55 was not a start-of-frame.
                    buf = buf[1..-1]
                    required_bytes = [ 0, 4 - buf.length ].max
                    puts "Header CRC failure" if @debug
                    next
                end
            end

            if buf.length < length
                required_bytes = length - buf.length
                next
            end

            if DUML::crc16(buf[0..-3].pack("C*")) != buf[-2..-1].pack("C*").unpack("S<")[0]
                # Message CRC doesn't match.. This 0x55 was not a start-of-frame.
                buf = buf[1..-1]
                required_bytes = [ 0, 4 - buf.length ].max
                puts "Message CRC failure" if @debug
                next
            end

            # Here the message is complete and all CRC's are valid !
            handle_incoming_message(DUML::Msg.from_bytes(buf.pack("C*")))

            # Start over
            buf = []
            required_bytes = 4
        end
    end

end

if __FILE__ == $0
    # debugging
end

# vim: expandtab:ts=4:sw=4
