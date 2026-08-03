#!/usr/bin/env ruby
# Generates Companion/iTerm2Companion.xcodeproj from scratch. This project is the
# source of truth for the iTerm2 Buddy iOS app; re-run this script after adding,
# removing, or renaming source files (or changing build wiring) and commit the
# result. Requires the xcodeproj gem (already used by tools/add_file_to_xcodeproj.rb).
#
# It emits three targets:
#   * iTerm2Companion       - the SwiftUI app (application)
#   * PushService           - the notification-service extension (app-extension),
#                             embedded into the app and built before it
#   * iTerm2CompanionTests  - the unit-test bundle, hosted by the app
#
# Dependencies: the local CompanionCore Swift package (CompanionProtocol,
# CompanionNoise, CompanionTransport) and the remote WhisperKit package.

require 'xcodeproj'
require 'pathname'

COMPANION_DIR = File.expand_path('..', __dir__)
REPO_ROOT = File.expand_path('../..', __dir__)
PROJECT_PATH = File.join(COMPANION_DIR, 'iTerm2Companion.xcodeproj')
APP_DIR = File.join(COMPANION_DIR, 'iTerm2Companion')
PUSH_DIR = File.join(COMPANION_DIR, 'PushService')
TESTS_DIR = File.join(COMPANION_DIR, 'iTerm2CompanionTests')
BUNDLE_ID = 'com.googlecode.iterm2.companion'
TEAM = 'H7V7XYVQ7D'
# iOS 26: the TabView Tab API and tabBarMinimizeBehavior are used without
# availability checks. The app is unreleased and tracks the current OS.
DEPLOYMENT_TARGET = '26.0'
# Kept in sync by hand; bump when releasing (mirrors the old Xcode-managed values).
MARKETING_VERSION = '1.0'
CURRENT_PROJECT_VERSION = '4'
PACKAGE_PRODUCTS = %w[CompanionProtocol CompanionNoise CompanionTransport]
WHISPERKIT_URL = 'https://github.com/argmaxinc/WhisperKit.git'
WHISPERKIT_MIN_VERSION = '1.0.0'

# Chat-model sources shared with the Mac app. These compile into BOTH the
# iTerm2 app and this iOS app, so they must stay platform-neutral (each file
# carries a banner comment saying so). Heavy Mac-only leaf types they mention
# have same-named stand-ins in iTerm2Companion/Satellites/. When a shared file
# starts referencing a new shared type, add it here and re-run.
SHARED_MAC_SOURCES = %w[
  sources/AITerm/Message.swift
  sources/AITerm/Chat.swift
  sources/AITerm/RemoteCommand.swift
  sources/AITerm/LLM.swift
  sources/AITerm/AIExplanationRequest.swift
  sources/AITerm/AIExplanationResponse.swift
  sources/AITerm/iTermAIError.swift
  sources/AITerm/TerminalCommand.swift
  sources/AITerm/AIReasoningTypes.swift
  sources/Categories/Result+iTerm.swift
  sources/Categories/NSDictionaryCodableBox.swift
  sources/Categories/Data+BigEndian.swift
  sources/ClaudeCode/Orchestration/MentionParser.swift
  sources/ClaudeCode/Orchestration/StableSessionID.swift
  sources/ClaudeCode/Orchestration/WorkgroupWatcher.swift
  sources/Companion/CompanionMessageSubstance.swift
  sources/Companion/MentionPlainTextRenderer.swift
  sources/Companion/Shared/CompanionMessages.swift
  sources/Companion/Shared/CompanionPushRelay.swift
  sources/Companion/Shared/CompanionSession.swift
  sources/Companion/Shared/CompanionMediaFrame.swift
  sources/Companion/Shared/CompanionFrameChannel.swift
  sources/Companion/Shared/CompanionHEVCFraming.swift
  sources/Companion/Shared/CompanionHEVCSampleBuilder.swift
  sources/Companion/Shared/CompanionTouchMapper.swift
  sources/Companion/Shared/CompanionHistoryWindow.swift
]

# Source files compiled into the PushService extension. It links CompanionCore
# for wire types; it does not compile the shared Mac sources.
PUSH_SOURCES = %w[NotificationService.swift NSEFetcher.swift]

# Unit-test sources.
TEST_SOURCES = %w[AppModelWatchTests.swift SessionWatchStateTests.swift]

project = Xcodeproj::Project.new(PROJECT_PATH)

