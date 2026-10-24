#!/usr/bin/env ruby
# One-purpose publisher for the user-approved chrome-ring header. Invoked by
# a user LaunchAgent; all credentials stay in the existing private config.
require 'json'
require 'jwt'
require 'openssl'
require 'net/http'
require 'time'
require 'rubygems/version'

module HeaderPublication
  APP = '6686407796'.freeze
  BUNDLE = 'Jan-van-Rensburg.N4x4'.freeze
  VIDEO = '0a000018-e8a7-8c74-8128-2b84ccf4117b'.freeze
  SPEC = '8aeaae00-2a17-4781-bfc0-44ca02e26ccb'.freeze
  FILE = 'N4x4-Chrome-Ring-Header-v2.mp4'.freeze
  MINIMUM_RELEASE = Gem::Version.new('5.10')
  STATE_ROOT = File.expand_path('~/.local/share/n4x4-header-publication').freeze
  STATE_PATH = File.join(STATE_ROOT, 'state.json').freeze

  def self.request(path, method: 'GET', body: nil)
    raise 'Unexpected API path' unless path.start_with?('/v1/')
    key_path = File.expand_path('~/.config/n4x4/app-store-api-key.json')
    raise 'Credential permissions must remain private' unless (File.stat(key_path).mode & 0o077).zero?
    credential = JSON.parse(File.read(key_path))
    now = Time.now.to_i
    token = JWT.encode({iss: credential.fetch('issuer_id'), iat: now, exp: now + 300,
                        aud: 'appstoreconnect-v1'}, OpenSSL::PKey.read(credential.fetch('key')),
                       'ES256', {kid: credential.fetch('key_id'), typ: 'JWT'})
    uri = URI("https://api.appstoreconnect.apple.com#{path}")
    req = Net::HTTP.const_get(method.capitalize).new(uri)
    req['Authorization'] = "Bearer #{token}"
    req['Content-Type'] = 'application/json'
    req.body = JSON.generate(body) if body
    response = Net::HTTP.start(uri.host, uri.port, use_ssl: true,
                              open_timeout: 15, read_timeout: 45) { |http| http.request(req) }
    parsed = response.body.to_s.empty? ? {} : JSON.parse(response.body)
    unless response.is_a?(Net::HTTPSuccess)
      errors = parsed.fetch('errors', []).map { |e| [e['code'], e['detail']] }
      raise "HTTP #{response.code}: #{errors.to_json}"
    end
    parsed
  end

  def self.save(state)
    state['checkedAt'] = Time.now.utc.iso8601
    temp = STATE_PATH + '.new'
    File.write(temp, JSON.pretty_generate(state) + "\n", perm: 0o600)
    File.rename(temp, STATE_PATH)
    puts JSON.generate(state.slice('status', 'assetState', 'publishedVersion', 'checkedAt', 'error'))
  end

  def self.load_state
    File.exist?(STATE_PATH) ? JSON.parse(File.read(STATE_PATH)) : {}
  end

  def self.run(check_only: false)
    state = load_state
    return if state['status'] == 'COMPLETE'
    raise 'State references a different asset' if state['videoID'] && state['videoID'] != VIDEO
    state['videoID'] = VIDEO
    video = request("/v1/appAssetLibraryVideos/#{VIDEO}")['data']['attributes']
    raise 'Wrong asset category, file or specification' unless video['category'] == 'CREATIVE_ASSETS' &&
      video['specId'] == SPEC && video['fileName'] == FILE
    state['assetState'] = video['state']
    unless video['state'] == 'APPROVED'
      state['status'] = %w[FAILED REJECTED ARCHIVED].include?(video['state']) ? 'NEEDS_ATTENTION' : 'AWAITING_APPLE_APPROVAL'
      state.delete('error')
      save(state)
      return
    end
    app = request("/v1/apps/#{APP}")['data']
    raise 'App identifier mismatch' unless app.dig('attributes', 'bundleId') == BUNDLE
    versions = request("/v1/apps/#{APP}/appStoreVersions?filter[platform]=IOS&limit=200")['data']
    live = versions.select { |v| %w[READY_FOR_SALE READY_FOR_DISTRIBUTION].include?(v.dig('attributes', 'appStoreState')) }
                   .max_by { |v| Gem::Version.new(v.dig('attributes', 'versionString')) }
    raise 'No live iOS version found' unless live
    version_number = live.dig('attributes', 'versionString')
    locale = request("/v1/appStoreVersions/#{live['id']}/appStoreVersionLocalizations")['data']
             .find { |l| l.dig('attributes', 'locale') == 'en-US' }
    raise 'Live English localization missing' unless locale
    endpoint = "/v1/appStoreVersionLocalizations/#{locale['id']}/placements?include=video"
    headers = request(endpoint)['data'].select { |p| p.dig('attributes', 'placementType') == 'PRODUCT_PAGE_HEADER_ASSET' }
    raise 'Unexpected multiple headers' if headers.length > 1
    placement = headers.first
    if placement && placement.dig('relationships', 'video', 'data', 'id') != VIDEO
      raise 'Another header was selected; preserving it rather than replacing it'
    end
    if check_only
      state['status'] = placement ? 'ALREADY_PLACED' : 'READY_TO_PUBLISH'
      state['targetVersion'] = version_number
      save(state)
      return
    end
    unless placement
      placement = request('/v1/appAssetLibraryPlacements', method: 'POST', body: {
        data: {type: 'appAssetLibraryPlacements',
          attributes: {placementType: 'PRODUCT_PAGE_HEADER_ASSET', placementGroup: 'DEFAULT_PROFILE'},
          relationships: {video: {data: {type: 'appAssetLibraryVideos', id: VIDEO}},
                          appStoreVersionLocalization: {data: {type: 'appStoreVersionLocalizations', id: locale['id']}}}}
      })['data']
    end
    confirmed = request(endpoint)['data'].find { |p| p['id'] == placement['id'] }
    raise 'Published placement verification failed' unless confirmed &&
      confirmed.dig('relationships', 'video', 'data', 'id') == VIDEO &&
      %w[ACTIVE PARENT_APPROVED].include?(confirmed.dig('attributes', 'state'))
    state['publishedVersion'] = version_number
    state['placementID'] = confirmed['id']
    state['placementState'] = confirmed.dig('attributes', 'state')
    state['localizationID'] = locale['id']
    state['status'] = Gem::Version.new(version_number) >= MINIMUM_RELEASE ? 'COMPLETE' : 'PUBLISHED_AWAITING_5_10_RELEASE'
    state.delete('error')
    save(state)
  rescue => error
    state ||= {}
    state['status'] = 'ERROR'
    state['error'] = error.message
    save(state)
    raise
  end
end

if $PROGRAM_NAME == __FILE__
  HeaderPublication.run(check_only: ARGV.include?('--check'))
  if ENV['N4X4_HEADER_LAUNCH_AGENT'] == '1' &&
     JSON.parse(File.read(HeaderPublication::STATE_PATH))['status'] == 'COMPLETE'
    target = "gui/#{Process.uid}/com.n4x4.chrome-ring-publication"
    system('/bin/launchctl', 'disable', target, out: File::NULL, err: File::NULL)
    Process.spawn('/bin/launchctl', 'bootout', target, out: File::NULL, err: File::NULL)
  end
end
