Pod::Spec.new do |spec|
  spec.name = 'DramaPlayer'
  spec.version = '0.1.0'
  spec.summary = 'An AVFoundation playback SDK for single videos and vertical UIKit feeds.'
  spec.description = <<-DESC
    DramaPlayer provides playback sessions, bounded prepared-player reuse, source authorization
    and cache interfaces, and optional UIKit views with seeking and playback-speed controls.
  DESC
  spec.homepage = 'https://github.com/AmiaoCat/DramaPlayer'
  spec.license = { :type => 'MIT', :file => 'LICENSE' }
  spec.author = 'AmiaoCat'
  spec.source = { :git => 'https://github.com/AmiaoCat/DramaPlayer.git', :tag => spec.version.to_s }
  spec.ios.deployment_target = '16.0'
  spec.swift_version = '5.0'
  spec.default_subspec = 'UIKit'

  spec.subspec 'Core' do |core|
    core.source_files = 'Sources/ReelsPlaybackCore/**/*.swift'
    core.frameworks = 'AVFoundation', 'QuartzCore'
  end

  spec.subspec 'UIKit' do |ui|
    ui.dependency 'DramaPlayer/Core'
    ui.source_files = 'Sources/ReelsPlaybackUIKit/**/*.swift'
    ui.framework = 'UIKit'
  end
end
