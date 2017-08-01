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
    cipher.key = "\x74\x68\x69\x73\x2d\x61\x65\x73\x2d\x6b\x65\x79\x00\x00\x00\x00"
    cipher.iv  = "\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
    decrypted_plain_text = cipher.update(encodedfile) + cipher.final

    # https://github.com/MAVProxyUser/DJI_ftpd_aes_unscramble/commit/93537fdec26435537399ea8595e0eee8725f5759
    # undo the weird xor stuff that DJI does to try and beat us

    puts "reversing odd DJI XOR bytes"
    bytes = decrypted_plain_text.bytes.to_a
    0.upto(9) do |i|
        bytes[i] ^= 0x30 + i
    end
    10.upto(15) do |i|
        bytes[i] ^= 0x57 + i
    end

    # https://github.com/MAVProxyUser/DJI_ftpd_aes_unscramble/commit/73a21718c32ee2be96fc64b9b5acf033c5626176
    # Ruby uses PKCS7 Padding by default, so there's no need to adjust this

    puts bytes.pack('c*')
    File.open("upgrade00_logjam.txt", "w+") { |file| file.write(bytes.pack('c*')) }
    puts "file written to upgrade00_logjam.txt"

rescue Net::FTPPermError
    puts "Weird FTP problem... unable to retrieve the upgrade00.log file"
end
ftp.close
