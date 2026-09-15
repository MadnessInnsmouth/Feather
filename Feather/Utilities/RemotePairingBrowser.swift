//
//  RemotePairingBrowser.swift
//  Feather
//

import Foundation
import Network
import OSLog

/// Finds the RemotePairing service and the port it is actually listening on.
///
/// The port is assigned dynamically, so it cannot be hardcoded: the reference
/// implementations all browse for the service and use the port it advertises.
/// Connecting to a guessed port reaches whatever happens to be bound there,
/// which accepts the TCP connection and then resets it once the RPPairing
/// handshake starts.
///
/// Requires `NSLocalNetworkUsageDescription` and an `NSBonjourServices` entry
/// for each type below, or iOS returns no results without reporting an error.
enum RemotePairingBrowser {
	/// Service types that carry a RemotePairing endpoint, most specific first.
	static let serviceTypes = [
		"_remotepairing._tcp",
		"_remotepairing-manual-pairing._tcp",
		"_remotepairing-pairable-host._tcp",
	]

	struct Endpoint {
		let host: String
		let port: UInt16
		let serviceType: String
	}

	/// Browses for a RemotePairing service and resolves it to a host and port.
	///
	/// - Parameter timeout: How long to wait before giving up on all types.
	static func discover(timeout: TimeInterval = 6.0) async -> Endpoint? {
		for type in serviceTypes {
			if let found = await _browse(type: type, timeout: timeout / Double(serviceTypes.count)) {
				Logger.misc.info("RemotePairing found via \(type) at \(found.host):\(found.port)")
				return found
			}
		}

		Logger.misc.error("RemotePairing browse found no services")
		return nil
	}

	private static func _browse(type: String, timeout: TimeInterval) async -> Endpoint? {
		let parameters = NWParameters.tcp
		parameters.includePeerToPeer = true

		let browser = NWBrowser(
			for: .bonjour(type: type, domain: nil),
			using: parameters
		)

		let service: NWEndpoint? = await withCheckedContinuation { continuation in
			let lock = NSLock()
			var resumed = false

			func finish(_ endpoint: NWEndpoint?) {
				lock.lock()
				let shouldResume = !resumed
				resumed = true
				lock.unlock()

				guard shouldResume else { return }
				browser.cancel()
				continuation.resume(returning: endpoint)
			}

			browser.browseResultsChangedHandler = { results, _ in
				guard let first = results.first else { return }
				finish(first.endpoint)
			}

			browser.stateUpdateHandler = { state in
				if case .failed(let error) = state {
					Logger.misc.error("RemotePairing browse failed for \(type): \(error.localizedDescription)")
					finish(nil)
				}
			}

			browser.start(queue: .global(qos: .userInitiated))
			DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { finish(nil) }
		}

		guard let service else { return nil }
		return await _resolve(service, type: type)
	}

	/// Resolves a Bonjour endpoint to a concrete address by opening a connection
	/// to it and reading back the path it settled on — there is no lookup API
	/// that returns the port directly.
	private static func _resolve(_ endpoint: NWEndpoint, type: String, timeout: TimeInterval = 4.0) async -> Endpoint? {
		let connection = NWConnection(to: endpoint, using: .tcp)

		return await withCheckedContinuation { continuation in
			let lock = NSLock()
			var resumed = false

			func finish(_ result: Endpoint?) {
				lock.lock()
				let shouldResume = !resumed
				resumed = true
				lock.unlock()

				guard shouldResume else { return }
				connection.cancel()
				continuation.resume(returning: result)
			}

			connection.stateUpdateHandler = { state in
				switch state {
				case .ready:
					guard
						let remote = connection.currentPath?.remoteEndpoint,
						case let .hostPort(host, port) = remote
					else {
						finish(nil)
						return
					}

					// Strip the %en0-style interface suffix NWEndpoint prints.
					let address = "\(host)".split(separator: "%").first.map(String.init) ?? "\(host)"
					finish(Endpoint(host: address, port: port.rawValue, serviceType: type))
				case .failed, .cancelled:
					finish(nil)
				default:
					break
				}
			}

			connection.start(queue: .global(qos: .userInitiated))
			DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { finish(nil) }
		}
	}
}
