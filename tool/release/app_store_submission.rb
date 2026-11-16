# Gets the App Store version for a release ready for review, so submitting it
# is the only step left in App Store Connect.
#
# Run after the build is in TestFlight. It takes the iOS version that has not
# been submitted yet, or creates one, and sets its version number, attaches the
# build and writes "What's New" in each of the version's languages (the
# Norwegian notes for Norwegian, the English notes for every other language).
# Every release moves that same unsubmitted version forward, so App Store
# Connect always offers the newest TestFlight build. App Review contact details
# and the copyright are copied from the previous version when the version has
# none. A version that is already with Apple (waiting for review, in review,
# waiting to be released) is left alone, and this only says so.
#
# Nothing is submitted: choosing "Add for Review" stays a person's decision.
#
# Usage (from the repository root):
#   ruby tool/release/app_store_submission.rb --version 2.3.0 --build 101 \
#     --notes release-notes/play
#
# --notes is a folder holding whatsnew-en-US and whatsnew-no-NO, as
# tool/release/release_notes.py writes them. Environment: as for
# tool/release/lib/app_store_connect.rb.

require 'optparse'
require_relative 'lib/app_store_connect'
require_relative 'lib/ci_log'

BUNDLE_ID = 'com.biso.no'.freeze

# Versions whose build and metadata can still be changed.
EDITABLE_STATES = %w[PREPARE_FOR_SUBMISSION DEVELOPER_REJECTED REJECTED METADATA_REJECTED
                     INVALID_BINARY].freeze
# Versions submitted and not yet live. Apple allows no new version meanwhile.
WITH_APPLE_STATES = %w[READY_FOR_REVIEW WAITING_FOR_REVIEW IN_REVIEW WAITING_FOR_EXPORT_COMPLIANCE
                       PENDING_DEVELOPER_RELEASE PENDING_APPLE_RELEASE PROCESSING_FOR_DISTRIBUTION
                       ACCEPTED].freeze
REVIEW_DETAIL_FIELDS = %w[contactFirstName contactLastName contactPhone contactEmail
                          demoAccountName demoAccountPassword demoAccountRequired notes].freeze

# Apple processes a build for a few minutes after the upload reports it.
BUILD_ATTEMPTS = Integer(ENV.fetch('BUILD_ATTEMPTS', '20'))
BUILD_RETRY_SECONDS = Integer(ENV.fetch('BUILD_RETRY_SECONDS', '30'))

def state(version)
  version.dig('attributes', 'appVersionState') || version.dig('attributes', 'appStoreState')
end

def label(version)
  "#{version.dig('attributes', 'versionString')} (#{state(version)})"
end

def norwegian?(locale)
  locale.match?(/\A(no|nb|nn)\b/i)
end

def read_notes(folder)
  notes = %w[en-US no-NO].to_h do |language|
    path = File.join(folder, "whatsnew-#{language}")
    fail!("No release notes at #{path}") unless File.exist?(path)
    [language, File.read(path).strip]
  end
  fail!('The release notes are empty') if notes.values.any?(&:empty?)
  notes
end

def find_build(api, app_id, version, build_number)
  BUILD_ATTEMPTS.times do |attempt|
    builds, = api.get_all('/v1/builds', 'filter[app]' => app_id, 'filter[version]' => build_number,
                                        'filter[preReleaseVersion.version]' => version, 'limit' => '10')
    build = builds.first
    processing = build&.dig('attributes', 'processingState')
    return build if processing == 'VALID'
    if %w[FAILED INVALID].include?(processing)
      fail!("Build #{version} (#{build_number}) is #{processing} in App Store Connect.")
    end

    puts "Build #{version} (#{build_number}) is #{processing || 'not visible yet'}; " \
         "checking again in #{BUILD_RETRY_SECONDS} s (#{attempt + 1}/#{BUILD_ATTEMPTS})"
    sleep BUILD_RETRY_SECONDS
  end
  fail!("Build #{version} (#{build_number}) did not become valid in App Store Connect.")
end

# The version to prepare, created when there is none to reuse. Returns nil when
# a version is already with Apple.
def prepare_version(api, app_id, versions, version_string, build)
  submitted = versions.find { |version| WITH_APPLE_STATES.include?(state(version)) }
  if submitted
    warning!("Version #{label(submitted)} is already with Apple, which allows no other version " \
             "until it is released or removed from review, so #{version_string} was not prepared. " \
             'Run "Prepare store submissions" for this release once it is.')
    summary("- **App Store:** not prepared. Version #{label(submitted)} is already with Apple.")
    return nil
  end

  editable = versions.find { |version| EDITABLE_STATES.include?(state(version)) }
  previous = versions.find { |version| !version.equal?(editable) }
  copyright = previous&.dig('attributes', 'copyright')
  build_link = { build: { data: { type: 'builds', id: build['id'] } } }

  if editable
    attributes = {}
    attributes[:versionString] = version_string unless editable.dig('attributes', 'versionString') == version_string
    attributes[:copyright] = copyright if editable.dig('attributes', 'copyright').to_s.empty? && copyright
    puts "Updating version #{label(editable)}: version #{version_string}, build #{build.dig('attributes', 'version')}"
    data = { type: 'appStoreVersions', id: editable['id'], relationships: build_link }
    data[:attributes] = attributes unless attributes.empty?
    api.update("/v1/appStoreVersions/#{editable['id']}", { data: data })
  else
    puts "Creating version #{version_string} with build #{build.dig('attributes', 'version')}"
    attributes = { platform: 'IOS', versionString: version_string }
    attributes[:copyright] = copyright if copyright
    api.create('/v1/appStoreVersions', {
                 data: {
                   type: 'appStoreVersions',
                   attributes: attributes,
                   relationships: { app: { data: { type: 'apps', id: app_id } } }.merge(build_link)
                 }
               })
  end
