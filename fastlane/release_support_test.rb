require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require 'ostruct'
require_relative 'release_support'

class ReleaseSupportTest < Minitest::Test
  def build(**changes)
    OpenStruct.new({ id: 'build-40', app_id: N4x4Release::APP_ID,
      bundle_id: N4x4Release::BUNDLE_ID, app_version: '5.4', version: '40',
      platform: 'IOS', processing_state: 'VALID', expired: false,
      uses_non_exempt_encryption: false }.merge(changes))
  end

  def version(state, attached = build)
    OpenStruct.new(app_version_state: state, get_build: attached)
  end

  def project_settings
    (N4x4Release::SHIPPING_BUNDLES * 2).map do |bundle|
      "buildSettings = {\nMARKETING_VERSION = 5.4;\nPRODUCT_BUNDLE_IDENTIFIER = \"#{bundle}\";\n};\n"
    end.join + "buildSettings = {\nMARKETING_VERSION = 1.0;\nPRODUCT_BUNDLE_IDENTIFIER = \"Jan-van-Rensburg.N4x4Tests\";\n};\n"
  end

  def test_same_submission_is_a_no_op_but_different_build_is_rejected
    assert_equal :already_submitted, N4x4Release.disposition(version('WAITING_FOR_REVIEW'), build)
    assert_raises(RuntimeError) { N4x4Release.disposition(version('IN_REVIEW'), build(id: 'build-41')) }
    assert_raises(RuntimeError) { N4x4Release.disposition(version('READY_FOR_DISTRIBUTION', nil), build) }
  end

  def test_unfinished_review_draft_is_not_silently_replaced
    assert_raises(RuntimeError) { N4x4Release.disposition(version('READY_FOR_REVIEW'), build) }
    assert_equal :submit, N4x4Release.disposition(version('PREPARE_FOR_SUBMISSION'), build)
    assert_equal :submit, N4x4Release.disposition(nil, build)
  end

  def test_failed_expired_wrong_app_and_encrypted_builds_are_rejected
    [{ processing_state: 'FAILED' }, { processing_state: 'PROCESSING' },
     { expired: true }, { app_id: 'another-app' }, { app_version: '5.3' },
     { version: '41' }, { platform: 'MAC_OS' }, { uses_non_exempt_encryption: true }].each do |change|
      assert_raises(RuntimeError) { N4x4Release.validate_build!(build(**change), '5.4', '40') }
    end
    N4x4Release.validate_build!(build, '5.4', '40')
  end

  def test_partial_version_bump_and_empty_notes_are_rejected
    Dir.mktmpdir do |root|
      FileUtils.mkdir_p(File.join(root, 'N4x4.xcodeproj'))
      FileUtils.mkdir_p(File.join(root, 'AppStore'))
      project = File.join(root, 'N4x4.xcodeproj/project.pbxproj')
      notes = File.join(root, 'AppStore/release-notes-5.4.txt')
      File.write(project, project_settings)
      File.write(notes, 'Larger countdown.')
      assert_equal ['5.4', '40', 'Larger countdown.'], N4x4Release.inputs(root, '5.4', '40')
      assert_raises(RuntimeError) { N4x4Release.inputs(root, '5.4', 'latest') }
      File.write(project, project_settings.sub('MARKETING_VERSION = 5.4;', 'MARKETING_VERSION = 5.3;'))
      assert_raises(RuntimeError) { N4x4Release.inputs(root, '5.4', '40') }
      File.write(project, project_settings)
      File.write(notes, " \n")
      assert_raises(RuntimeError) { N4x4Release.inputs(root, '5.4', '40') }
    end
  end
end
