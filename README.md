# KZFileWatchers

## Swift 6 fork

**Swift language mode: 6 | Minimum tools/compiler: 6.2 | Platforms:
macOS 12+, iOS 15+, tvOS 15+**

This fork's `modernization/swift6` branch compiles **all Swift targets in Swift 6
language mode**, including the optional Objective-C adapters. It requires Swift
tools/compiler **6.2+**, macOS 12+, iOS 15+ or
tvOS 15+. There are no third-party package dependencies. This is a breaking API
migration, not just compilation with a newer compiler.

- Construct, start, refresh and stop watchers on `@MainActor`.
- Callbacks are `@Sendable`. Remote callbacks run on the main actor; local
  callbacks retain their configurable delivery queue. Hop to `@MainActor`
  before touching UI or mutable UI-owned state.
- Handle `.updated(data:)`, `.noChanges` and the new `.failed(error:)` result.
  HTTP/network/read/reopen failures are reported instead of silently ignored.
- Remote requests are serialized, support ETag and Last-Modified validators,
  and compare response bodies even when cache validators are absent.
- Local atomic-save replacements are reopened; deleted files are retried at
  the refresh interval. Stop or release the watcher to cancel retries.
- Stop cancels pending work and suppresses stale requests after restart. A
  local callback already submitted to a custom delivery queue can still finish.
- Intervals must be finite, greater than zero and at most 1,000,000,000 seconds;
  intervals are not silently capped.

```swift
.package(url: "https://github.com/tomasszabo/KZFileWatchers.git",
         branch: "master")
```

The migration is currently on `modernization/swift6`. The installation examples
intentionally use **`master` for after the PR is merged**. Until then, select
`modernization/swift6` to try Swift 6. Pin a reviewed commit for reproducible
builds; these examples do not imply the PR is already merged.

Add the `KZFileWatchers` product. For Objective-C use, add
`KZFileWatchersObjC`, import that module and call adapters from the main thread.
Delegates may implement the optional `refreshDidFail(from:error:)` method;
failures are also logged. Adapter delegates are always called on the main actor,
including when a local watcher has a custom callback queue.

For CocoaPods, use the fork explicitly; the public registry still supplies the
older upstream release:

```ruby
pod 'KZFileWatchers', :git => 'https://github.com/tomasszabo/KZFileWatchers.git',
                    :branch => 'master'
```

The fork podspec includes the Objective-C wrappers in the same module and sets
Swift 6 mode. Use a Swift 6.2+ compiler, even though the language setting is `6.0`.
Legacy examples and their vendored Pods are historical and are not the supported
Swift 6 build surface. The installation instructions below describe upstream.

### Validation

```sh
swift test
swift build -c release
sh Scripts/test-package.sh test
DESTINATION='generic/platform=tvOS Simulator' \
    sh Scripts/test-package.sh -configuration Release build
```

