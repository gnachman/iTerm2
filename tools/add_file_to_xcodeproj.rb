#!/usr/bin/env ruby
# Usage: tools/add_file_to_xcodeproj.rb <file_path> <target_name>
# Example: tools/add_file_to_xcodeproj.rb sources/Example.swift iTerm2SharedARC
#
# Adds a PBXFileReference and target membership using the xcodeproj gem. The gem
# re-serializes the WHOLE project on save, which normalizes formatting the way
# Xcode does not (drops redundant `name =` keys, re-expands
# PBXFileSystemSynchronizedRootGroups, rewrites comments), producing a large
# unreviewable diff. To keep the change minimal, we let the gem compute the new
# objects, then splice ONLY those newly-created lines into the original file text
# and throw away the gem's cosmetic churn. If the splice can't be done safely
# (e.g. new groups had to be created), we fall back to the gem's full output with
# a warning so the file is still added.

require 'xcodeproj'
require 'pathname'
require 'set'

def main
  if ARGV.length != 2
    puts "Usage: #{$0} <file_path> <target_name>"
    puts "Example: #{$0} sources/Example.swift iTerm2SharedARC"
    exit 1
  end

  file_path = ARGV[0]
  target_name = ARGV[1]

  proj_path = find_xcodeproj
  unless proj_path
    puts "Error: Could not find .xcodeproj file"
    exit 1
  end

  project = Xcodeproj::Project.open(proj_path)

  target = project.targets.find { |t| t.name == target_name }
  unless target
    puts "Error: Target '#{target_name}' not found"
    puts "Available targets:"
    project.targets.each { |t| puts "  - #{t.name}" }
    exit 1
  end

  unless File.exist?(file_path)
    puts "Error: File '#{file_path}' does not exist"
    exit 1
  end

  # A file under a PBXFileSystemSynchronizedRootGroup is auto-discovered by Xcode;
  # no project change is needed.
  dir_components = File.dirname(file_path).split(File::SEPARATOR).reject { |c| c == '.' }
  if synchronized_root_group?(project, dir_components)
    puts "Directory '#{File.dirname(file_path)}' is a synchronized root group — Xcode manages it automatically."
    puts "No project changes needed."
    exit 0
  end

  pbxproj_path = File.join(proj_path, 'project.pbxproj')
  original_text = File.read(pbxproj_path)
  uuids_before = project.objects_by_uuid.keys.to_set

  group = find_or_create_group(project, file_path)

  existing_ref = project.files.find { |f| f.path == File.basename(file_path) && f.parent == group }
  if existing_ref
    puts "Warning: File already exists in project, checking target membership..."
  else
    existing_ref = group.new_file(File.basename(file_path))
    puts "Added file reference: #{file_path}"
  end

  build_file = target.source_build_phase.files.find { |f| f.file_ref == existing_ref }
  if build_file
    puts "File is already a member of target '#{target_name}'"
  else
    target.source_build_phase.add_file_reference(existing_ref)
    puts "Added to target: #{target_name}"
  end

  new_uuids = project.objects_by_uuid.keys.to_set - uuids_before
  if new_uuids.empty?
    puts "No project changes needed."
    return
  end

  # Let the gem serialize (this churns the whole file), then keep only the new
  # objects' lines spliced into the untouched original.
  project.save
  gem_text = File.read(pbxproj_path)

  minimal = splice_additions(original_text, gem_text, new_uuids)
  if minimal
    File.write(pbxproj_path, minimal)
    puts "Project saved (minimal diff)."
  else
    puts "Warning: could not compute a minimal diff (new groups or an unusual"
    puts "layout); saved with the gem's full serialization. Review the pbxproj diff"
    puts "and revert any hunks unrelated to #{File.basename(file_path)}."
  end
end

# Rebuild the original pbxproj text plus only the lines the gem added for
# new_uuids. Returns the new text, or nil if the additions can't be anchored
# unambiguously (caller then keeps the gem's full output).
def splice_additions(original_text, gem_text, new_uuids)
  gem_lines = gem_text.lines

  # Mark every gem line that belongs to a new object: its single- or multi-line
  # definition (a line beginning with a new UUID) and any reference to it (child
  # lists, build phases, which also begin with the UUID).
  marked = Array.new(gem_lines.length, false)
  i = 0
  while i < gem_lines.length
    line = gem_lines[i]
    m = line.match(/\A\t*([0-9A-F]{24}) /)
    if m && new_uuids.include?(m[1])
      marked[i] = true
      # A multi-line object definition opens "= {" without closing "};" on the
      # same line; mark through the matching close at the same indent.
      if line.include?(' = {') && !line.rstrip.end_with?('};')
        indent = line[/\A\t*/]
        close = "#{indent}};"
        j = i + 1
        while j < gem_lines.length
          marked[j] = true
          break if gem_lines[j].rstrip == close
          j += 1
        end
        i = j + 1
        next
      end
    end
    i += 1
  end

  # Group contiguous marked lines into runs, each anchored to the immediately
  # preceding UNMARKED gem line (a stable, pre-existing entry).
  runs = []
  i = 0
  while i < gem_lines.length
    if marked[i]
      start = i
      run = []
      while i < gem_lines.length && marked[i]
        run << gem_lines[i]
        i += 1
      end
      return nil if start.zero? # nothing stable to anchor to
      runs << [gem_lines[start - 1], run]
    else
      i += 1
    end
  end
  return nil if runs.empty?

  # Each anchor must occur exactly once in the original so the insertion point is
  # unambiguous; otherwise bail rather than risk a wrong or churned result.
  original_lines = original_text.lines
  runs.each do |anchor, _run|
    return nil unless original_lines.count(anchor) == 1
  end

  placed = Array.new(runs.length, false)
  out = []
  original_lines.each do |line|
    out << line
    runs.each_with_index do |(anchor, run), idx|
      next if placed[idx]
      if line == anchor
        out.concat(run)
        placed[idx] = true
      end
    end
  end

  return nil unless placed.all?
  out.join
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

def synchronized_root_group?(project, components)
  current = project.main_group
  components.each do |component|
    child = current.children.find { |c|
      c.respond_to?(:display_name) && (c.display_name == component || c.path == component)
    }
    return false unless child
    if child.is_a?(Xcodeproj::Project::Object::PBXFileSystemSynchronizedRootGroup)
      return true
    end
    return false unless child.is_a?(Xcodeproj::Project::Object::PBXGroup)
    current = child
  end
  false
end

def find_or_create_group(project, file_path)
  components = File.dirname(file_path).split(File::SEPARATOR)
  components = components.reject { |c| c == '.' }

  current_group = project.main_group

  components.each do |component|
    child = current_group.children.find { |c|
      next false unless c.is_a?(Xcodeproj::Project::Object::PBXGroup)
      c.display_name == component ||
        c.path == component ||
        c.path == "#{component}/"
    }

    if child
      current_group = child
    else
      current_group = current_group.new_group(component, component)
      puts "Created group: #{component}"
    end
  end

  current_group
end

main
