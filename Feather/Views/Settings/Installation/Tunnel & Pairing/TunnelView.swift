//
//  SettingsTunnelView.swift
//  Feather (idevice)
//
//  Created by samara on 29.04.2025.
//

import SwiftUI
import NimbleViews
import IDeviceSwift

// MARK: - View
struct TunnelView: View {
	@State private var _isImportingPairingPresenting = false
	
	@State var doesHavePairingFile = false
	@State private var _pairingFormat: PairingFileFormat?
	@State private var _isGeneratingPairing = false
	@AppStorage("Feather.pairingHost") private var _pairingHost: String = ""
	@AppStorage("Feather.pairingPort") private var _pairingPort: Int = 0
	@AppStorage("Feather.pairingPin") private var _pairingPin: String = ""
	@State private var isLocalDevVpnAvailable = false
	
	// MARK: Body
	var body: some View {
		Group {
			Section {
				if #available(iOS 17.4, *) {
				} else {
					_tunnelInfo()
					TunnelHeaderView()
				}
			} footer: {
				if let format = _pairingFormat {
					VStack(alignment: .leading, spacing: 4) {
						Text(format.title)
						Text(format.advice(isRsd: HeartbeatManager.shared.isRsd))
					}
				} else {
					Text(.localized("No pairing file found, please import it."))
				}
			}
			
			Section {
				Button(.localized("Import Pairing File"), systemImage: "square.and.arrow.down") {
					_isImportingPairingPresenting = true
				}
				if _needsRemotePairing {
					Button {
						_generateRemotePairing()
					} label: {
						HStack {
							Label(.localized("Generate Remote Pairing File"), systemImage: "wand.and.stars")
							if _isGeneratingPairing {
								Spacer()
								ProgressView()
							}
						}
					}
					.disabled(_isGeneratingPairing)
				}
				if #available(iOS 17.4, *) {
				} else {
					Button(.localized("Restart Heartbeat"), systemImage: "arrow.counterclockwise") {
						HeartbeatManager.shared.start(true)
						
						DispatchQueue.global(qos: .userInitiated).async {
							if !HeartbeatManager.shared.checkSocketConnection().isConnected {
								DispatchQueue.main.async {
									UIAlertController.showAlertWithOk(
										title: "Socket",
										message: "Unable to connect to TCP. Make sure you have loopback VPN enabled and you are on WiFi or Airplane mode."
									)
								}
							}
						}
					}
				}
			}
			
			NBSection(.localized("Pairing Service")) {
				HStack {
					Text(.localized("Address"))
					Spacer()
					TextField(HeartbeatManager.shared.ipAddress, text: $_pairingHost)
						.multilineTextAlignment(.trailing)
						.autocorrectionDisabled()
						.textInputAutocapitalization(.never)
				}
				HStack {
					Text(.localized("Port"))
					Spacer()
					TextField(.localized("Auto"), value: $_pairingPort, format: .number.grouping(.never))
						.multilineTextAlignment(.trailing)
						.keyboardType(.numberPad)
				}
				HStack {
					Text(.localized("PIN"))
					Spacer()
					TextField("000000", text: $_pairingPin)
						.multilineTextAlignment(.trailing)
						.keyboardType(.numberPad)
				}
			} footer: {
				Text(.localized("Leave the port empty to discover the pairing service automatically. Set it only if discovery fails. Enter a PIN if this device shows one while pairing."))
			}

			NBSection(.localized("Help")) {
				Button(.localized("Pairing File Guide"), systemImage: "questionmark.circle") {
					UIApplication.open("https://github.com/claration/Impactor#pairing-file")
				}
				if isLocalDevVpnAvailable {
					Button(.localized("Connect to LocalDevVPN"), systemImage: "link") {
						UIApplication.open("localdevvpn://enable?scheme=feather")
					}
				} else {
					Button(.localized("Download LocalDevVPN"), systemImage: "arrow.down.app") {
						UIApplication.open("https://apps.apple.com/us/app/localdevvpn/id6755608044")
					}
				}
			}
		}
		.sheet(isPresented: $_isImportingPairingPresenting) {
			FileImporterRepresentableView(
				allowedContentTypes:  [.xmlPropertyList, .plist, .mobiledevicepairing],
				onDocumentsPicked: { urls in
					guard let selectedFileURL = urls.first else { return }
					FR.movePairing(selectedFileURL)
					_refreshPairingFormat()
				}
			)
			.ignoresSafeArea()
		}
		.onAppear {
			_refreshPairingFormat()
			if let url = URL(string: "localdevvpn://") {
				isLocalDevVpnAvailable = UIApplication.shared.canOpenURL(url)
			} else {
				isLocalDevVpnAvailable = false
			}
		}
	}
	
	/// Whether this device needs a RemotePairing file and has no usable one.
	///
	/// Covers the no-file case too: pairing runs against the device over the
	/// tunnel, so nothing has to be imported first.
	private var _needsRemotePairing: Bool {
		HeartbeatManager.shared.isRsd && _pairingFormat != .remotePairing
	}

	private func _generateRemotePairing() {
		_isGeneratingPairing = true

		FR.generateRemotePairingFile(pin: _pairingPin.isEmpty ? "000000" : _pairingPin) { error in
			_isGeneratingPairing = false
			_refreshPairingFormat()

			UIAlertController.showAlertWithOk(
				title: .localized("Pairing File"),
				message: error.map { String(describing: $0) }
					?? .localized("Generated a remote pairing file for this device.")
			)
		}
	}

	/// Re-reads the stored pairing file and identifies its format.
	///
	/// Replaces a bare `fileExists` check, which reported success for any file at
	/// the path regardless of whether the install path could actually parse it.
	private func _refreshPairingFormat() {
		let path = HeartbeatManager.pairingFile()

		guard FileManager.default.fileExists(atPath: path) else {
			doesHavePairingFile = false
			_pairingFormat = nil
			return
		}

		doesHavePairingFile = true
		_pairingFormat = PairingFileInspector.inspect(atPath: path)
	}

	@ViewBuilder
	private func _tunnelInfo() -> some View {
		HStack {
			VStack(alignment: .leading, spacing: 6) {
				Text(.localized("Heartbeat"))
					.font(.headline)
				Text(.localized("The heartbeat is activated in the background, it will restart when the app is re-opened or prompted. If the status below is pulsing, that means its healthy."))
					.font(.subheadline)
					.foregroundStyle(.secondary)
			}
			.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
		}
	}
}
