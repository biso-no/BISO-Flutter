# A small App Store Connect API client for the release scripts: a short-lived
# ES256 token and JSON requests that follow pagination.
#
# Environment: APPLE_API_ISSUER_ID, APPLE_API_KEY_ID and APPLE_API_PRIVATE_KEY
# (the .p8 text). ASC_API_URL overrides the API, for testing.

require 'base64'
require 'json'
require 'net/http'
require 'openssl'
require 'uri'

class AppStoreConnect
  class Error < StandardError
    attr_reader :status, :codes

    def initialize(status, codes, message)
      @status = status
      @codes = codes
      super(message)
    end
  end

  def self.from_env
    new(
      issuer_id: ENV.fetch('APPLE_API_ISSUER_ID'),
      key_id: ENV.fetch('APPLE_API_KEY_ID'),
      private_key: ENV.fetch('APPLE_API_PRIVATE_KEY'),
      base_url: ENV.fetch('ASC_API_URL', 'https://api.appstoreconnect.apple.com')
    )
  end

  # The error's message with what to do about it. `forbidden` says what the
  # calling script needs the key to be allowed to do, for a plain 403.
  def self.explain(error, forbidden:)
    hint = if error.codes.any? { |code| code.include?('REQUIRED_AGREEMENTS') }
             # Apple refuses every API call until the Account Holder accepts an
             # updated agreement; no key, role or secret fixes this.
             ' The Account Holder must accept the updated agreement: sign in at ' \
               'https://developer.apple.com/account (and check App Store Connect, ' \
               'Business), accept it, then re-run this job.'
           elsif error.status == 401
             ' Check APPLE_API_KEY_ID, APPLE_API_ISSUER_ID and APPLE_API_PRIVATE_KEY.'
           elsif error.status == 403
             " #{forbidden}"
           else
             ''
           end
    "#{error.message}.#{hint}"
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

  # One resource, or nil when there is none (a to-one relationship that is
  # empty answers either 404 or null data).
  def get_one(path, query = {})
    request(:get, build_url(path, query))['data']
  rescue Error => e
    raise unless e.status == 404

    nil
  end

  def create(path, body)
    request(:post, build_url(path), body)['data']
  end

  def update(path, body)
    request(:patch, build_url(path), body)['data']
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
    request = { get: Net::HTTP::Get, post: Net::HTTP::Post, patch: Net::HTTP::Patch,
                delete: Net::HTTP::Delete }.fetch(method).new(uri)
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
      errors = parse_errors(response.body)
      detail = errors.map do |error|
        error.values_at('code', 'title', 'detail').compact.map { |part| part.chomp('.') }.join(': ')
      end.join('; ')
      detail = response.body.to_s[0, 300] if errors.empty?
      raise Error.new(response.code.to_i, errors.map { |error| error['code'].to_s },
                      "#{method.upcase} #{uri.path} failed with #{response.code}: #{detail}")
    end
    response.body.to_s.empty? ? {} : JSON.parse(response.body)
  end

  def parse_errors(body)
    JSON.parse(body.to_s)['errors'] || []
  rescue JSON::ParserError
    []
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
