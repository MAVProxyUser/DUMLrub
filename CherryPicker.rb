#!/usr/bin/ruby
# gem install nokogiri  -v '1.6.7.2' -- --with-xml2-include=/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX10.11.sdk/usr/include/libxml2 --use-system-libraries 
# 
require 'nokogiri'
require 'rubygems'
require 'highline/import'
require 'fileutils'

# model numbers
models = Hash.new()
models['wm100'] =    'Spark'
models['wm220'] =    'Mavic'
models['wm220_gl'] = 'Goggles' 
models['GL200A'] =   'GL200A' # Mavic Controller
models['wm330'] =    'P4'
models['wm331'] =    'P4P'
models['wm620'] =    'Inspire2'
name = ""
firmware = ""
cfg = ""

if ARGV[0] == nil
    # Use for-loop on keys.
    for key in models.keys()
        puts "#{key} -> #{models[key]}"
    end

    puts "Enter your drone: "
    name = $stdin.gets.chomp
    puts "Using drone type: #{name}"
else
    puts "Using drone type: #{ARGV[0]}"
    name = ARGV[0]
end

puts "Name is: #{name}"

if ARGV[1] == nil
    puts "Available firmware versions:"
    FileUtils.cd("firm_cache")
    Dir.glob("cfgs/V*/*.cfg.sig") {|file|
        if file.include?(models[name])
            puts "- " + file.split('_')[0].split('/')[1]
        end
    }
    puts "Enter desired firmware: "
    firmware = $stdin.gets.chomp
    puts "Using firmware: #{firmware}"
else
    puts "Using firmware: #{ARGV[1]}"
    firmware = ARGV[1]
end

# This should only be one file
Dir.glob("cfgs/#{firmware}_#{models[name]}_dji_system/*.cfg.sig") {|file| 
    cfg = "#{file}"
}

puts "Using config file: #{cfg}"

# Seek in 480 bytes and look for XML header (then skip it)
# 000001e0: 3c3f 786d 6c20 7665 7273 696f 6e3d 2231  <?xml version="1
config_sig = File.read("#{cfg}")
startxml = config_sig.index("<dji>")
config_sig = config_sig[startxml..-24]

firmwarepackage = Nokogiri::XML(config_sig)
firmwarepackage_version = firmwarepackage.xpath('/dji/device/firmware/release').first['version']
puts "Firmware version inside package confirmed as #{firmwarepackage_version}"

sigfiles = Array.new
handrolled = Array.new
puts "Found update for: "
firmwarepackage.xpath('/dji/device/firmware/release/module').each do  |firmware_module|
    # Known type's
    # ca02 -
    # cd01 -
    # cd02 -
    # cd03 -
    # gb01 -
    # gb02 - 
    # ln01 -
    # ln02 -

    sig =  "#{firmware_module['group']}_module id:#{firmware_module['id']} version:#{firmware_module['version']}"
    # Known group's
    # ac - AirCraft
    # gl - GroundLink (Goggles, Mavic RC)
    # rc - RemoteController

    if "#{firmware_module['type']}" != ""
        sig = sig + " group: #{firmware_module['type']}"
    end

    sigfiles << [firmware_module.text(), sig, "md5:#{firmware_module['md5']}" ]

end

sigfiles << "Done. (roll the tar)"

loop do 
    taritup = false
    choose do |menu|
        menu.shell = true
        menu.prompt = 'Please choose the .fw.sigs you wish to include:'
        menu.choices(*sigfiles) do |chosen|
            if "#{chosen}" == "Done. (roll the tar)"
                puts "tar it up now!"
                taritup = true
            else
                puts "adding to handroll"
                handrolled << "#{chosen[0]}"
                sigfiles.delete_if do |sig|
                    if chosen == sig 
                        true
                    end
                end
            end
        end
    end

    if taritup == true
        if handrolled.length > 0
            puts "At least one module detected"
            break
        else
            puts "Please select more modules"
            taritup = false
        end
    end
end 

