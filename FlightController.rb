#!/usr/bin/env ruby

require 'rubygems'
require 'colorize'
require 'json'
require 'jsonable'
require 'optparse'
$:.unshift File.expand_path('.',__dir__)
require 'DUML.rb'

class FlightController

    class Param
        attr_accessor :table, :item, :type, :length, :default, :value, :min, :max, :name, :packing

        @@packings = [ "C", "S<", "L<", "", "c", "s", "l<", "", "e" ]
        @@types = [ "uint8", "uint16", "uint32", "uint64", "int8", "int16", "int32", "int64", "float" ]

        def initialize(table, item, type, length, default, min, max, name)
            @table = table; @item = item; @type = type; @length = length
            @default = default; @value = default; @min = min; @max = max
            @name = name; @packing = @@packings[type]
        end

        def to_s
            out = "%d %4d  %-70s %-8s " % [ @table, @item, @name, @@types[@type] ]
            case type
            when 0..3
                out += " %12u %12u %12u %12u" % [ @min, @max, @default, @value ]
            when 4..7
                out += " %12d %12d %12d %12d" % [ @min, @max, @default, @value ]
            when 8
                out += " %12.4f %12.4f %12.4f %12.4f" % [ @min, @max, @default, @value ]
            end
            out
        end

        def to_json(a)
            { 'table' => @table, 'item' => @item, 'type' => @@types[@type], 'default' => @default,
              'value' => @value, 'min' => @min, 'max' => @max, 'name' => @name }.to_json
        end

        def self.from_json string
            data = JSON.load string
            self.new data['a'], data['b']
        end

        def self.types
            return @@types
        end
    end

    def initialize(duml = nil, debug = false)
        @duml = duml
        @debug = debug
        @timeout = 0.2
        @src = @duml.src
        @dst = '0300'

        if debug
            # TODO: Add src & dst
            @duml.register_handler(0x00, 0x0e) do |msg| fc_status(msg); end
        end

        # See if we can reach the FC
        @versions = @duml.cmd_dev_ver_get(@src, @dst, @timeout)
        if @versions[:full] == nil
            raise "FlightController unresponsive"
        end
        puts "FC Version: %s" % @versions[:app]

        if fc_assistant_unlock() == nil
            raise "Couldn't do an 'assistant unlock'"
        end
    end

    def fc_status(msg)
        reply = msg.payload[1..-1].pack("C*")
        if reply.scan( /\[D-SEND DATA\]\[DEBUG\]\[Pub\]/ ) == []
            puts reply.yellow
        end
    end

    def fc_assistant_unlock()
        reply = @duml.send(DUML::Msg.new(@src, @dst, 0x40, 0x03, 0xdf, [ 0x00000001 ].pack("L<").unpack("C*")), @timeout)
        # TODO: parse reply
        return reply
    end

    def fc_ask_table(table)
        reply = @duml.send(DUML::Msg.new(@src, @dst, 0x40, 0x03, 0xe0,
                                         [ table ].pack("S<").unpack("C*")), @timeout)
        if reply == nil
            raise "No reply"
        end

        status = reply.payload[0..1].pack("C*").unpack("S<")[0]
        if status != 0
            return -status
        end

        table, unk, items = reply.payload[2..-1].pack("C*").unpack("S<L<S<");

        return items
    end

    def fc_ask_param(table, item)
        reply = @duml.send(DUML::Msg.new(@src, @dst, 0x40, 0x03, 0xe1,
                                         [ table, item ].pack("S<S<").unpack("C*")), @timeout)
        status = reply.payload[0..1].pack("C*").unpack("S<")[0]
        if status != 0
            return -status
        end

        table, item, type, length = reply.payload[2..9].pack("C*").unpack("S<S<S<S<")

        # uint8 = 0, uint16 = 1, uint32 = 2, int8 = 4, int16 = 5, int32 = 6, float = 8
        case type
        when 0..2
            default, min, max = reply.payload[10..21].pack("C*").unpack("L<L<L<")
        when 4..6
            default, min, max = reply.payload[10..21].pack("C*").unpack("l<l<l<")
        when 8
            default, min, max = reply.payload[10..21].pack("C*").unpack("eee")
        end

        name = reply.payload[22..-2].pack("C*")

        return Param.new(table, item, type, length, default, min, max, name)
    end

    def fc_get_param(param)
        reply = @duml.send(DUML::Msg.new(@src, @dst, 0x40, 0x03, 0xe2,
                                         [ param.table, 0x0001, param.item ].pack("S<S<S<").unpack("C*")), @timeout)
        status = reply.payload[0..1].pack("C*").unpack("S<")[0]
        if status != 0
            return nil
        end

        #table, item = reply.payload[2..5].pack("C*").unpack("S<S")
        param.value = reply.payload[6..-1].pack("C*").unpack(param.packing)[0]
        return param
    end

    def fc_set_param(param, value = param.value)
        #TODO: add a Param setter for value that does this.
        if value.is_a? String
            case param.type
            when 0..7
                value = value.to_i
            when 8
                value = value.to_f
            end
        end
        payload = [ param.table, 0x0001, param.item, value ].pack("S<S<S<%s" % param.packing).unpack("C*")
        reply = @duml.send(DUML::Msg.new(@src, @dst, 0x40, 0x03, 0xe3, payload), @timeout)
        status = reply.payload[0..1].pack("C*").unpack("S<")[0]
        if status != 0
            puts "status: #{status}"
            return status
        end
        return 0
    end

    def read_params_def()
        file = "params-" + @versions[:app] + ".json"
        if File.file?(file)
            f = File.new(file).read
            all = []
            p = JSON.parse(f)
            @params = p.map { |p| Param.new(p['table'], p['item'], Param.types.index(p['type']), 0, p['default'], p['min'], p['max'], p['name']) }
            return true
        end
        return false
    end

    def write_param_def()
        f = File.new("params-" + @versions[:app] + ".json", "w")
        f.write(JSON.pretty_generate(@params))
    end

    def read_params_def_from_fc()
        @params = []
        [0, 1].each do |t|
            items = fc_ask_table(t)
            puts "Table %d => %d items" % [t, items]
            (0..(items - 1)).each do |i|
                print "   %3d / %3d\r" % [ i + 1, items ]
                p = fc_ask_param(t, i)
                @params = @params + [ p ]
            end
        end
    end

    def search_params(paramstr)
        @params.each do |p|
            if p.name.include? paramstr
                fc_get_param(p)
                puts p
            end
        end
    end

    def lookup_param(paramstr)
        @params.each do |p|
            if p.name == paramstr
                fc_get_param(p)
                return p
            end
        end
        return nil
    end
