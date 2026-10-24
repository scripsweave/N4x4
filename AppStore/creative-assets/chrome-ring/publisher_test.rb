require 'minitest/autorun'
require_relative 'publish-approved'

class HeaderPublisherTest < Minitest::Test
  def setup
    @calls = []
    @saved = nil
    @asset_state = 'APPROVED'
    @version = '5.10'
    @headers = []
    test = self
    @originals = %i[request save load_state].to_h { |name| [name, HeaderPublication.method(name)] }
    HeaderPublication.define_singleton_method(:load_state) { {} }
    HeaderPublication.define_singleton_method(:save) { |state| test.capture(state) }
    HeaderPublication.define_singleton_method(:request) do |path, method: 'GET', body: nil|
      test.response(path, method, body)
    end
  end

  def teardown
    @originals.each { |name, method| HeaderPublication.define_singleton_method(name, method) }
  end

  def capture(state)
    @saved = Marshal.load(Marshal.dump(state))
  end

  def placement(video = HeaderPublication::VIDEO)
    {'id' => 'header-placement', 'attributes' => {'placementType' => 'PRODUCT_PAGE_HEADER_ASSET', 'state' => 'ACTIVE'},
     'relationships' => {'video' => {'data' => {'id' => video}}}}
  end

  def response(path, method, body)
    @calls << [path, method, body]
    data = case path
    when "/v1/appAssetLibraryVideos/#{HeaderPublication::VIDEO}"
      {'attributes' => {'category' => 'CREATIVE_ASSETS', 'specId' => HeaderPublication::SPEC,
                        'fileName' => HeaderPublication::FILE, 'state' => @asset_state}}
    when "/v1/apps/#{HeaderPublication::APP}"
      {'attributes' => {'bundleId' => HeaderPublication::BUNDLE}}
    when /appStoreVersions\?/
      [{'id' => 'live-version', 'attributes' => {'versionString' => @version, 'appStoreState' => 'READY_FOR_SALE'}},
       {'id' => 'pending-version', 'attributes' => {'versionString' => '5.11', 'appStoreState' => 'WAITING_FOR_REVIEW'}}]
    when '/v1/appStoreVersions/live-version/appStoreVersionLocalizations'
      [{'id' => 'live-locale', 'attributes' => {'locale' => 'en-US'}}]
    when '/v1/appStoreVersionLocalizations/live-locale/placements?include=video'
      @headers
    when '/v1/appAssetLibraryPlacements'
      raise 'Unexpected mutation' unless method == 'POST'
      raise 'Wrong localization' unless body.dig(:data, :relationships, :appStoreVersionLocalization, :data, :id) == 'live-locale'
      @headers = [placement]
      @headers.first
    else
      raise "Unexpected request #{path}"
    end
    {'data' => data}
  end

  def test_unapproved_video_never_writes_to_apple
    @asset_state = 'WAITING_FOR_REVIEW'
    HeaderPublication.run
    assert_equal 'AWAITING_APPLE_APPROVAL', @saved['status']
    assert @calls.all? { |_, method, _| method == 'GET' }
    assert_equal 1, @calls.length
  end

  def test_another_selected_header_is_preserved
    @headers = [placement('a-different-user-selected-video')]
    assert_raises(RuntimeError) { HeaderPublication.run }
    assert @calls.all? { |_, method, _| method == 'GET' }
    assert_equal 'ERROR', @saved['status']
  end

  def test_approved_header_is_idempotent_and_pending_version_is_untouched
    @headers = [placement]
    HeaderPublication.run
    assert_equal 'COMPLETE', @saved['status']
    assert_equal '5.10', @saved['publishedVersion']
    assert @calls.all? { |_, method, _| method == 'GET' }
    refute @calls.any? { |path, _, _| path.include?('pending-version') }
  end

  def test_current_live_version_is_published_then_waits_for_5_10
    @version = '5.7'
    HeaderPublication.run
    assert_equal 'PUBLISHED_AWAITING_5_10_RELEASE', @saved['status']
    assert_equal '5.7', @saved['publishedVersion']
    assert_equal 1, @calls.count { |_, method, _| method == 'POST' }
    refute @calls.any? { |path, _, _| path.include?('pending-version') }
  end
end
