require 'net/ftp'
require "openssl"

class PullFtpFile

    def get(filename)
        decrypted_plain_test = ""
        ftp = Net::FTP.new('192.168.42.2')
        ftp.passive = true
        ftp.login("root","Big~9China" )
        begin
            encodedfile = ftp.getbinaryfile(filename, nil)
            cipher = OpenSSL::Cipher::AES128.new(:CBC)
            cipher.decrypt
            cipher.key = "this-aes-key\x00\x00\x00\x00"
            cipher.iv  = "0123456789abcdef"
            decrypted_plain_text = cipher.update(encodedfile) + cipher.final

            # https://github.com/MAVProxyUser/DJI_ftpd_aes_unscramble/commit/73a21718c32ee2be96fc64b9b5acf033c5626176
            # Ruby uses PKCS7 Padding by default, so there's no need to adjust this

        rescue Net::FTPPermError
            puts "Weird FTP problem... unable to retrieve #{filename}"
        end
        ftp.close

        return decrypted_plain_text
    end

end

# vim: expandtab:ts=4:sw=4
