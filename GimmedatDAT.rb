require 'net/ftp'
require "openssl"
require "base64"
include Base64

#puts "Please connect your DJI drone, verify the RNDIS is up, and press <enter>"
#gets

puts "Only Compatiable with DAT files not on FC (i.e. > Mavic 01.04.000)"
puts "---------------------"
ftp = Net::FTP.new('192.168.42.2')
ftp.passive = true
ftp.read_timeout = 300
ftp.login("HDnesgotyoshit","gimmedatDAT" )
puts "Logged into the FTP"
puts "---------------------"

files = ftp.chdir('blackbox/flyctrl')
files = ftp.nlst

index = 0
files.each do |i|
    puts "[" + index.to_s + "]: " + i
    index += 1
end

puts "---------------------"
puts "Select DAT file to be pulled:"
print "[#?]: "
input = gets
file_selected = files[input.to_i]
file_selected = file_selected.to_s

begin
    
    filename = "/blackbox/flyctrl/" + file_selected
    puts "Grabbing DAT file"
    puts "Downloading DAT file: #{filename} to memory"
    encodedfile = ftp.getbinaryfile(filename,nil)
    cipher = OpenSSL::Cipher::AES128.new(:CBC)
    cipher.decrypt
    cipher.key = "this-aes-key\x00\x00\x00\x00"
    #cipher.key = "\x59\x50\x31\x4E\x61\x67\x37\x5A\x52\x26\x44\x6A\x00\x00\x00\x00"
    cipher.iv  = "0123456789abcdef"
    decrypted_plain_text = cipher.update(encodedfile) + cipher.final

    # https://github.com/MAVProxyUser/DJI_ftpd_aes_unscramble/commit/73a21718c32ee2be96fc64b9b5acf033c5626176
    # Ruby uses PKCS7 Padding by default, so there's no need to adjust this

    #puts decrypted_plain_text
    File.open(file_selected, "w+") { |file| file.write(decrypted_plain_text) }
    puts "file written to " + file_selected

rescue Net::FTPPermError
    puts "Weird FTP problem... unable to retrieve the DAT file"
end
ftp.close


