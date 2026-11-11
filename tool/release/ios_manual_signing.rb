# Switches the app and share extension to manual signing for Release builds.
#
# The project uses automatic signing, which needs an Apple account signed in to
# Xcode. CI has none, so before `flutter build ipa` this points each target's
# Release configuration at the Apple Distribution certificate and the App Store
# profile that ios/ExportOptions.plist names for its bundle id. The change is
# made on the CI checkout only and is never committed.
#
# Usage (from the repository root): ruby tool/release/ios_manual_signing.rb

require 'xcodeproj'

export_options = Xcodeproj::Plist.read_from_path('ios/ExportOptions.plist')
team_id = export_options.fetch('teamID')
profiles = export_options.fetch('provisioningProfiles')
identity = export_options.fetch('signingCertificate')

project = Xcodeproj::Project.open('ios/Runner.xcodeproj')
signed = []

project.native_targets.each do |target|
  release = target.build_configurations.find { |config| config.name == 'Release' }
  next unless release

  bundle_id = release.build_settings['PRODUCT_BUNDLE_IDENTIFIER']
  profile = profiles[bundle_id]
  next unless profile

  release.build_settings.merge!(
    'CODE_SIGN_STYLE' => 'Manual',
    'DEVELOPMENT_TEAM' => team_id,
    'CODE_SIGN_IDENTITY' => identity,
    'CODE_SIGN_IDENTITY[sdk=iphoneos*]' => identity,
    'PROVISIONING_PROFILE_SPECIFIER' => profile
  )
  signed << bundle_id
  puts "#{target.name} (#{bundle_id}): #{identity}, profile \"#{profile}\""
end

missing = profiles.keys - signed
abort "No Release target found for #{missing.join(', ')}" unless missing.empty?

project.save
