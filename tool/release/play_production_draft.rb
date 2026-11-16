# Puts a release's build on Google Play's production track as a draft, so
# sending it for review is the only step left in Play Console.
#
# Run after the internal testing upload, which already put the build in the
# app's library. This adds that build to production as a draft release with
# the same name and release notes. A draft left by an earlier release is
# replaced, so production always offers the newest build; the track's other
# releases (the live one, a staged rollout) are sent back unchanged. When
# production already has this build or a newer one, for example after someone
# promoted it in Play Console, no draft is added and any draft that build
# outdates is removed.
#
# Nothing is rolled out: Play Console shows the draft under Production, and
# reviewing it and starting the rollout stays a person's decision.
#
# Usage (from the repository root):
#   ruby tool/release/play_production_draft.rb --version-code 101 \
#     --name "2.3.0 (101)" --notes release-notes/play
#
# --notes is a folder of whatsnew-<language> files, as
# tool/release/release_notes.py writes them. Environment:
# GOOGLE_PLAY_SERVICE_ACCOUNT_JSON (the service account's key file, as text).
# PLAY_API_URL and PLAY_TOKEN_URL override the endpoints, for testing.

require 'base64'
require 'json'
require 'net/http'
require 'openssl'
require 'optparse'
require 'uri'
require_relative 'lib/ci_log'

PACKAGE = 'com.biso.no'.freeze
TRACK = 'production'.freeze

# The Google Play Developer API, signed in as the service account.
class GooglePlay
  class Error < StandardError
    attr_reader :status

    def initialize(status, message)
      @status = status
      super(message)
    end
  end

  SCOPE = 'https://www.googleapis.com/auth/androidpublisher'.freeze

  def initialize(service_account_json, package:)
    account = JSON.parse(service_account_json)
    @email = account.fetch('client_email')
    @key = OpenSSL::PKey::RSA.new(account.fetch('private_key'))
    @token_url = ENV.fetch('PLAY_TOKEN_URL', account['token_uri'] || 'https://oauth2.googleapis.com/token')
    base = ENV.fetch('PLAY_API_URL', 'https://androidpublisher.googleapis.com')
    @base = "#{base}/androidpublisher/v3/applications/#{package}/"
  end

  def call(method, path, body = nil)
    uri = URI.join(@base, path)
    request = { get: Net::HTTP::Get, post: Net::HTTP::Post, put: Net::HTTP::Put,
                delete: Net::HTTP::Delete }.fetch(method).new(uri)
    request['Authorization'] = "Bearer #{token}"
    request['Content-Type'] = 'application/json'
    request.body = JSON.generate(body) if body
    response = send_request(uri, request)
    unless response.is_a?(Net::HTTPSuccess)
      raise Error.new(response.code.to_i, "#{method.upcase} #{uri.path} failed with #{response.code}: " \
                                          "#{error_message(response.body)}")
    end
    response.body.to_s.empty? ? {} : JSON.parse(response.body)
  end

  private

  def send_request(uri, request)
    Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https', open_timeout: 30,
                                        read_timeout: 120) { |http| http.request(request) }
  end

  def error_message(body)
    JSON.parse(body.to_s).dig('error', 'message') || body.to_s[0, 300]
  rescue JSON::ParserError
    body.to_s[0, 300]
  end

  # An OAuth token for a JWT the service account signs (RS256).
  def token
    return @token if @token

    now = Time.now.to_i
    claims = { iss: @email, scope: SCOPE, aud: @token_url, iat: now, exp: now + 3600 }
    signing_input = [{ alg: 'RS256', typ: 'JWT' }, claims].map { |part| base64url(JSON.generate(part)) }.join('.')
    assertion = "#{signing_input}.#{base64url(@key.sign(OpenSSL::Digest.new('SHA256'), signing_input))}"
    uri = URI(@token_url)
    request = Net::HTTP::Post.new(uri)
    request.set_form_data('grant_type' => 'urn:ietf:params:oauth:grant-type:jwt-bearer', 'assertion' => assertion)
    response = send_request(uri, request)
    unless response.is_a?(Net::HTTPSuccess)
      raise Error.new(response.code.to_i, "Signing in to Google failed with #{response.code}: " \
                                          "#{response.body.to_s[0, 300]}")
    end
    @token = JSON.parse(response.body).fetch('access_token')
  end

  def base64url(data)
    Base64.urlsafe_encode64(data, padding: false)
  end