# Begin tar file creation 
directory_name = "dji_system"
Dir.mkdir(directory_name) unless File.exists?(directory_name)

puts "Cleaning up any existing firmware files in ./dji_system"
Dir.glob("#{directory_name}/*").each { |file| 
    File.delete(file)
    puts "deleted #{file}"
}

puts "Copying over firmware modules"
handrolled.each { |file|
    puts "-> sigs/#{file}"
    FileUtils.cp( "sigs/#{file}", "dji_system/")
}
FileUtils.cp( cfg, "dji_system/")

if File.exists?("dji_system.bin")
    puts "deleting stale firmware file"
    File.unlink("dji_system.bin")
end

# Tested on OSX with brew http://brewformulas.org/GnuTar 
%x[ gtar --owner=0 --group=0 -cvf dji_system.bin -C dji_system/ .]

if File.exists?("dji_system.bin")
    puts "Successful *custom* dji_system.bin creation"
    puts %x[gtar -tvf dji_system.bin]
else
    puts "Something went wrong... try again"
end

# Known module id's
# Need to document what each ID goes to, upgrade00.log is the best immediate candiate to map these out if you don't want to disas dji_sys
# Use the below grep command to get a list on a rooted device. 
# grep ": check file" `busybox find / -name "*upgrade*log*"`  | busybox cut -f2 -d "]" | busybox sort | busybox uniq 
#
# 0100 - P4P, P4, i2, Mavic Camera Upgrade
# 0101 - P4, Mavic Camera Loader Upgrade
# 0104 - P4P Lens_Controller Upgrade
# 0106 - CAMFPGA (XLNX), XiLinx CAM FPGA? 
# 0305 - P4, i2 FlyCtrl_Loader, Spark, Mavic FC Loader Upgrade
# 0306 - P4P, P4, i2 FlyCtrl, Spark, Mavic FC APP Upgrade
# 0400 - P4P, P4, Spark, Mavic Gimbal Upgrade
# 0401 - P4P, P4 Gimbal 5223#1, i2 Gimbal_ESC Upgrade
# 0402 - P4P, P4 Gimbal 5223 #2, i2 SSD_Controller Upgrade
# 0404 - FPV_Gimbal Upgrade
# 0500 - i2 CenterBoard Upgrade
# 0501 - i2 Gear_Controller Upgrade
# 0600 - GLB200A MCU_051_gnd Upgrade (not encrypted)
# 0601 - Goggles MCU_031_gls Upgrade
# 0603 - Goggles MCU_051_gls Upgrade
# 0801 - Android recovery ROM?
# 0802 - Modvidius ma2155 VPU firmware, "DJI_IMX377" (CMOS image sensor) firmware, Veri Silicon Hantaro Video IP encoder/decoder ?
# 0803 - 
# 0804 - "System Initialized" ?
# 0805 - upgrade.zip (calibration for VPS?)
# 0900 - P4 OFDM, P4P, i2 LightBridge Upgrade
# 0905 - NFZ Database (nfz.db and bfz.sig)
# 0907 - Mavic modem/arm/dsp/gnd/uav "upgrade file" (unencrypted)
# 1100 - i2 Battery_0, P4, Spark, Mavic Battery Upgrade
# 1101 - i2 Battery_1 Upgrade
# 1200 - P4, i2, Spark, Mavic ESC0 Upgrade
# 1201 - P4, i2, spark, Mavic ESC1 Upgrade
# 1202 - P4, i2, Spark, Mavic ESC2 Upgrade
# 1203 - P4, i2, Spark, Mavic ESC3 Upgrade
# 1301 - OTA.zip?
# 1407 - GLB200A modem/arm/dsp/gnd/uav "upgrade file" (unencrypted)
# 2801 - Mavic modem/arm/dsp/gnd/uav "upgrade file" (unencrypted)
# 2803 -  
# 2807 - Mavic modem/arm/dsp/gnd/uav "upgrade file" (unencrypted)
# 
# Match against: https://github.com/mefistotelis/phantom-firmware-tools/issues/25#issuecomment-297153290
