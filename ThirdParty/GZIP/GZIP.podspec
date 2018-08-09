Pod::Spec.new do |s|
  s.name         = 'GZIP'
  s.version      = '1.2.1'
  s.license      = 'zlib'
  s.summary      = 'GZIP is category on NSData that provides simple gzip compression and decompression functionality.'
  s.homepage     = 'https://github.com/nicklockwood/GZIP'
  s.author       = { "Nick Lockwood" => "support@charcoaldesign.co.uk" }
  s.source       = { :git => "https://github.com/nicklockwood/GZIP.git", :tag => "1.2.1" }
  s.source_files = 'GZIP/*.{h,m}'
  s.library      = 'z'
  s.requires_arc = false
  s.ios.deployment_target = '8.0'
  s.osx.deployment_target = '10.10'
  s.tvos.deployment_target = '9.0'
  s.watchos.deployment_target = '2.0'
end
