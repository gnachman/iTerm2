#!/usr/bin/env ruby
# Usage: tools/add_file_to_xcodeproj.rb <file_path> <target_name>
# Example: tools/add_file_to_xcodeproj.rb sources/Example.swift iTerm2SharedARC

require 'xcodeproj'
require 'pathname'

def main
  if ARGV.length != 2
    puts "Usage: #{$0} <file_path> <target_name>"
    puts "Example: #{$0} sources/Example.swift iTerm2SharedARC"
    exit 1
  end

  file_path = ARGV[0]
  target_name = ARGV[1]

  # Find the xcodeproj in the current directory or parent directories
  proj_path = find_xcodeproj
  unless proj_path
    puts "Error: Could not find .xcodeproj file"
    exit 1
  end

  project = Xcodeproj::Project.open(proj_path)

  # Find the target
  target = project.targets.find { |t| t.name == target_name }
  unless target
    puts "Error: Target '#{target_name}' not found"
    puts "Available targets:"
    project.targets.each { |t| puts "  - #{t.name}" }
    exit 1
  end

  # Check if file exists
  unless File.exist?(file_path)
    puts "Error: File '#{file_path}' does not exist"
    exit 1
  end

  # Find or create the group hierarchy based on the file path
  group = find_or_create_group(project, file_path)

  # Check if file is already in the project
  existing_ref = project.files.find { |f| f.path == File.basename(file_path) && f.parent == group }
  if existing_ref
    puts "Warning: File already exists in project, checking target membership..."
  else
    # Add the file reference
    existing_ref = group.new_file(File.basename(file_path))
    puts "Added file reference: #{file_path}"
  end

  # Check if already in target
  build_file = target.source_build_phase.files.find { |f| f.file_ref == existing_ref }
  if build_file
    puts "File is already a member of target '#{target_name}'"
  else
    target.source_build_phase.add_file_reference(existing_ref)
    puts "Added to target: #{target_name}"
  end

  project.save
  puts "Project saved."
end

def find_xcodeproj
  dir = Pathname.new(Dir.pwd)
  loop do
    proj = Dir.glob(dir.join("*.xcodeproj")).first
    return proj if proj
    break if dir.root?
    dir = dir.parent
  end
  nil
end

def find_or_create_group(project, file_path)
  # Split the path into components (excluding the filename)
  components = File.dirname(file_path).split(File::SEPARATOR)
  components = components.reject { |c| c == '.' }

  # Start from the main group
  current_group = project.main_group

  components.each do |component|
    # Look for existing group
    child = current_group.children.find { |c| c.is_a?(Xcodeproj::Project::Object::PBXGroup) && c.name == component }

    # Also check by path if name doesn't match
    child ||= current_group.children.find { |c| c.is_a?(Xcodeproj::Project::Object::PBXGroup) && c.path == component }

    if child
      current_group = child
    else
      # Create new group
      current_group = current_group.new_group(component, component)
      puts "Created group: #{component}"
    end
  end

  current_group
end

main
