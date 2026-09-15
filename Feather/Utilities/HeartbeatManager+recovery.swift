//
//  HeartbeatManager+recovery.swift
//  Feather
//

import Foundation
import IDeviceSwift

extension HeartbeatManager {
	/// Clears RSD tunnel state left behind by a failed `ensureRSDTunnel()`.
	///
	/// `ensureRSDTunnel()` raises `isRestartInProgress` before building the RSD
	/// adapter but only lowers it again on its success path. Every early return
	/// (unreadable pairing file, bad tunnel address, failed handshake) leaves the
	/// flag raised, so the *next* call short-circuits on `guard !isRestartInProgress`
	/// and returns `true` without ever creating an adapter. The caller then fails on
	/// `heartbeat.adapter == nil` and reports "Cannot find RSD adapter" — masking the
	/// original failure for the rest of the process lifetime.
	///
	/// Resetting the flag before each attempt makes a retry actually retry, so the
	/// real error surfaces instead of the stale one.
	func clearStaleTunnelState() {
		isRestartInProgress = false
	}
}
