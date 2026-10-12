import Foundation
import XCTest
@testable import KZFileWatchers

@MainActor
final class WatcherTests: XCTestCase {
    private func file() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("watched.txt")
    }

    func testLocalInitialContentAndNoChanges() async throws {
        let url = try file()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try Data("first".utf8).write(to: url)
        let initial = expectation(description: "Initial content")
        let unchanged = expectation(description: "Unchanged content")
        let watcher = FileWatcher.Local(path: url.path)
        try watcher.start { result in
            switch result {
            case .updated(let data): XCTAssertEqual(data, Data("first".utf8)); initial.fulfill()
            case .noChanges: unchanged.fulfill()
            case .failed(let error): XCTFail("\(error)")
            }
        }
        await fulfillment(of: [initial], timeout: 3)
        watcher.refresh()
        await fulfillment(of: [unchanged], timeout: 3)
        try watcher.stop()
        XCTAssertThrowsError(try watcher.stop())
    }

    func testLocalAtomicReplacement() async throws {
        let url = try file()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try Data("first".utf8).write(to: url)
        let initial = expectation(description: "Initial")
        let replacement = expectation(description: "Atomic replacement")
        let watcher = FileWatcher.Local(path: url.path, refreshInterval: 0.02)
        try watcher.start { result in
            if case .updated(let data) = result {
                if data == Data("first".utf8) { initial.fulfill() }
                if data == Data("second".utf8) { replacement.fulfill() }
            }
        }
        await fulfillment(of: [initial], timeout: 3)
        try Data("second".utf8).write(to: url, options: .atomic)
        await fulfillment(of: [replacement], timeout: 3)
        try watcher.stop()
    }

    func testLocalDeletedFileRecoversAfterRecreation() async throws {
        let url = try file()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try Data("first".utf8).write(to: url)
        let initial = expectation(description: "Initial")
        let failure = expectation(description: "Missing file")
        failure.assertForOverFulfill = false
        let recreated = expectation(description: "Recreated")
        let watcher = FileWatcher.Local(path: url.path, refreshInterval: 0.02)
        try watcher.start {
            switch $0 {
            case .updated(let data):
                if data == Data("first".utf8) { initial.fulfill() }
                else { XCTAssertEqual(data, Data("second".utf8)); recreated.fulfill() }
            case .failed: failure.fulfill()
            case .noChanges: break
            }
        }
        await fulfillment(of: [initial], timeout: 3)
        try FileManager.default.removeItem(at: url)
        await fulfillment(of: [failure], timeout: 3)
        try Data("second".utf8).write(to: url)
        await fulfillment(of: [recreated], timeout: 3)
        try watcher.stop()
    }

    func testLocalCustomQueueDelivery() async throws {
        let url = try file()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try Data("first".utf8).write(to: url)
        let delivered = expectation(description: "Custom queue")
        let watcher = FileWatcher.Local(path: url.path, queue: DispatchQueue(label: "watcher.test"))
        try watcher.start {
            XCTAssertFalse(Thread.isMainThread)
            if case .updated = $0 { delivered.fulfill() }
        }
        await fulfillment(of: [delivered], timeout: 3)
        try watcher.stop()
    }

    func testRemoteConditionalLastModifiedRequest() async throws {
        let watcher = remote("modified")
        let initial = expectation(description: "Last-Modified body")
        let notModified = expectation(description: "Conditional date request")
        try watcher.start {
            switch $0 {
            case .updated: initial.fulfill()
            case .noChanges: notModified.fulfill()
            case .failed(let error): XCTFail("\(error)")
            }
        }
        await fulfillment(of: [initial], timeout: 3)
        try watcher.refresh()
        await fulfillment(of: [notModified], timeout: 3)
        try watcher.stop()
    }

    func testRemoteChangedBodyAndCoalescedRequests() async throws {
        let watcher = remote("changing")
        let initial = expectation(description: "Initial body")
        let changed = expectation(description: "Changed body")
        try watcher.start {
            switch $0 {
            case .updated(let data):
                if data == Data("body".utf8) { initial.fulfill() }
                else { XCTAssertEqual(data, Data("changed".utf8)); changed.fulfill() }
            case .noChanges: XCTFail("Request should have been coalesced")
            case .failed(let error): XCTFail("\(error)")
            }
        }
        try watcher.refresh()
        try watcher.refresh()
        await fulfillment(of: [initial], timeout: 3)
        try watcher.refresh()
        await fulfillment(of: [changed], timeout: 3)
        try watcher.stop()
    }

    func testRemoteNetworkFailure() async throws {
        let watcher = remote("network")
        let failure = expectation(description: "Network failure")
        try watcher.start {
            if case .failed = $0 { failure.fulfill() }
            else { XCTFail("Network error must be reported") }
        }
        await fulfillment(of: [failure], timeout: 3)
        try watcher.stop()
    }

    func testRemoteStopAndRestartSuppressesOldRequest() async throws {
        let watcher = remote("plain")
        let old = expectation(description: "Old request")
        old.isInverted = true
        let restarted = expectation(description: "Restarted request")
        try watcher.start { _ in old.fulfill() }
        try watcher.stop()
        try watcher.start { if case .updated = $0 { restarted.fulfill() } }
        await fulfillment(of: [restarted, old], timeout: 0.2)
        try watcher.stop()
    }

    func testWatchersCanBeReleasedWithoutExplicitStop() async throws {
        let url = try file()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try Data("first".utf8).write(to: url)
        weak var local: FileWatcher.Local?
        weak var remoteWatcher: FileWatcher.Remote?
        do {
            let watcher = FileWatcher.Local(path: url.path)
            local = watcher
            try watcher.start { _ in }
            let other = remote("plain")
            remoteWatcher = other
            try other.start { _ in }
        }
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertNil(local)
        XCTAssertNil(remoteWatcher)
    }

    func testLocalInvalidLifecycleAndInterval() throws {
        let watcher = FileWatcher.Local(path: "/nonexistent/\(UUID())")
        XCTAssertThrowsError(try watcher.start { _ in })
        XCTAssertThrowsError(try watcher.stop())
        let invalid = FileWatcher.Local(path: "", refreshInterval: .nan)
        XCTAssertThrowsError(try invalid.start { _ in })
    }

    func testLocalRestartResendsInitialContent() async throws {
        let url = try file()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try Data("first".utf8).write(to: url)
        let first = expectation(description: "First")
        let second = expectation(description: "Restart")
        let watcher = FileWatcher.Local(path: url.path)
        try watcher.start { if case .updated = $0 { first.fulfill() } }
        XCTAssertThrowsError(try watcher.start { _ in })
        await fulfillment(of: [first], timeout: 3)
        try watcher.stop()
        try watcher.start { if case .updated = $0 { second.fulfill() } }
        await fulfillment(of: [second], timeout: 3)
        try watcher.stop()
    }

    private func remote(_ path: String, interval: TimeInterval = 3600) -> FileWatcher.Remote {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubProtocol.self]
        return FileWatcher.Remote(url: URL(string: "https://watcher.invalid/\(path)")!,
                                  refreshInterval: interval, sessionConfiguration: configuration)
    }

    func testRemoteContentWithoutValidatorsAndUnchangedBody() async throws {
        let watcher = remote("plain")
        let initial = expectation(description: "Body without cache headers")
        let unchanged = expectation(description: "Same body")
        try watcher.start { result in
            XCTAssertTrue(Thread.isMainThread)
            switch result {
            case .updated(let data): XCTAssertEqual(data, Data("body".utf8)); initial.fulfill()
            case .noChanges: unchanged.fulfill()
            case .failed(let error): XCTFail("\(error)")
            }
        }
        await fulfillment(of: [initial], timeout: 3)
        try watcher.refresh()
        await fulfillment(of: [unchanged], timeout: 3)
        try watcher.stop()
        XCTAssertThrowsError(try watcher.refresh())
    }

    func testRemoteConditionalETagRequest() async throws {
        let watcher = remote("etag")
        let initial = expectation(description: "ETag body")
        let notModified = expectation(description: "Conditional request")
        try watcher.start { result in
            switch result {
            case .updated: initial.fulfill()
            case .noChanges: notModified.fulfill()
            case .failed(let error): XCTFail("\(error)")
            }
        }
        await fulfillment(of: [initial], timeout: 3)
        try watcher.refresh()
        await fulfillment(of: [notModified], timeout: 3)
        try watcher.stop()
    }

    func testRemoteHTTPFailureAndRestart() async throws {
        let watcher = remote("failure")
        let failure = expectation(description: "HTTP failure")
        try watcher.start { result in
            if case .failed(let error) = result {
                XCTAssertEqual(error, .refreshFailed(reason: "HTTP 503"))
                failure.fulfill()
            } else {
                XCTFail("HTTP failure must not look successful")
            }
        }
        XCTAssertThrowsError(try watcher.start { _ in })
        await fulfillment(of: [failure], timeout: 3)
        try watcher.stop()
        try watcher.stop()
    }

    func testRemoteInvalidIntervalAndURL() {
        XCTAssertThrowsError(try remote("plain", interval: 0).start { _ in })
        XCTAssertThrowsError(try remote("plain", interval: .infinity).start { _ in })
        XCTAssertThrowsError(try remote("plain", interval: 1_000_000_001).start { _ in })
        let maximum = remote("plain", interval: 1_000_000_000)
        XCTAssertNoThrow(try maximum.start { _ in })
        XCTAssertNoThrow(try maximum.stop())
        let watcher = FileWatcher.Remote(url: URL(fileURLWithPath: "/tmp/file"))
        XCTAssertThrowsError(try watcher.start { _ in })
    }

    func testStopSuppressesQueuedLocalDelivery() async throws {
        let url = try file()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try Data("first".utf8).write(to: url)
        let callback = expectation(description: "No callback after immediate stop")
        callback.isInverted = true
        let watcher = FileWatcher.Local(path: url.path)
        try watcher.start { _ in callback.fulfill() }
        try watcher.stop()
        await fulfillment(of: [callback], timeout: 0.1)
    }
}

// URLProtocol already has unchecked Sendable conformance; this test subclass
// adds no mutable state and responds deterministically from each request.
private final class StubProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let path = request.url!.lastPathComponent
        if path == "network" {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
            return
        }
        let date = "Wed, 21 Oct 2015 07:28:00 GMT"
        let status = path == "failure" ? 503 :
            ((path == "etag" && request.value(forHTTPHeaderField: "If-None-Match") == "\"v1\"") ||
             (path == "modified" && request.value(forHTTPHeaderField: "If-Modified-Since") == date) ? 304 : 200)
        let headers = path == "etag" || path == "changing" ? ["ETag": "\"v1\""] :
            (path == "modified" ? ["Last-Modified": date] : [:])
        let response = HTTPURLResponse(url: request.url!, statusCode: status,
                                       httpVersion: "HTTP/1.1", headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        let body = path == "changing" && request.value(forHTTPHeaderField: "If-None-Match") != nil ? "changed" : "body"
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