end

def read_notes(folder)
  notes = Dir.glob(File.join(folder, 'whatsnew-*')).sort.map do |path|
    { language: File.basename(path).delete_prefix('whatsnew-'), text: File.read(path).strip }
  end
  fail!("No whatsnew-<language> files in #{folder}") if notes.empty?
  notes
end

def main
  options = {}
  OptionParser.new do |parser|
    parser.on('--version-code CODE', 'The build number, like 101')
    parser.on('--name NAME', 'Release name, like "2.3.0 (101)"')
    parser.on('--notes FOLDER', 'Folder of whatsnew-<language> files')
  end.parse!(into: options)
  version_code, name, notes_folder = options.values_at(:'version-code', :name, :notes)
  fail!('Pass --version-code, --name and --notes') unless version_code && name && notes_folder

  draft = { name: name, versionCodes: [version_code], status: 'draft', releaseNotes: read_notes(notes_folder) }
  play = GooglePlay.new(ENV.fetch('GOOGLE_PLAY_SERVICE_ACCOUNT_JSON'), package: PACKAGE)

  edit = play.call(:post, 'edits', {})['id']
  begin
    current = begin
      play.call(:get, "edits/#{edit}/tracks/#{TRACK}")['releases'] || []
    rescue GooglePlay::Error => e
      raise unless e.status == 404

      []
    end
    drafts, kept = current.partition { |release| release['status'] == 'draft' }
    kept.each { |release| puts "Keeping the #{release['status']} release #{release['name'].inspect}" }
    newest = kept.flat_map { |release| Array(release['versionCodes']).map(&:to_i) }.max || 0
    outdated = newest >= version_code.to_i
    # A draft holding nothing newer than production is outdated too.
    stale = drafts.select do |release|
      !outdated || Array(release['versionCodes']).map(&:to_i).max.to_i <= newest
    end
    if outdated && stale.empty?
      play.call(:delete, "edits/#{edit}")
      puts "Production already has version code #{newest}, so there is nothing to prepare."
      summary("- **Google Play:** nothing to prepare. Production already has version code #{newest}.")
      return
    end
    stale.each { |release| puts "Removing the draft #{release['name'].inspect} (#{release['versionCodes']&.join(', ')})" }

    releases = current - stale
    releases += [draft] unless outdated
    play.call(:put, "edits/#{edit}/tracks/#{TRACK}", { track: TRACK, releases: releases })
    begin
      play.call(:post, "edits/#{edit}:commit")
    rescue GooglePlay::Error => e
      # Apps whose changes go to review only from Play Console must say so.
      raise unless e.message.include?('changesNotSentForReview')

      play.call(:post, "edits/#{edit}:commit?changesNotSentForReview=true")
    end
  rescue StandardError
    begin
      play.call(:delete, "edits/#{edit}")
    rescue GooglePlay::Error
      nil # The edit expires on its own.
    end
    raise
  end

  if outdated
    puts "Production already has version code #{newest}, so no draft was added."
    summary("- **Google Play:** nothing to prepare. Production already has version code #{newest}; " \
            'outdated drafts were removed.')
    return
  end
  puts "Production draft #{name.inspect} holds version code #{version_code}"
  summary("- **Google Play:** a draft production release #{name} is ready. In Play Console, open " \
          '**Production**, edit the draft release, choose **Next**, then **Save and publish** ' \
          '(or **Send for review**).')
rescue GooglePlay::Error => e
  hint = e.status == 403 ? ' The service account needs permission to release to production.' : ''
  fail!("#{e.message}.#{hint}")
end

main if $PROGRAM_NAME == __FILE__
