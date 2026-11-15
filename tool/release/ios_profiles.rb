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
require 'json'
require 'net/http'
require 'openssl'
require 'optparse'
require 'rexml/document'
require 'time'
require 'uri'

PROFILE_TYPE = 'IOS_APP_STORE'.freeze
# Replaced this long before it expires, so a build never ships with a profile
# that lapses while the build waits for review.
MIN_DAYS_LEFT = 7
DISTRIBUTION_NAMES = /\A(Apple|iPhone) Distribution:/

def fail!(message)
  warn "::error::#{message}"
  exit 1
end

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

# A small App Store Connect API client: a short-lived ES256 token and JSON
# requests that follow pagination.
class AppStoreConnect
  class Error < StandardError
    attr_reader :status

    def initialize(status, message)
      @status = status
      super(message)
    end
  end

  def initialize(issuer_id:, key_id:, private_key:, base_url:)
    @issuer_id = issuer_id
    @key_id = key_id
    # Secrets pasted with literal "\n" still read as a key.
    @key = OpenSSL::PKey.read(private_key.gsub('\n', "\n"))
    @base_url = base_url
  end

  def get_all(path, query = {})
    items = []
    included = []
    url = build_url(path, query)
    while url
      page = request(:get, url)
      items.concat(page['data'])
      included.concat(page['included'] || [])
      url = page.dig('links', 'next')
    end
    [items, included]
  end

  def create(path, body)
    request(:post, build_url(path), body)['data']
  end

  def delete(path)
    request(:delete, build_url(path))
  end

  private

  def build_url(path, query = {})
    uri = URI.join(@base_url, path)
    uri.query = URI.encode_www_form(query) unless query.empty?
    uri.to_s
  end

  def request(method, url, body = nil)
    uri = URI(url)
    request = { get: Net::HTTP::Get, post: Net::HTTP::Post, delete: Net::HTTP::Delete }
              .fetch(method).new(uri)
    request['Authorization'] = "Bearer #{token}"
    if body
      request['Content-Type'] = 'application/json'
      request.body = JSON.generate(body)
    end
    response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https',
                                                   open_timeout: 30, read_timeout: 60) do |http|
      http.request(request)
    end
    unless response.is_a?(Net::HTTPSuccess)
      raise Error.new(response.code.to_i,
                      "#{method.upcase} #{uri.path} failed with #{response.code}: #{error_detail(response.body)}")
    end
    response.body.to_s.empty? ? {} : JSON.parse(response.body)
  end

  def error_detail(body)
    errors = JSON.parse(body.to_s)['errors'] || []
    errors.map { |error| [error['title'], error['detail']].compact.join(': ') }.join('; ')
  rescue JSON::ParserError
    body.to_s[0, 300]
  end

  # Valid for 15 minutes; Apple allows at most 20.
  def token
    now = Time.now.to_i
    return @token if @token && now < @token_expires - 60

    header = { alg: 'ES256', kid: @key_id, typ: 'JWT' }
    payload = { iss: @issuer_id, iat: now, exp: now + 900, aud: 'appstoreconnect-v1' }
    signing_input = [header, payload].map { |part| base64url(JSON.generate(part)) }.join('.')
    der = @key.sign(OpenSSL::Digest.new('SHA256'), signing_input)
    # JWS wants the raw r || s pair, not the DER sequence OpenSSL returns.
    raw = OpenSSL::ASN1.decode(der).value.map { |n| n.value.to_s(2).rjust(32, "\0") }.join
    @token_expires = payload[:exp]
    @token = "#{signing_input}.#{base64url(raw)}"
  end

  def base64url(data)
    Base64.urlsafe_encode64(data, padding: false)
  end
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
  $stdout.sync = true # Keeps progress and ::error:: lines in order in the CI log
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

  api = AppStoreConnect.new(
    issuer_id: ENV.fetch('APPLE_API_ISSUER_ID'),
    key_id: ENV.fetch('APPLE_API_KEY_ID'),
    private_key: ENV.fetch('APPLE_API_PRIVATE_KEY'),
    base_url: ENV.fetch('ASC_API_URL', 'https://api.appstoreconnect.apple.com')
  )

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
  hint = if e.status == 401
           ' Check APPLE_API_KEY_ID, APPLE_API_ISSUER_ID and APPLE_API_PRIVATE_KEY.'
         elsif e.status == 403
           ' The API key needs the Admin role, or App Manager with access to Certificates, ' \
             'Identifiers & Profiles, to read and make profiles.'
         else
           ''
         end
  fail!("#{e.message}.#{hint}")
end

main if $PROGRAM_NAME == __FILE__