Override `DESTINATION` for an available simulator. Tests use temporary files and
an in-process HTTP protocol stub, with no external services or signing.
Cleanup uses Sendable resource owners rather than `isolated deinit`, avoiding
the older simulator/runtime crash reported in
[Swift issue #85663](https://github.com/swiftlang/swift/issues/85663). The local
dispatch-source owner has a narrowly scoped unchecked Sendable conformance:
its handle is immutable and Dispatch cancellation is thread-safe.
Validated with Xcode 27 / Swift 6.4: all 16 tests pass on macOS and the iOS
simulator, macOS/iOS/tvOS Release builds pass, and unsigned iOS CocoaPods lint
passes. No concurrency warnings occur in library sources. Older OS runtime
execution and tvOS runtime tests have not been performed.

![Demo GIF](Images/Demo.gif)


[![CI Status](http://img.shields.io/travis/krzysztofzablocki/KZFileWatchers.svg?style=flat)](https://travis-ci.org/krzysztofzablocki/KZFileWatchers)
[![Version](https://img.shields.io/cocoapods/v/KZFileWatchers.svg?style=flat)](http://cocoapods.org/pods/KZFileWatchers)
[![License](https://img.shields.io/cocoapods/l/KZFileWatchers.svg?style=flat)](http://cocoapods.org/pods/KZFileWatchers)
[![Platform](https://img.shields.io/cocoapods/p/KZFileWatchers.svg?style=flat)](http://cocoapods.org/pods/KZFileWatchers)

Wouldn't it be great if we could adjust feeds and configurations of our native apps without having to sit back to Xcode, change code, recompile and navigate back to screen we were at?

One of the basis of building tools that allow us to do just that is the way we observe for data changes, this micro-framework provides you File observers for Local and Remote assets.

This framework provides:

- `FileWatcher.Local` useful for observing local file changes, it can also be used to breach Sandbox env for debug simulator builds and e.g. observe file on the developer desktop (like the demo app does).

- `FileWatcher.Remote` can be used to observe files on the web, it supports both `Etag` headers and `Last-Modified-Date` so you can just put file on Dropbox or real ftp server.

It also supports usage from Objective-C projects. For this, you should consider these following steps:

1. Add `$(TOOLCHAIN_DIR)/usr/lib/swift/$(PLATFORM_NAME)` into your projects **Library Search Paths** in **Build Setting** section.

2. Import swift-header by adding `@import KZFileWatchers;` into any `.m` file, where you want to use FileWatchers.

3. Use provided classes for set up file observing like this:
```objectivec
self.fileWatcher = [[LocalFileWatcher alloc] initWithPath:path];
self.fileWatcher.delegate = self;
[self.fileWatcher startWithError:nil];
```
4. Implement `FileWatcherDelegate` in your class for handling file refreshing events. For example:
```objectivec
- (void)refreshDidOccurFrom:(id<FileWatcherProtocol>)fileWatcher type:(enum RefreshResult)type data:(NSData *)data
{
    self.textLabel.text = [[NSString alloc] initWithData:data encoding:kCFStringEncodingUTF8];
}
```

## Installation

KZFileWatchers is available through [CocoaPods](http://cocoapods.org) and [Swift Package Manager](http://github.com/apple/swift-package-manager).

### CocoaPods

In order to install KZFileWatchers by using CocoaPods, simply add the following line to your Podfile:

```ruby
pod "KZFileWatchers"
```

Last version to support Swift 2.3 is `0.1.2`
Last version to support Swift 3.0 is `1.0.4`

### Swift Package Manager

Installing KZFileWatchers over SwiftPM is only supported since version 1.0.1. You just need to add it as a dependency to your Package.swift manifest:

```swift
import PackageDescription

let package = Package(
    name: "YourProject",
    dependencies: [
        .package(url: "https://github.com/krzysztofzablocki/KZFileWatchers.git", from: "1.1.0"),
        // other dependencies
    ],
    targets: [
        .executableTarget(name: "YourApp", dependencies: [
            .product(name: "KZFileWatchers", package: "KZFileWatchers"),
            // other dependencies
        ]
    ]
)
```

## Author

Krzysztof Zabłocki, krzysztof.zablocki@pixle.pl

## Contributing

Contributions to KZFileWatchers are welcomed and encouraged! Please see the [Contributing guide](https://github.com/krzysztofzablocki/KZFileWatchers/blob/master/CONTRIBUTING.md).

[A list of contributors is available through GitHub.](https://github.com/krzysztofzablocki/KZFileWatchers/graphs/contributors)

To give clarity of what is expected of our members, KZFileWatchers has adopted the code of conduct defined by the Contributor Covenant. This document is used across many open source communities. For more, see the [Code of Conduct](https://github.com/krzysztofzablocki/KZFileWatchers/blob/master/CODE_OF_CONDUCT.md).

## License

KZFileWatchers is available under the MIT license. See [LICENSE](https://github.com/krzysztofzablocki/KZFileWatchers/blob/master/LICENSE) for more information.
