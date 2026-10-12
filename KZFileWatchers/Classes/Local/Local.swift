//
//  Local.swift
//  KZFileWatchers
//
//  Created by Krzysztof Zabłocki on 05/08/16.
//

import Foundation

public extension FileWatcher {
    /// Main-actor-owned local watcher with content diffing and coalesced file events.
    @MainActor
    final class Local: FileWatcherProtocol {
        private let path: String
        private let refreshInterval: TimeInterval
        private let queue: DispatchQueue
        private var source: DispatchSourceLifetime?
        private var callback: UpdateClosure?
        private var reloadTask: Task<Void, Never>?
        private var previousContent: Data?
        private var generation = 0

        /// `queue` controls callback delivery, not watcher state ownership.
        public init(path: String, refreshInterval: TimeInterval = 1 / 60,
                    queue: DispatchQueue = .main) {
            self.path = path
            self.refreshInterval = refreshInterval
            self.queue = queue
        }

        public func start(closure: @escaping UpdateClosure) throws {
            guard callback == nil else { throw Error.alreadyStarted }
            guard refreshInterval.isFinite, refreshInterval > 0, refreshInterval <= 1_000_000_000 else {
                throw Error.failedToStart(reason: "Refresh interval must be positive and at most 1,000,000,000 seconds")
            }
            try observe()
            callback = closure
            previousContent = nil
            refresh()
        }

        public func stop() throws {
            guard callback != nil else { throw Error.alreadyStopped }
            generation += 1
            reloadTask?.cancel()
            reloadTask = nil
            source?.cancel()
            source = nil
            callback = nil
        }

        deinit {
            reloadTask?.cancel()
            source?.cancel()
        }

        private func observe() throws {
            let handle = open(path, O_EVTONLY)
            guard handle >= 0 else {
                throw Error.failedToStart(reason: "Cannot open \(path): \(String(cString: strerror(errno)))")
            }
            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: handle,
                eventMask: [.delete, .write, .extend, .attrib, .link, .rename, .revoke],
                queue: .main
            )
            let token = generation
            source.setEventHandler { [weak self] in
                Task { @MainActor [weak self] in
                    guard let self, self.generation == token, self.callback != nil else { return }
                    self.scheduleReload()
                }
            }
            source.setCancelHandler { close(handle) }
            source.resume()
            self.source = DispatchSourceLifetime(source)
        }

        // Dispatch source cancellation is thread-safe. Keeping the immutable handle
        // in a Sendable owner avoids executor-hopping deinit runtime bugs on older OSes.
        private final class DispatchSourceLifetime: @unchecked Sendable {
            private let source: any DispatchSourceFileSystemObject

            init(_ source: any DispatchSourceFileSystemObject) {
                self.source = source
            }

            func cancel() {
                source.cancel()
            }

            deinit {
                source.cancel()
            }
        }

        private func scheduleReload() {
            reloadTask?.cancel()
            let token = generation
            let interval = refreshInterval
            reloadTask = Task { @MainActor [weak self] in
                do {
                    try await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                } catch is CancellationError {
                    return
                } catch {
                    self?.deliver(.failed(error: .refreshFailed(reason: error.localizedDescription)))
                    return
                }
                guard let self else { return }
                guard self.generation == token, self.callback != nil else { return }
                // Editors commonly replace the inode during an atomic save.
                self.source?.cancel()
                self.source = nil
                do {
                    try self.observe()
                    self.refresh()
                } catch {
                    self.deliver(.failed(error: .refreshFailed(reason: error.localizedDescription)))
                    self.scheduleReload()
                }
            }
        }

        /// Read immediately; a stopped watcher does not emit callbacks.
        public func refresh() {
            guard callback != nil else { return }
            do {
                let content = try Data(contentsOf: URL(fileURLWithPath: path), options: .uncached)
                let result: RefreshResult = content == previousContent ? .noChanges : .updated(data: content)
                previousContent = content
                deliver(result)
            } catch {
                deliver(.failed(error: .refreshFailed(reason: error.localizedDescription)))
            }
        }

        private func deliver(_ result: RefreshResult) {
            let token = generation
            // Recheck lifecycle before handing a callback to its delivery queue.
            Task { @MainActor [weak self] in
                guard let self, self.generation == token, let callback = self.callback else { return }
                self.queue.async { callback(result) }
            }
        }
    }
}

public extension FileWatcher.Local {
    #if targetEnvironment(simulator)
    nonisolated class func simulatorOwnerUsername() -> String {
        let components = NSHomeDirectory().components(separatedBy: "/")
        guard components.count > 2 else { return NSUserName() }
        return components[2]
    }
    #endif
}