end

if __FILE__ == $0

    options = {}
    OptionParser.new do |parser|
        parser.on("-d", "--device DEVICE",
                  "Path to the serial port, e.g. /dev/tty.usbmodem1425") do |dev|
            options["dev"] = dev
        end
        parser.on("-f", "--find PARAM",
                  "Search for parameters matching the PARAM query") do |param|
            options["find"] = param
        end
        parser.on("-s", "--set PARAM",
                  "To parameter which value you want to change") do |param|
            options["set_param"] = param
        end
        parser.on("-v", "--value VALUE",
                  "The new value for the parameter provided by -s") do |value|
            options["set_value"] = value
        end
    end.parse!

    port = options["dev"]
    if port == nil
        puts "No serial port defined"
        exit
    end

    con = DUML::ConnectionSerial.new(port)
    duml = DUML.new(0x2a, 0xc3, con, 1, false)
    fc = FlightController.new(duml, false)

    if not fc.read_params_def()
        puts "Parameters for this version aren't cached yet, reading them first"
        fc.read_params_def_from_fc()
        fc.write_param_def()
    end

    if options["find"]
        puts "Looking for " + options["find"] + ":"
        fc.search_params(options["find"])
    end

    if options["set_param"]
        puts "Setting '" + options["set_param"] + "' to " + options["set_value"]
        p = fc.lookup_param(options["set_param"])
        if p
            fc.fc_set_param(p, options["set_value"])
            fc.fc_get_param(p)
            puts p
        end
    end
end

# vim: expandtab:ts=4:sw=4
