#!/usr/bin/env ruby
# One-off cleanup: move MomentermMarkdownTemplate.html from Sources → Resources
# in the 3 app targets, and remove MomentermMarkdownContent.swift entirely.
#
# Usage:
#   tools/fix_markdown_template_phase.rb         # dry-run
#   tools/fix_markdown_template_phase.rb --apply # write changes

require 'xcodeproj'

APPLY = ARGV.include?('--apply')
APP_TARGETS = %w[iTerm2 iTerm2Tests iTerm2ForApplescriptTesting].freeze
HTML_NAME   = 'MomentermMarkdownTemplate.html'
SWIFT_NAME  = 'MomentermMarkdownContent.swift'

project = Xcodeproj::Project.open('iTerm2.xcodeproj')

html_ref  = project.files.find { |f| f.path == HTML_NAME }
swift_ref = project.files.find { |f| f.path == SWIFT_NAME }

abort "ERROR: #{HTML_NAME} file reference not found"  unless html_ref
abort "ERROR: #{SWIFT_NAME} file reference not found" unless swift_ref

puts "Mode: #{APPLY ? 'APPLY' : 'DRY-RUN'}"
puts "HTML  fileRef UUID: #{html_ref.uuid}"
puts "Swift fileRef UUID: #{swift_ref.uuid}"
puts

# 1. Remove HTML from every Sources build phase
project.targets.each do |t|
  next unless t.respond_to?(:source_build_phase)
  bf = t.source_build_phase.files.find { |f| f.file_ref == html_ref }
  if bf
    puts "- Remove #{HTML_NAME} from Sources phase of '#{t.name}'  (bf=#{bf.uuid})"
    bf.remove_from_project if APPLY
  end
end

# 2. Add HTML to Resources phase of each app target (skip if already present)
APP_TARGETS.each do |name|
  t = project.targets.find { |x| x.name == name }
  abort "ERROR: target '#{name}' not found" unless t
  if t.resources_build_phase.files.any? { |f| f.file_ref == html_ref }
    puts "  (already in Resources of '#{name}', skipping)"
    next
  end
  puts "+ Add #{HTML_NAME} to Resources phase of '#{name}'"
  t.resources_build_phase.add_file_reference(html_ref) if APPLY
end

# 3. Remove Swift file from every Sources build phase, then drop file ref
project.targets.each do |t|
  next unless t.respond_to?(:source_build_phase)
  bf = t.source_build_phase.files.find { |f| f.file_ref == swift_ref }
  if bf
    puts "- Remove #{SWIFT_NAME} from Sources phase of '#{t.name}'  (bf=#{bf.uuid})"
    bf.remove_from_project if APPLY
  end
end
puts "- Remove file reference for #{SWIFT_NAME}  (uuid=#{swift_ref.uuid})"
swift_ref.remove_from_project if APPLY

if APPLY
  project.save
  puts
  puts "Saved iTerm2.xcodeproj"
else
  puts
  puts "Dry run only. Re-run with --apply to write changes."
end
