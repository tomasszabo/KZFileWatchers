#
# Be sure to run `pod lib lint KZFileWatchers.podspec' to ensure this is a
# valid spec before submitting.
#
# Any lines starting with a # are optional, but their use is encouraged
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html
#

Pod::Spec.new do |s|
  s.name             = 'KZFileWatchers'
  s.version          = '2.0.0'
  s.summary          = 'A micro-framework for observing file changes, both local and remote. Helpful in building developer tools.'

  s.description      = <<-DESC
A micro-framework for observing file changes, both local and remote. Helpful in building developer tools. Supports both ETag and Last-Modified-Date so you can use it with most available hosting options, e.g. Dropbox or AWS.
                       DESC

  s.homepage         = 'https://github.com/tomasszabo/KZFileWatchers'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'Krzysztof Zabłocki' => 'krzysztof.zablocki@pixle.pl' }
  s.source           = { :git => 'https://github.com/tomasszabo/KZFileWatchers.git', :branch => 'modernization/swift6' }
  s.social_media_url = 'https://twitter.com/merowing_'
  s.swift_version    = '6.0'

  s.ios.deployment_target = '15.0'
  s.tvos.deployment_target = '15.0'
  s.osx.deployment_target = '12.0'

  s.source_files = 'KZFileWatchers/Classes/**/*', 'ObjcWrappers/*.swift'
end