# Local + remote Swift package references.
local_pkg = project.new(Xcodeproj::Project::Object::XCLocalSwiftPackageReference)
local_pkg.relative_path = 'CompanionCore'
project.root_object.package_references << local_pkg

whisper_pkg = project.new(Xcodeproj::Project::Object::XCRemoteSwiftPackageReference)
whisper_pkg.repositoryURL = WHISPERKIT_URL
whisper_pkg.requirement = { 'kind' => 'upToNextMajorVersion', 'minimumVersion' => WHISPERKIT_MIN_VERSION }
project.root_object.package_references << whisper_pkg

# Links a Swift package product into a target: a product dependency plus a build
# file in the target's Frameworks phase. For a local package the dependency must
# point back at its package reference, or the target builds the product but
# cannot import its module.
def link_package_product(project, target, package, product_name)
  dependency = project.new(Xcodeproj::Project::Object::XCSwiftPackageProductDependency)
  dependency.product_name = product_name
  dependency.package = package
  target.package_product_dependencies << dependency

  build_file = project.new(Xcodeproj::Project::Object::PBXBuildFile)
  build_file.product_ref = dependency
  target.frameworks_build_phase.files << build_file
end

# ---------------------------------------------------------------------------
# PushService: notification-service extension. Created first so the app can take
# a dependency on it and embed its product.
# ---------------------------------------------------------------------------
push_target = project.new_target(:app_extension, 'PushService', :ios, DEPLOYMENT_TARGET)
push_group = project.new_group('PushService', 'PushService')
PUSH_SOURCES.each do |name|
  ref = push_group.new_reference(File.join(PUSH_DIR, name))
  push_target.add_file_references([ref])
end
# Referenced so it shows in the navigator; it is imported via the build setting
# below, not compiled.
push_group.new_reference(File.join(PUSH_DIR, 'PushService-Bridging-Header.h'))
PACKAGE_PRODUCTS.each { |product| link_package_product(project, push_target, local_pkg, product) }

push_target.build_configurations.each do |config|
  settings = config.build_settings
  settings['CODE_SIGN_ENTITLEMENTS'] = 'PushService/PushService.entitlements'
  settings['CODE_SIGN_STYLE'] = 'Automatic'
  settings['DEVELOPMENT_TEAM'] = TEAM
  settings['MARKETING_VERSION'] = MARKETING_VERSION
  settings['CURRENT_PROJECT_VERSION'] = CURRENT_PROJECT_VERSION
  settings['GENERATE_INFOPLIST_FILE'] = 'YES'
  settings['INFOPLIST_FILE'] = 'PushService/Info.plist'
  settings['INFOPLIST_KEY_CFBundleDisplayName'] = 'PushService'
  settings['IPHONEOS_DEPLOYMENT_TARGET'] = DEPLOYMENT_TARGET
  settings['PRODUCT_BUNDLE_IDENTIFIER'] = "#{BUNDLE_ID}.PushService"
  settings['PRODUCT_NAME'] = '$(TARGET_NAME)'
  settings['SDKROOT'] = 'iphoneos'
  settings['SKIP_INSTALL'] = 'YES'
  settings['SWIFT_OBJC_BRIDGING_HEADER'] = 'PushService/PushService-Bridging-Header.h'
  settings['SWIFT_EMIT_LOC_STRINGS'] = 'YES'
  settings['SWIFT_VERSION'] = '5.0'
  settings['TARGETED_DEVICE_FAMILY'] = '1,2'
  # An extension lives two levels down inside the app, hence the extra rpath.
  settings['LD_RUNPATH_SEARCH_PATHS'] = ['$(inherited)', '@executable_path/Frameworks', '@executable_path/../../Frameworks']
end

# ---------------------------------------------------------------------------
# iTerm2Companion: the app.
# ---------------------------------------------------------------------------
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
  # Icon Composer bundle; pairs with the AppIcon asset set by name (the .icon
  # is used on iOS 26+, the asset set is the fallback for older systems).
  icon = File.join(APP_DIR, 'Resources', 'AppIcon.icon')
  icon_ref = app_group.new_reference(icon)
  target.add_resources([icon_ref])
end

# Package products: CompanionCore (local) + WhisperKit (remote, for dictation).
PACKAGE_PRODUCTS.each { |product| link_package_product(project, target, local_pkg, product) }
link_package_product(project, target, whisper_pkg, 'WhisperKit')

