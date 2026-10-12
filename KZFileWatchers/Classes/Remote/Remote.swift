//
//  Remote.swift
//  KZFileWatchers
//
//  Created by Krzysztof Zabłocki on 05/08/16.
//

import Foundation

public extension FileWatcher {
    /// Main-actor-owned remote watcher with conditional HTTP requests.
    @MainActor
    final class Remote: FileWatcherProtocol {
        internal static var sessionConfiguration: URLSessionConfiguration {
            let configuration = URLSessionConfiguration.default
            configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            return configuration
        }

        let url: URL
        let refreshInterval: TimeInterval
        private let configuration: URLSessionConfiguration
        private var session: SessionLifetime?
        private var callback: UpdateClosure?
        private var pollingTask: Task<Void, Never>?
        private var requestTask: Task<Void, Never>?
        private var lastModified: String?
        private var lastETag: String?
        private var previousContent: Data?
        private var generation = 0

        public init(url: URL, refreshInterval: TimeInterval = 1,
                    sessionConfiguration: URLSessionConfiguration? = nil) {
            self.url = url
            self.refreshInterval = refreshInterval
            self.configuration = sessionConfiguration ?? Remote.sessionConfiguration
        }

        public func start(closure: @escaping UpdateClosure) throws {
            guard callback == nil else { throw Error.alreadyStarted }
            guard refreshInterval.isFinite, refreshInterval > 0, refreshInterval <= 1_000_000_000,
                  ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
                throw Error.failedToStart(reason: "An HTTP(S) URL and an interval between 0 and 1,000,000,000 seconds are required")
            }
            callback = closure
            session = SessionLifetime(configuration: configuration)
            lastModified = nil
            lastETag = nil
            previousContent = nil
            try refresh()
            pollingTask = Task { @MainActor [weak self] in
                while !Task.isCancelled {
                    guard let interval = self?.refreshInterval else { return }
                    do {
                        try await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                    } catch is CancellationError {
                        return
                    } catch {
                        self?.callback?(.failed(error: .refreshFailed(reason: error.localizedDescription)))
                        return
                    }
                    guard let self, self.callback != nil else { return }
                    do {
                        try self.refresh()
                    } catch {
                        self.callback?(.failed(error: .refreshFailed(reason: error.localizedDescription)))
                    }
                }
            }
        }

        public func stop() throws {
            guard callback != nil else { return }
            generation += 1
            pollingTask?.cancel()
            requestTask?.cancel()
            pollingTask = nil
            requestTask = nil
            session = nil
            callback = nil
        }

        deinit {
            pollingTask?.cancel()
            requestTask?.cancel()
        }

        /// Trigger a request unless one is already in flight.
        @objc public func refresh() throws {
            guard let session, callback != nil else { throw Error.notStarted }
            guard requestTask == nil else { return }
            var request = URLRequest(url: url)
            request.setValue(lastModified, forHTTPHeaderField: "If-Modified-Since")
            request.setValue(lastETag, forHTTPHeaderField: "If-None-Match")
            let token = generation
            requestTask = Task { @MainActor [weak self] in
                guard !Task.isCancelled else { return }
                do {
                    let (data, response) = try await session.value.data(for: request)
                    guard let self, self.generation == token, let callback = self.callback else { return }
                    self.requestTask = nil
                    guard let response = response as? HTTPURLResponse else {
                        callback(.failed(error: .refreshFailed(reason: "Expected an HTTP response")))
                        return
                    }
                    if response.statusCode == 304 {
                        callback(.noChanges)
                        return
                    }
                    guard (200...299).contains(response.statusCode) else {
                        callback(.failed(error: .refreshFailed(reason: "HTTP \(response.statusCode)")))
                        return
                    }
                    self.lastModified = response.value(forHTTPHeaderField: "Last-Modified")
                    self.lastETag = response.value(forHTTPHeaderField: "ETag")
                    let result: RefreshResult = data == self.previousContent ? .noChanges : .updated(data: data)
                    self.previousContent = data
                    callback(result)
                } catch {
                    guard let self, self.generation == token, let callback = self.callback else { return }
                    self.requestTask = nil
                    guard !Task.isCancelled else { return }
                    callback(.failed(error: .refreshFailed(reason: error.localizedDescription)))
                }
            }

        }
    }
}

// Pending request tasks retain their session until cancellation completes, so
// stop/deinit cannot invalidate it while data(for:) is still creating a task.
private final class SessionLifetime: Sendable {
    let value: URLSession

    init(configuration: URLSessionConfiguration) {
        value = URLSession(configuration: configuration)
    }

    deinit {
        value.invalidateAndCancel()
    }
}
