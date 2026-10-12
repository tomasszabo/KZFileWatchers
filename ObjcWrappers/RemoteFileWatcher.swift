//
//  RemoteFileWatcher.swift
//  KZFileWatchers
//
//  Created by Andrey Morozov on 18/12/2018.
//

import Foundation
#if SWIFT_PACKAGE
import KZFileWatchers
#endif

/**
Watcher for remote files, it supports both ETag and Last-Modified HTTP header tags.
*/
@MainActor
@objc
public final class RemoteFileWatcher: NSObject {
	
	/// Original remote FileWatcher, that does all work.
	private let remoteWatcher: FileWatcher.Remote
	
	public weak var delegate: FileWatcherOutput?
	
	/**
	Creates a new watcher using given URL and refreshInterval.
	
	- parameter url:             URL to observe.
	
	- note: By default, it uses refreshInterval equal to 1.
	*/
	@objc
	public convenience init(url: URL) {
		self.init(url: url, refreshInterval: 1)
	}
	
	/**
	Creates a new watcher using given URL and refreshInterval.
	
	- parameter url:             URL to observe.
	- parameter refreshInterval: Minimal refresh interval between queries.
	*/
	@objc
	public init(url: URL, refreshInterval: TimeInterval) {
		remoteWatcher = FileWatcher.Remote(url: url, refreshInterval: refreshInterval)
	}
	
	@objc
	public func refresh() throws {
		try remoteWatcher.refresh()
	}
}

extension RemoteFileWatcher: FileWatcherInput {
	
	public func start() throws {
		try remoteWatcher.start { [weak self] result in
			Task { @MainActor [weak self] in
				guard let self else { return }
				switch result {
				case .noChanges:
					self.delegate?.refreshDidOccur(from: self, type: .noChanges, data: nil)
				case .updated(let data):
					self.delegate?.refreshDidOccur(from: self, type: .updated, data: data)
				case .failed(let error):
					NSLog("Remote watcher failed: %@", String(describing: error))
					self.delegate?.refreshDidFail?(from: self, error: error as NSError)
				}
			}
		}
	}
	
	public func stop() throws {
		try remoteWatcher.stop()
	}
}
