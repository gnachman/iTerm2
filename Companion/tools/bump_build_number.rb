#!/usr/bin/env ruby
# Bump (or set) the build number for the Companion app AND the PushService
# extension. CURRENT_PROJECT_VERSION (CFBundleVersion) is defined once in
# generate_companion_project.rb and applied to both targets, so this edits that
# single source of truth. Run the generator afterward to write it into the
# Xcode project (the `companion-bump-build` make target does both).
#
# Usage:
#   ruby bump_build_number.rb          # increment by 1
#   ruby bump_build_number.rb 12       # set to an explicit number
#
# Set an explicit number (>= your latest App Store Connect build + 1) the first
# time, since a bare increment starts from whatever the generator currently
# holds, which a regeneration may have reset below your latest uploaded build.

path = File.join(__dir__, 'generate_companion_project.rb')
source = File.read(path)
unless source =~ /^CURRENT_PROJECT_VERSION = '(\d+)'/
  abort "bump_build_number: could not find CURRENT_PROJECT_VERSION in #{path}"
end
old = $1.to_i
new = if ARGV[0] && ARGV[0] =~ /\A\d+\z/
        ARGV[0].to_i
      else
        old + 1
      end
source.sub!(/^CURRENT_PROJECT_VERSION = '\d+'/, "CURRENT_PROJECT_VERSION = '#{new}'")
File.write(path, source)
puts "Companion build number: #{old} -> #{new} (app + PushService). Run the generator to apply."
