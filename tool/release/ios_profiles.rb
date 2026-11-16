# Installs the App Store profiles that ios/ExportOptions.plist names, making
# them first when they are missing or unusable.
#
# For each bundle id in ExportOptions.plist, this looks the profile up by name
# through the App Store Connect API. It is used as it is when it is active, an
# App Store profile for that bundle id, holds the distribution certificate CI
# signs with, and does not expire within a week. Otherwise every profile with
# that name is deleted and a new one is created under the same name, with the
# certificate and the bundle id's current capabilities. Changing a capability
# on the App ID makes Apple invalidate its profiles, and a new certificate is
# not in the old profiles, so neither needs a visit to the developer portal:
# the next release replaces the profile.
#
# The profiles are written where Xcode looks for them. The certificate itself
# comes from the keychain the import step made, so only the profiles' names
# and bundle ids live in ExportOptions.plist.
#
# Usage (from the repository root, after the certificate is imported):
#   ruby tool/release/ios_profiles.rb --keychain signing_temp.keychain
#   ruby tool/release/ios_profiles.rb --certificate cert.pem   # a PEM file instead
#
# Environment: APPLE_API_ISSUER_ID, APPLE_API_KEY_ID and APPLE_API_PRIVATE_KEY
# (the .p8 text). ASC_API_URL and PROFILES_DIRS (colon-separated) override the
# API and the install folders, for testing.

require 'base64'
require 'fileutils'
require 'openssl'
require 'optparse'
require 'rexml/document'
require 'time'
require_relative 'lib/app_store_connect'
require_relative 'lib/ci_log'

PROFILE_TYPE = 'IOS_APP_STORE'.freeze
# Replaced this long before it expires, so a build never ships with a profile
# that lapses while the build waits for review.
MIN_DAYS_LEFT = 7
DISTRIBUTION_NAMES = /\A(Apple|iPhone) Distribution:/

# The plist subset ExportOptions.plist uses: dict, array, string and booleans.
def plist_value(element)
  case element.name
  when 'dict'
    element.elements.each_slice(2).to_h { |key, value| [key.text, plist_value(value)] }
  when 'array' then element.elements.map { |child| plist_value(child) }
  when 'string' then element.text.to_s
  when 'integer' then element.text.to_i
  when 'true' then true
  when 'false' then false
  else raise "Unsupported plist element <#{element.name}>"
  end
end

def read_plist(path)
  plist_value(REXML::Document.new(File.read(path)).root.elements[1])
end

def local_certificates(keychain:, pem_path:)
  pem = if pem_path
          File.read(pem_path)
        else
          IO.popen(['security', 'find-certificate', '-a', '-p', keychain], &:read).tap do
            fail!("Could not read certificates from the keychain #{keychain}") unless $?.success?
          end
        end
  pem.scan(/-----BEGIN CERTIFICATE-----.+?-----END CERTIFICATE-----/m)
     .map { |block| OpenSSL::X509::Certificate.new(block) }
     .select { |cert| common_name(cert)&.match?(DISTRIBUTION_NAMES) }
end

def common_name(cert)
  cert.subject.to_a.find { |name, _, _| name == 'CN' }&.at(1)
end

def describe(cert)
  "\"#{common_name(cert)}\" (serial #{cert.serial.to_s(16)}, expires #{cert.not_after.utc.to_date})"
end

def unusable_reason(profile, bundle_resource_id, certificate_id)
  attributes = profile['attributes']
  relationships = profile['relationships'] || {}
  return "it is #{attributes['profileState']}" unless attributes['profileState'] == 'ACTIVE'
  return "it is a #{attributes['profileType']} profile" unless attributes['profileType'] == PROFILE_TYPE
  unless relationships.dig('bundleId', 'data', 'id') == bundle_resource_id
    return 'it is for another bundle id'
  end
  unless (relationships.dig('certificates', 'data') || []).any? { |cert| cert['id'] == certificate_id }
    return 'it does not hold the certificate CI signs with'
  end

  expires = Time.parse(attributes['expirationDate'])
  return "it expires #{expires.utc.to_date}" if expires < Time.now + MIN_DAYS_LEFT * 86_400

  nil
end

def install(profile, directories)
  attributes = profile['attributes']
  content = Base64.decode64(attributes.fetch('profileContent'))
  directories.each do |directory|
    FileUtils.mkdir_p(directory)
    File.binwrite(File.join(directory, "#{attributes.fetch('uuid')}.mobileprovision"), content)
  end
end

