# Pure input/state checks shared by the lanes and their regression tests.
module N4x4Release
  APP_ID = '6686407796'.freeze
  BUNDLE_ID = 'Jan-van-Rensburg.N4x4'.freeze
  SHIPPING_BUNDLES = [BUNDLE_ID, "#{BUNDLE_ID}.watchkitapp", "#{BUNDLE_ID}.LiveActivity"].freeze
  SUBMITTED_STATES = %w[WAITING_FOR_REVIEW IN_REVIEW PENDING_APPLE_RELEASE
                        PENDING_DEVELOPER_RELEASE PROCESSING_FOR_DISTRIBUTION
                        READY_FOR_DISTRIBUTION READY_FOR_SALE].freeze
  EDITABLE_STATES = %w[PREPARE_FOR_SUBMISSION DEVELOPER_REJECTED REJECTED METADATA_REJECTED INVALID_BINARY].freeze
  ACTIVE_STATES = (EDITABLE_STATES + %w[READY_FOR_REVIEW WAITING_FOR_REVIEW IN_REVIEW
                                      PENDING_APPLE_RELEASE PENDING_DEVELOPER_RELEASE
                                      PROCESSING_FOR_DISTRIBUTION WAITING_FOR_EXPORT_COMPLIANCE]).freeze

  def self.inputs(root, version, number)
    version, number = version.to_s, number.to_s
    raise 'Specify a numeric version, e.g. 5.5.' unless version.match?(/\A(?:0|[1-9]\d*)(?:\.(?:0|[1-9]\d*)){1,2}\z/)
    raise 'Specify an exact numeric build number; latest is not accepted.' unless number.match?(/\A[1-9]\d*\z/)
    settings = File.read(File.join(root, 'N4x4.xcodeproj/project.pbxproj')).scan(/buildSettings = \{(.*?)^\s*\};/m).flatten
    valid = SHIPPING_BUNDLES.all? do |bundle|
      configs = settings.select { |s| s[/PRODUCT_BUNDLE_IDENTIFIER = "?([^";]+)"?;/, 1] == bundle }
      configs.length == 2 && configs.all? { |s| s[/MARKETING_VERSION = ([^;]+);/, 1] == version }
    end
    raise 'All six shipping configurations must match the requested version.' unless valid
    notes = File.read(File.join(root, "AppStore/release-notes-#{version}.txt")).strip
    raise 'Release notes must contain 1–4000 characters.' unless (1..4000).cover?(notes.length)
    [version, number, notes]
  end

  def self.validate_build!(build, version, number)
    raise 'Apple returned a different app, version, build or platform.' unless build.app_id == APP_ID && build.bundle_id == BUNDLE_ID && build.app_version == version && build.version == number && build.platform == 'IOS'
    raise "Build cannot be submitted: #{build.processing_state}." unless build.processing_state == 'VALID'
    raise 'Build is expired.' if build.expired
    raise 'This build declares non-exempt encryption; review export compliance before submitting.' if build.uses_non_exempt_encryption == true
  end

  def self.state(version)
    version.app_version_state || version.app_store_state
  end

  def self.disposition(version, build, expected_number: nil)
    return :submit unless version
    current = state(version)
    if SUBMITTED_STATES.include?(current)
      attached = version.get_build
      matches = attached && (build ? attached.id == build.id : attached.version == expected_number)
      raise 'This version is already submitted with a different build. It will not be replaced.' unless matches
      return :already_submitted
    end
    raise "Version is #{current}; resolve its current review draft/status in App Store Connect." unless EDITABLE_STATES.include?(current)
    :submit
  end
end
