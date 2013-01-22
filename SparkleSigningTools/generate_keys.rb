#!/usr/bin/ruby
["dsaparam.pem", "dsa_priv.pem", "dsa_pub.pem"].each do |file|
  if File.exist? file
    puts "There's already a #{file} here! Move it aside or be more careful!"
  end
end
`openssl dsaparam 2048 < /dev/urandom > dsaparam.pem`
`openssl gendsa dsaparam.pem -out dsa_priv.pem`
`openssl dsa -in dsa_priv.pem -pubout -out dsa_pub.pem`
`rm dsaparam.pem`
puts "\nGenerated private and public keys: dsa_priv.pem and dsa_pub.pem.\n
BACK UP YOUR PRIVATE KEY AND KEEP IT SAFE!\n
If you lose it, your users will be unable to upgrade!\n"