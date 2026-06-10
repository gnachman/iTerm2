#!/usr/bin/env ruby
# Generates Companion/iTerm2Companion.xcodeproj: an iOS SwiftUI app target that
# depends on the local CompanionCore Swift package. Re-run after adding source
# files. Requires the xcodeproj gem (already used by tools/add_file_to_xcodeproj.rb).

require 'xcodeproj'
require 'pathname'

COMPANION_DIR = File.expand_path('..', __dir__)
REPO_ROOT = File.expand_path('../..', __dir__)
PROJECT_PATH = File.join(COMPANION_DIR, 'iTerm2Companion.xcodeproj')
APP_DIR = File.join(COMPANION_DIR, 'iTerm2Companion')
BUNDLE_ID = 'com.googlecode.iterm2.companion'
DEPLOYMENT_TARGET = '16.0'
PACKAGE_PRODUCTS = %w[CompanionProtocol CompanionNoise CompanionTransport]

# Chat-model sources shared with the Mac app. These compile into BOTH the
# iTerm2 app and this iOS app, so they must stay platform-neutral (each file
# carries a banner comment saying so). Heavy Mac-only leaf types they mention
# have same-named stand-ins in iTerm2Companion/Satellites/.
SHARED_MAC_SOURCES = %w[
  sources/AITerm/Message.swift
  sources/AITerm/Chat.swift
  sources/AITerm/RemoteCommand.swift
  sources/AITerm/LLM.swift
  sources/AITerm/AIExplanationRequest.swift
  sources/AITerm/AIExplanationResponse.swift
  sources/AITerm/iTermAIError.swift
  sources/AITerm/TerminalCommand.swift
  sources/Categories/Result+iTerm.swift
  sources/Categories/NSDictionaryCodableBox.swift
  sources/ClaudeCode/Orchestration/WorkgroupWatcher.swift
  sources/Companion/Shared/CompanionMessages.swift
  sources/Companion/Shared/CompanionSession.swift
]

project = Xcodeproj::Project.new(PROJECT_PATH)

target = project.new_target(:application, 'iTerm2Companion', :ios, DEPLOYMENT_TARGET)

# Group mirroring the on-disk layout under iTerm2Companion/.
app_group = project.new_group('iTerm2Companion', APP_DIR)

# Add every Swift source under the app dir, preserving subfolder groups.
swift_files = Dir.glob(File.join(APP_DIR, '**', '*.swift')).sort
swift_files.each do |path|
  rel = Pathname.new(path).relative_path_from(Pathname.new(APP_DIR)).to_s
  group = app_group
  File.dirname(rel).split('/').each do |segment|
    next if segment == '.'
    group = group[segment] || group.new_group(segment, segment)
  end
  ref = group.new_reference(path)
  target.add_file_references([ref])
end

# Shared chat-model sources from the Mac tree.
shared_group = project.new_group('SharedFromMac', REPO_ROOT)
SHARED_MAC_SOURCES.each do |rel|
  path = File.join(REPO_ROOT, rel)
  raise "missing shared source #{path}" unless File.exist?(path)
  ref = shared_group.new_reference(path)
  target.add_file_references([ref])
end

# Resources: the asset catalog (Info.plist is referenced via INFOPLIST_FILE).
# SKIP_ASSETS exists only so the app's Swift can be compiled on machines whose
# iOS simulator runtime is too old for actool; never set it for a real build.
include_assets = ENV['SKIP_ASSETS'].nil?
if include_assets
  assets = File.join(APP_DIR, 'Resources', 'Assets.xcassets')
  assets_ref = app_group.new_reference(assets)
  target.add_resources([assets_ref])
end

# Local Swift package + product dependencies.
pkg_ref = project.new(Xcodeproj::Project::Object::XCLocalSwiftPackageReference)
pkg_ref.relative_path = 'CompanionCore'
project.root_object.package_references << pkg_ref

PACKAGE_PRODUCTS.each do |product|
  dependency = project.new(Xcodeproj::Project::Object::XCSwiftPackageProductDependency)
  dependency.product_name = product
  # For a local package, the product dependency must point back at the local
  # package reference, or the app target builds the products but cannot import
  # their modules.
  dependency.package = pkg_ref
  target.package_product_dependencies << dependency

  build_file = project.new(Xcodeproj::Project::Object::PBXBuildFile)
  build_file.product_ref = dependency
  target.frameworks_build_phase.files << build_file
end

# Build settings shared by Debug and Release.
target.build_configurations.each do |config|
  settings = config.build_settings
  settings['PRODUCT_BUNDLE_IDENTIFIER'] = BUNDLE_ID
  settings['PRODUCT_NAME'] = '$(TARGET_NAME)'
  settings['MARKETING_VERSION'] = '1.0'
  settings['CURRENT_PROJECT_VERSION'] = '1'
  settings['IPHONEOS_DEPLOYMENT_TARGET'] = DEPLOYMENT_TARGET
  settings['SWIFT_VERSION'] = '5.0'
  settings['TARGETED_DEVICE_FAMILY'] = '1,2'
  settings['GENERATE_INFOPLIST_FILE'] = 'NO'
  settings['INFOPLIST_FILE'] = 'iTerm2Companion/Resources/Info.plist'
  if include_assets
    settings['ASSETCATALOG_COMPILER_APPICON_NAME'] = 'AppIcon'
    settings['ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME'] = 'AccentColor'
  end
  settings['ENABLE_PREVIEWS'] = 'YES'
  settings['CODE_SIGN_STYLE'] = 'Automatic'
  settings['SWIFT_EMIT_LOC_STRINGS'] = 'YES'
end

project.save

# A shared scheme so `xcodebuild -scheme iTerm2Companion` works and the project
# is usable from a fresh checkout.
scheme = Xcodeproj::XCScheme.new
scheme.add_build_target(target)
scheme.set_launch_target(target)
scheme.save_as(PROJECT_PATH, 'iTerm2Companion', true)

puts "Wrote #{PROJECT_PATH}"
puts "Sources: #{swift_files.length} Swift files"