def ensure_profile(api, name:, bundle_id:, certificate_id:, directories:)
  bundles, = api.get_all('/v1/bundleIds', 'filter[identifier]' => bundle_id, 'limit' => '200')
  bundle = bundles.find { |item| item.dig('attributes', 'identifier') == bundle_id }
  fail!("The App ID #{bundle_id} is not registered in the team.") unless bundle

  # Looked up by name rather than through the bundle id, whose list of related
  # profiles is cut short when the App ID has many (development, ad hoc and
  # Xcode's own).
  profiles, = api.get_all('/v1/profiles',
                          'filter[name]' => name,
                          'include' => 'bundleId,certificates',
                          'limit' => '200',
                          'limit[certificates]' => '50')
  profiles.select! { |profile| profile.dig('attributes', 'name') == name }

  reasons = profiles.to_h { |profile| [profile, unusable_reason(profile, bundle['id'], certificate_id)] }
  usable = profiles.find { |profile| reasons[profile].nil? }
  if usable
    install(usable, directories)
    puts "#{bundle_id}: using \"#{name}\" (#{usable.dig('attributes', 'uuid')}, " \
         "expires #{Time.parse(usable.dig('attributes', 'expirationDate')).utc.to_date})"
    return
  end

  # Profile names are unique in a team, so the old ones go before the new one
  # is made.
  profiles.each do |profile|
    puts "#{bundle_id}: deleting \"#{name}\" (#{profile.dig('attributes', 'uuid')}), because #{reasons[profile]}"
    api.delete("/v1/profiles/#{profile['id']}")
  end
  puts "#{bundle_id}: no usable \"#{name}\", creating it" if profiles.empty?

  created = api.create('/v1/profiles', {
                         data: {
                           type: 'profiles',
                           attributes: { name: name, profileType: PROFILE_TYPE },
                           relationships: {
                             bundleId: { data: { type: 'bundleIds', id: bundle['id'] } },
                             certificates: { data: [{ type: 'certificates', id: certificate_id }] }
                           }
                         }
                       })
  install(created, directories)
  puts "#{bundle_id}: created \"#{name}\" (#{created.dig('attributes', 'uuid')}, " \
       "expires #{Time.parse(created.dig('attributes', 'expirationDate')).utc.to_date})"
end

def main
  options = { 'export-options': 'ios/ExportOptions.plist' }
  OptionParser.new do |parser|
    parser.on('--keychain NAME', 'Keychain the distribution certificate was imported into')
    parser.on('--certificate PATH', 'PEM file with the distribution certificate, instead of a keychain')
    parser.on('--export-options PATH', 'ExportOptions.plist (default: ios/ExportOptions.plist)')
  end.parse!(into: options)
  fail!('Pass --keychain or --certificate') unless options[:keychain] || options[:certificate]

  export_options = read_plist(options[:'export-options'])
  profiles = export_options.fetch('provisioningProfiles')

  local = local_certificates(keychain: options[:keychain], pem_path: options[:certificate])
  fail!('No Apple Distribution certificate was found to sign with.') if local.empty?

  api = AppStoreConnect.from_env

  team_certificates, = api.get_all('/v1/certificates', 'limit' => '200')
  matches = local.filter_map do |cert|
    der = cert.to_der
    remote = team_certificates.find do |item|
      content = item.dig('attributes', 'certificateContent')
      content && Base64.decode64(content) == der
    end
    [cert, remote] if remote
  end
  if matches.empty?
    fail!("The signing certificate #{local.map { |cert| describe(cert) }.join(', ')} is not one of the " \
          "team's certificates, so it was revoked or belongs to another team. Create an Apple " \
          'Distribution certificate, export it with its private key as a .p12 and update the ' \
          'IOS_CERTIFICATE_P12_BASE64 and IOS_CERTIFICATE_PASSWORD secrets.')
  end
  cert, remote = matches.max_by { |local_cert, _| local_cert.not_after }
  if cert.not_after < Time.now
    fail!("The signing certificate #{describe(cert)} has expired. Create a new Apple Distribution " \
          'certificate and update the IOS_CERTIFICATE_* secrets.')
  end
  puts "Signing certificate: #{describe(cert)}"

  directories = ENV.fetch('PROFILES_DIRS', [
    File.join(Dir.home, 'Library/Developer/Xcode/UserData/Provisioning Profiles'), # Xcode 16 and later
    File.join(Dir.home, 'Library/MobileDevice/Provisioning Profiles')
  ].join(':')).split(':')

  profiles.each do |bundle_id, name|
    ensure_profile(api, name: name, bundle_id: bundle_id, certificate_id: remote['id'],
                        directories: directories)
  end
rescue AppStoreConnect::Error => e
  fail!(AppStoreConnect.explain(e, forbidden: 'The API key needs the Admin role, or App Manager with ' \
                                              'access to Certificates, Identifiers & Profiles, to read ' \
                                              'and make profiles.'))
end

main if $PROGRAM_NAME == __FILE__