# Build PushService before the app and embed the resulting .appex.
target.add_dependency(push_target)
embed_phase = target.new_copy_files_build_phase('Embed Foundation Extensions')
embed_phase.symbol_dst_subfolder_spec = :plug_ins
embed_phase.dst_path = ''
embed_build_file = embed_phase.add_file_reference(push_target.product_reference, true)
embed_build_file.settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy'] }

target.build_configurations.each do |config|
  settings = config.build_settings
  settings['PRODUCT_BUNDLE_IDENTIFIER'] = BUNDLE_ID
  settings['PRODUCT_NAME'] = '$(TARGET_NAME)'
  settings['MARKETING_VERSION'] = MARKETING_VERSION
  settings['CURRENT_PROJECT_VERSION'] = CURRENT_PROJECT_VERSION
  settings['IPHONEOS_DEPLOYMENT_TARGET'] = DEPLOYMENT_TARGET
  settings['SWIFT_VERSION'] = '5.0'
  settings['TARGETED_DEVICE_FAMILY'] = '1,2'
  settings['GENERATE_INFOPLIST_FILE'] = 'NO'
  settings['INFOPLIST_FILE'] = 'iTerm2Companion/Resources/Info.plist'
  settings['SDKROOT'] = 'iphoneos'
  settings['CLANG_ENABLE_OBJC_WEAK'] = 'NO'
  settings['LD_RUNPATH_SEARCH_PATHS'] = ['$(inherited)', '@executable_path/Frameworks']
  if include_assets
    settings['ASSETCATALOG_COMPILER_APPICON_NAME'] = 'AppIcon'
    settings['ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME'] = 'AccentColor'
  end
  settings['ENABLE_PREVIEWS'] = 'YES'
  settings['CODE_SIGN_STYLE'] = 'Automatic'
  settings['DEVELOPMENT_TEAM'] = TEAM
  settings['SWIFT_EMIT_LOC_STRINGS'] = 'YES'
  # Per-config entitlements select the APNs environment: development pushes in
  # Debug, production in Release. Automatic signing provisions the aps-environment
  # capability because run_on_iphone.sh passes -allowProvisioningUpdates.
  if config.name == 'Debug'
    settings['CODE_SIGN_ENTITLEMENTS'] = 'iTerm2Companion/Resources/iTerm2Companion-Debug.entitlements'
  else
    settings['CODE_SIGN_ENTITLEMENTS'] = 'iTerm2Companion/Resources/iTerm2Companion-Release.entitlements'
    settings['VALIDATE_PRODUCT'] = 'YES'
  end
end

# ---------------------------------------------------------------------------
# iTerm2CompanionTests: unit-test bundle hosted by the app.
# ---------------------------------------------------------------------------
tests_target = project.new_target(:unit_test_bundle, 'iTerm2CompanionTests', :ios, DEPLOYMENT_TARGET)
tests_group = project.new_group('iTerm2CompanionTests', 'iTerm2CompanionTests')
TEST_SOURCES.each do |name|
  ref = tests_group.new_reference(File.join(TESTS_DIR, name))
  tests_target.add_file_references([ref])
end
tests_target.add_dependency(target)

tests_target.build_configurations.each do |config|
  settings = config.build_settings
  settings['BUNDLE_LOADER'] = '$(TEST_HOST)'
  settings['TEST_HOST'] = '$(BUILT_PRODUCTS_DIR)/iTerm2Companion.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/iTerm2Companion'
  settings['PRODUCT_BUNDLE_IDENTIFIER'] = "#{BUNDLE_ID}.tests"
  settings['GENERATE_INFOPLIST_FILE'] = 'YES'
  settings['IPHONEOS_DEPLOYMENT_TARGET'] = DEPLOYMENT_TARGET
  settings['SDKROOT'] = 'iphoneos'
  settings['SWIFT_VERSION'] = '5.0'
  settings['CODE_SIGN_STYLE'] = 'Automatic'
  settings['DEVELOPMENT_TEAM'] = TEAM
end

project.save

# A shared scheme so `xcodebuild -scheme iTerm2Companion` works (build, run, and
# test) from a fresh checkout.
scheme = Xcodeproj::XCScheme.new
scheme.add_build_target(target)
scheme.set_launch_target(target)
scheme.add_test_target(tests_target)
scheme.save_as(PROJECT_PATH, 'iTerm2Companion', true)

puts "Wrote #{PROJECT_PATH}"
puts "Targets: iTerm2Companion (app), PushService (extension), iTerm2CompanionTests"
puts "App sources: #{swift_files.length} Swift files; shared: #{SHARED_MAC_SOURCES.length}"
