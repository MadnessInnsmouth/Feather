//
//  PairingFileInspector.swift
//  Feather
//

import Foundation

/// Identifies which pairing-file format a file on disk holds.
///
/// There are two incompatible formats in circulation and they are not
/// interchangeable:
///
/// - `.lockdown` — the classic lockdownd trust record written when a device
///   trusts a computer, and what `jitterbugpair`, `pymobiledevice3` and most
///   sideloading tools hand you. Read with `idevice_pairing_file_read`.
/// - `.remotePairing` — the RemoteXPC/RemotePairing record used by the RSD
///   tunnel path on iOS 17.4+. Read with `rp_pairing_file_read`.
///
/// Feather's install path picks its reader from the *iOS version* rather than
/// from the file it was actually given, so handing the RSD path a lockdown file
/// fails deep inside the tunnel setup with a generic "Missing Pairing".
/// Detecting the format at import time turns that into something a user can act
/// on.
enum PairingFileFormat: Equatable {
	case lockdown
	case remotePairing
	case unknown
	case unreadable(String)
}

enum PairingFileInspector {
	/// Keys that only ever appear in a classic lockdownd pairing record.
	private static let lockdownKeys: Set<String> = [
		"HostID", "SystemBUID", "HostCertificate", "DeviceCertificate", "EscrowBag"
	]

	/// Inspects the pairing file at `path`.
	///
	/// Lockdown records are identified positively by their key set. Anything that
	/// parses as a property list but carries none of those keys is reported as
	/// `.remotePairing`, by elimination rather than by schema — so treat that case
	/// as "not lockdown" rather than as a guarantee the RSD path will accept it.
	static func inspect(atPath path: String) -> PairingFileFormat {
		guard let data = FileManager.default.contents(atPath: path) else {
			return .unreadable("File could not be read.")
		}

		guard !data.isEmpty else {
			return .unreadable("File is empty.")
		}

		let plist: Any
		do {
			plist = try PropertyListSerialization.propertyList(
				from: data,
				options: [],
				format: nil
			)
		} catch {
			return .unreadable("Not a property list: \(error.localizedDescription)")
		}

		guard let dict = plist as? [String: Any] else {
			return .unreadable("Property list is not a dictionary.")
		}

		let keys = Set(dict.keys)

		if !keys.isDisjoint(with: lockdownKeys) {
			return .lockdown
		}

		return keys.isEmpty ? .unknown : .remotePairing
	}
}

extension PairingFileFormat {
	/// Short label for the settings row.
	var title: String {
		switch self {
		case .lockdown: .localized("Lockdown pairing file")
		case .remotePairing: .localized("Remote pairing file")
		case .unknown: .localized("Unrecognised pairing file")
		case .unreadable: .localized("Invalid pairing file")
		}
	}

	/// What the user should do about it, if anything.
	func advice(isRsd: Bool) -> String {
		switch self {
		case .lockdown where isRsd:
			return .localized("This device uses the RSD tunnel, which needs a remote pairing file. A lockdown pairing file will fail with ‘Missing Pairing’.")
		case .lockdown:
			return .localized("This is the format this device expects.")
		case .remotePairing where isRsd:
			return .localized("This is the format this device expects.")
		case .remotePairing:
			return .localized("This device uses the lockdown socket, which needs a classic lockdown pairing file.")
		case .unknown:
			return .localized("The file parsed but contains no recognisable pairing keys.")
		case .unreadable(let reason):
			return reason
		}
	}
}
