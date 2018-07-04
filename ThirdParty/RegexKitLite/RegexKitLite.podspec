Pod::Spec.new do |s|
  s.name     = 'RegexKitLite'
  s.version  = '4.0.6'
  s.license  = 'BSD'
  s.summary  = 'Lightweight Objective-C Regular Expressions using the ICU Library.'
  s.homepage = 'http://regexkit.sourceforge.net/RegexKitLite/'
  s.author   = { 'John Engelhart' => 'regexkitlite@gmail.com' }
  s.source   = { :git => 'https://github.com/inquisitiveSoft/RegexKitLite.git', :tag => "4.0.6" }
  s.source_files = '**/RegexKitLite.{h,m}'
  s.requires_arc = false
  s.compiler_flags = '-fno-objc-arc'
  s.library = 'icucore'
end