end

# Writes What's New, and returns what still needs a person in App Store Connect.
def write_whats_new(api, version_id, notes)
  localizations, = api.get_all("/v1/appStoreVersions/#{version_id}/appStoreVersionLocalizations",
                               'limit' => '200')
  return ['the version has no languages; add them in App Store Connect'] if localizations.empty?

  gaps = []
  localizations.each do |localization|
    locale = localization.dig('attributes', 'locale')
    text = notes[norwegian?(locale) ? 'no-NO' : 'en-US']
    unless localization.dig('attributes', 'whatsNew') == text
      api.update("/v1/appStoreVersionLocalizations/#{localization['id']}", {
                   data: { type: 'appStoreVersionLocalizations', id: localization['id'],
                           attributes: { whatsNew: text } }
                 })
    end
    puts "What's New written for #{locale}"
    gaps << "#{locale} has no description" if localization.dig('attributes', 'description').to_s.strip.empty?
    sets, = api.get_all("/v1/appStoreVersionLocalizations/#{localization['id']}/appScreenshotSets")
    gaps << "#{locale} has no screenshots" if sets.empty?
  end
  gaps
end

# Copies App Review contact details from the newest version that has them, and
# returns what still needs a person.
def ensure_review_detail(api, version_id, versions)
  return [] if api.get_one("/v1/appStoreVersions/#{version_id}/appStoreReviewDetail")

  versions.each do |version|
    next if version['id'] == version_id

    source = api.get_one("/v1/appStoreVersions/#{version['id']}/appStoreReviewDetail")
    next unless source

    attributes = source['attributes'].slice(*REVIEW_DETAIL_FIELDS).compact
    api.create('/v1/appStoreReviewDetails', {
                 data: {
                   type: 'appStoreReviewDetails',
                   attributes: attributes,
                   relationships: { appStoreVersion: { data: { type: 'appStoreVersions', id: version_id } } }
                 }
               })
    puts "App Review details copied from version #{label(version)}"
    return []
  end
  ['App Review contact details are missing (fill them in once; later versions copy them)']
end

def main
  options = {}
  OptionParser.new do |parser|
    parser.on('--version VERSION', 'Version name, like 2.3.0')
    parser.on('--build NUMBER', 'Build number, like 101')
    parser.on('--notes FOLDER', 'Folder with whatsnew-en-US and whatsnew-no-NO')
  end.parse!(into: options)
  version_string, build_number, notes_folder = options.values_at(:version, :build, :notes)
  fail!('Pass --version, --build and --notes') unless version_string && build_number && notes_folder

  notes = read_notes(notes_folder)
  api = AppStoreConnect.from_env

  apps, = api.get_all('/v1/apps', 'filter[bundleId]' => BUNDLE_ID)
  app = apps.find { |item| item.dig('attributes', 'bundleId') == BUNDLE_ID }
  fail!("No app with the bundle id #{BUNDLE_ID} in App Store Connect.") unless app

  build = find_build(api, app['id'], version_string, build_number)
  versions, = api.get_all("/v1/apps/#{app['id']}/appStoreVersions", 'filter[platform]' => 'IOS',
                                                                       'limit' => '200')
  versions.sort_by! { |version| version.dig('attributes', 'createdDate').to_s }.reverse!

  version = prepare_version(api, app['id'], versions, version_string, build)
  return unless version

  gaps = write_whats_new(api, version['id'], notes) + ensure_review_detail(api, version['id'], versions)
  if gaps.empty?
    summary("- **App Store:** version #{version_string} with build #{build_number} is ready. " \
            'In App Store Connect, open it and choose **Add for Review**.')
  else
    gaps.each { |gap| warning!("App Store version #{version_string}: #{gap}") }
    summary("- **App Store:** version #{version_string} has build #{build_number} and What's New, " \
            "but needs: #{gaps.join('; ')}.")
  end
rescue AppStoreConnect::Error => e
  fail!(AppStoreConnect.explain(e, forbidden: 'The API key needs the Admin or App Manager role to ' \
                                              'prepare App Store versions.'))
end

main if $PROGRAM_NAME == __FILE__
