#!/usr/bin/env ruby
# Registers the MomenTerm plugin marketplace files with iTerm2.xcodeproj.
# Idempotent — re-running is safe.
#
#   - Swift sources -> iTerm2SharedARC compile phase (compiled once, linked into all app targets).
#   - Resources/plugins.default.json -> Resources phase of all app targets.

require 'xcodeproj'

SWIFT_SOURCES = %w[
  sources/MomentermPluginRegistry.swift
  sources/MomentermPluginInstaller.swift
  sources/MomentermPluginMarketWindowController.swift
].freeze

RESOURCE_FILES = %w[
  Resources/plugins.default.json
].freeze

SHARED_TARGET = 'iTerm2SharedARC'
APP_TARGETS = %w[iTerm2 iTerm2Tests iTerm2ForApplescriptTesting].freeze

project = Xcodeproj::Project.open('iTerm2.xcodeproj')

def find_or_create_group(project, group_path)
  components = group_path.split(File::SEPARATOR)
  current = project.main_group
  components.each do |comp|
    child = current.children.find do |c|
      c.is_a?(Xcodeproj::Project::Object::PBXGroup) &&
        (c.display_name == comp || c.path == comp || c.path == "#{comp}/")
    end
    current = child || current.new_group(comp, comp)
  end
  current
end

# -- Swift sources -----------------------------------------------------------

shared = project.targets.find { |t| t.name == SHARED_TARGET }
abort "ERROR: target '#{SHARED_TARGET}' not found" unless shared

sources_group = find_or_create_group(project, 'sources')

SWIFT_SOURCES.each do |rel|
  filename = File.basename(rel)
  ref = project.files.find { |f| f.path == filename }
  if ref.nil?
    ref = sources_group.new_file(filename)
    puts "+ Added file reference: #{rel}"
  else
    puts "  (file ref already exists: #{ref.path})"
  end
  if shared.source_build_phase.files.any? { |bf| bf.file_ref == ref }
    puts "  (already in Sources of '#{SHARED_TARGET}', skipping)"
  else
    shared.source_build_phase.add_file_reference(ref)
    puts "+ Add #{rel} to Sources of '#{SHARED_TARGET}'"
  end
end

# -- Resources ---------------------------------------------------------------

resources_group = find_or_create_group(project, 'Resources')

RESOURCE_FILES.each do |rel|
  filename = File.basename(rel)
  # Resources group has no `path`, so the file ref must carry the full
  # repo-relative path (e.g. "Resources/plugins.default.json"). Without
  # the prefix, Xcode looks at the project root and CpResource fails.
  ref = project.files.find { |f| f.path == rel || f.path == filename }
  if ref.nil?
    ref = resources_group.new_reference(rel)
    ref.last_known_file_type = 'text.json'
    puts "+ Added file reference: #{rel}"
  elsif ref.path != rel
    ref.path = rel
    puts "  (corrected path of existing file ref: #{rel})"
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
      puts "+ Add #{rel} to Resources of '#{name}'"
    end
  end
end

project.save
puts "Saved iTerm2.xcodeproj"
