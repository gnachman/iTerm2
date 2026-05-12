#!/usr/bin/env ruby
# Adds Resources/MomentermAssets.xcassets to the Resources build phase of
# the 3 app targets (iTerm2, iTerm2Tests, iTerm2ForApplescriptTesting).
# Idempotent: skips entries already present.

require 'xcodeproj'

APP_TARGETS = %w[iTerm2 iTerm2Tests iTerm2ForApplescriptTesting].freeze
RESOURCE_PATH = 'Resources/MomentermAssets.xcassets'

project = Xcodeproj::Project.open('iTerm2.xcodeproj')

# Find-or-create the file reference under a "Resources" group at project root
resources_group = project.main_group.find_subpath('Resources', true)
resources_group.set_source_tree('<group>')

ref = project.files.find { |f| f.path == 'MomentermAssets.xcassets' }
if ref.nil?
  ref = resources_group.new_reference('MomentermAssets.xcassets')
  ref.last_known_file_type = 'folder.assetcatalog'
  puts "+ Added file reference: #{RESOURCE_PATH}"
else
  puts "  (file ref already exists: #{ref.path})"
end

APP_TARGETS.each do |name|
  t = project.targets.find { |x| x.name == name }
  abort "ERROR: target '#{name}' not found" unless t
  if t.resources_build_phase.files.any? { |bf| bf.file_ref == ref }
    puts "  (already in Resources of '#{name}', skipping)"
  else
    t.resources_build_phase.add_file_reference(ref)
    puts "+ Add #{RESOURCE_PATH} to Resources phase of '#{name}'"
  end
end

project.save
puts "Saved iTerm2.xcodeproj"
