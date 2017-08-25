require 'net/ftp'
require "openssl"
require "base64"
include Base64

#puts "Please connect your DJI drone, verify the RNDIS is up, and press <enter>"
#gets

ftp = Net::FTP.new('192.168.42.2')
ftp.passive = true
ftp.login("LogJammer","IsDaRealest!" )
puts "Logged into the FTPD"
begin
    filename = "/upgrade/dji/log/upgrade00.log"
    puts "Snagging firmware update log file..."
    puts "Downloading file: #{filename} to memory"
    encodedfile = ftp.getbinaryfile(filename,nil)
    cipher = OpenSSL::Cipher::AES128.new(:CBC)
    cipher.decrypt
    cipher.key = "this-aes-key\x00\x00\x00\x00"
    cipher.iv  = "0123456789abcdef"
    decrypted_plain_text = cipher.update(encodedfile) + cipher.final

    # https://github.com/MAVProxyUser/DJI_ftpd_aes_unscramble/commit/73a21718c32ee2be96fc64b9b5acf033c5626176
    # Ruby uses PKCS7 Padding by default, so there's no need to adjust this

    puts decrypted_plain_text
    File.open("upgrade00_logjam.txt", "w+") { |file| file.write(decrypted_plain_text) }
    puts "file written to upgrade00_logjam.txt"

rescue Net::FTPPermError
    puts "Weird FTP problem... unable to retrieve the upgrade00.log file"
end
ftp.close
