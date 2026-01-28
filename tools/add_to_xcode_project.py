#!/usr/bin/env python3
"""
Add Swift files to the iTerm2 Xcode project.

This script adds files to the iTerm2SharedARC target. ModernTests uses
PBXFileSystemSynchronizedRootGroup which auto-syncs with the filesystem,
so test files don't need to be added manually.

Usage:
    python3 tools/add_to_xcode_project.py sources/FairnessScheduler.swift
"""

import sys
import os
import random
import re

def generate_uuid():
    """Generate a 24-character hex UUID like Xcode uses."""
    return ''.join(random.choices('0123456789ABCDEF', k=24))

def add_swift_file_to_project(filepath, project_path):
    """Add a Swift file to the iTerm2SharedARC target."""

    filename = os.path.basename(filepath)

    # Generate UUIDs
    file_ref_uuid = generate_uuid()
    build_file_uuid = generate_uuid()

    print(f"Adding {filename} to project...")
    print(f"  File Reference UUID: {file_ref_uuid}")
    print(f"  Build File UUID: {build_file_uuid}")

    # Read the project file
    with open(project_path, 'r') as f:
        content = f.read()

    # Check if file is already in project
    if filename in content:
        print(f"  WARNING: {filename} appears to already be in the project!")
        return False

    # 1. Add PBXFileReference entry
    # Find a good insertion point (after TokenArray.swift reference)
    file_ref_entry = f'\t\t{file_ref_uuid} /* {filename} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {filename}; sourceTree = "<group>"; }};\n'

    # Find TokenArray.swift file reference and insert after it
    token_array_pattern = r'(\t\tA69553882DD1AA7B002E694D /\* TokenArray\.swift \*/ = \{[^}]+\};\n)'
    match = re.search(token_array_pattern, content)
    if match:
        insert_pos = match.end()
        content = content[:insert_pos] + file_ref_entry + content[insert_pos:]
        print(f"  Added PBXFileReference entry")
    else:
        print("  ERROR: Could not find TokenArray.swift file reference")
        return False

    # 2. Add PBXBuildFile entry
    build_file_entry = f'\t\t{build_file_uuid} /* {filename} in Sources */ = {{isa = PBXBuildFile; fileRef = {file_ref_uuid} /* {filename} */; }};\n'

    # Find TokenArray.swift build file and insert after it
    token_array_build_pattern = r'(\t\tA69553892DD1AA7F002E694D /\* TokenArray\.swift in Sources \*/ = \{[^}]+\};\n)'
    match = re.search(token_array_build_pattern, content)
    if match:
        insert_pos = match.end()
        content = content[:insert_pos] + build_file_entry + content[insert_pos:]
        print(f"  Added PBXBuildFile entry")
    else:
        print("  ERROR: Could not find TokenArray.swift build file entry")
        return False

    # 3. Add to sources group (near TokenArray.swift)
    group_entry = f'\t\t\t\t{file_ref_uuid} /* {filename} */,\n'

    # Find TokenArray.swift in the group and insert after it
    group_pattern = r'(\t\t\t\tA69553882DD1AA7B002E694D /\* TokenArray\.swift \*/,\n)'
    match = re.search(group_pattern, content)
    if match:
        insert_pos = match.end()
        content = content[:insert_pos] + group_entry + content[insert_pos:]
        print(f"  Added to sources group")
    else:
        print("  ERROR: Could not find TokenArray.swift in sources group")
        return False

    # 4. Add to iTerm2SharedARC Sources build phase
    build_phase_entry = f'\t\t\t\t{build_file_uuid} /* {filename} in Sources */,\n'

    # Find TokenArray.swift in build phase and insert after it
    build_phase_pattern = r'(\t\t\t\tA69553892DD1AA7F002E694D /\* TokenArray\.swift in Sources \*/,\n)'
    match = re.search(build_phase_pattern, content)
    if match:
        insert_pos = match.end()
        content = content[:insert_pos] + build_phase_entry + content[insert_pos:]
        print(f"  Added to iTerm2SharedARC Sources build phase")
    else:
        print("  ERROR: Could not find TokenArray.swift in build phase")
        return False

    # Write the updated project file
    with open(project_path, 'w') as f:
        f.write(content)

    print(f"  Successfully added {filename} to project!")
    return True

def main():
    if len(sys.argv) < 2:
        print("Usage: python3 tools/add_to_xcode_project.py <filepath>")
        print("Example: python3 tools/add_to_xcode_project.py sources/FairnessScheduler.swift")
        sys.exit(1)

    filepath = sys.argv[1]
    project_path = "iTerm2.xcodeproj/project.pbxproj"

    if not os.path.exists(filepath):
        print(f"Error: File not found: {filepath}")
        sys.exit(1)

    if not os.path.exists(project_path):
        print(f"Error: Project file not found: {project_path}")
        sys.exit(1)

    success = add_swift_file_to_project(filepath, project_path)
    sys.exit(0 if success else 1)

if __name__ == "__main__":
    main()
