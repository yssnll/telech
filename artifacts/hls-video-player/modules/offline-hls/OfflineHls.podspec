Pod::Spec.new do |s|
  s.name = 'OfflineHls'
  s.version = '1.0.0'
  s.summary = 'Native background HLS downloads for iOS.'
  s.description = 'Downloads HLS assets with AVAssetDownloadURLSession for offline playback.'
  s.license = { type: 'MIT' }
  s.author = { 'Telech' => 'Telech' }
  s.platform = :ios, '15.1'
  s.source = { git: 'https://github.com/expo/expo.git', tag: 'sdk-54.0.0' }
  s.static_framework = true
  s.swift_version = '5.9'
  s.source_files = 'ios/**/*.swift'
  s.dependency 'ExpoModulesCore'
end