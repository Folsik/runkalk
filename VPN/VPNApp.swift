//
//  VPNApp.swift
//  VPN
//
//  Created by Stas Stukalow on 05.07.2024.
//
//

import SwiftUI
import NetworkExtension
import OpenVPNAdapter

extension NEPacketTunnelFlow: OpenVPNAdapterPacketFlow {}

class PacketTunnelProvider: NEPacketTunnelProvider {

    lazy var vpnAdapter: OpenVPNAdapter = {
        let adapter = OpenVPNAdapter()
        adapter.delegate = self
        return adapter
    }()

    let vpnReachability = OpenVPNReachability()

    var startHandler: ((Error?) -> Void)?
    var stopHandler: (() -> Void)?

    override func startTunnel(options: [String : NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        guard
                let protocolConfiguration = protocolConfiguration as? NETunnelProviderProtocol,
                let providerConfiguration = protocolConfiguration.providerConfiguration
        else {
            completionHandler(NSError(domain: "PacketTunnelProviderError", code: 1001, userInfo: nil))
            return
        }

        guard let ovpnContent = providerConfiguration["ovpn"] as? String else {
            completionHandler(NSError(domain: "PacketTunnelProviderError", code: 1002, userInfo: nil))
            return
        }

        let configuration = OpenVPNConfiguration()
        configuration.fileContent = ovpnContent.data(using: .utf8)
        // Set your required OpenVPN settings here
        configuration.settings = [
            // Example setting: "nobind": "true"
        ]

        configuration.tunPersist = true

        do {
            let evaluation = try vpnAdapter.apply(configuration: configuration)
            if !evaluation.autologin {
                guard let username = protocolConfiguration.username,
                      let password = providerConfiguration["password"] as? String else {
                    completionHandler(NSError(domain: "PacketTunnelProviderError", code: 1003, userInfo: nil))
                    return
                }

                let credentials = OpenVPNCredentials()
                credentials.username = username
                credentials.password = password

                try vpnAdapter.provide(credentials: credentials)
            }
        } catch {
            completionHandler(error)
            return
        }

        vpnReachability.startTracking { [weak self] status in
            guard let strongSelf = self, status == .reachableViaWiFi else { return }
            strongSelf.vpnAdapter.reconnect(afterTimeInterval: 5)
        }

        startHandler = completionHandler
        vpnAdapter.connect(using: packetFlow)
    }

    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        stopHandler = completionHandler

        if vpnReachability.isTracking {
            vpnReachability.stopTracking()
        }

        vpnAdapter.disconnect()
        completionHandler()
    }
}

extension PacketTunnelProvider: OpenVPNAdapterDelegate {

    func openVPNAdapter(_ openVPNAdapter: OpenVPNAdapter, configureTunnelWithNetworkSettings networkSettings: NEPacketTunnelNetworkSettings?, completionHandler: @escaping (Error?) -> Void) {
        networkSettings?.dnsSettings?.matchDomains = [""]

        setTunnelNetworkSettings(networkSettings, completionHandler: completionHandler)
    }

    func openVPNAdapter(_ openVPNAdapter: OpenVPNAdapter, handleEvent event: OpenVPNAdapterEvent, message: String?) {
        switch event {
        case .connected:
            if reasserting {
                reasserting = false
            }

            guard let startHandler = startHandler else { return }

            startHandler(nil)
            self.startHandler = nil

        case .disconnected:
            guard let stopHandler = stopHandler else { return }

            if vpnReachability.isTracking {
                vpnReachability.stopTracking()
            }

            stopHandler()
            self.stopHandler = nil

        case .reconnecting:
            reasserting = true

        default:
            break
        }
    }

    func openVPNAdapter(_ openVPNAdapter: OpenVPNAdapter, handleError error: Error) {
        guard let fatal = (error as NSError).userInfo[OpenVPNAdapterErrorFatalKey] as? Bool, fatal == true else {
            return
        }

        if vpnReachability.isTracking {
            vpnReachability.stopTracking()
        }

        if let startHandler = startHandler {
            startHandler(error)
            self.startHandler = nil
        } else {
            cancelTunnelWithError(error)
        }
    }

    func openVPNAdapter(_ openVPNAdapter: OpenVPNAdapter, handleLogMessage logMessage: String) {
    }

}

var providerManager: NETunnelProviderManager!

override func viewDidLoad() {
    super.viewDidLoad()
    loadProviderManager {
        self.configureVPN(serverAddress: "127.0.0.1", username: "", password: "")
    }
}

func loadProviderManager(completion:@escaping () -> Void) {
    NETunnelProviderManager.loadAllFromPreferences { (managers, error) in
        if error == nil {
            self.providerManager = managers?.first ?? NETunnelProviderManager()
            completion()
        }
    }
}

func configureVPN(serverAddress: String, username: String, password: String) {
    providerManager?.loadFromPreferences { error in
        if error == nil {
            let tunnelProtocol = NETunnelProviderProtocol()
            tunnelProtocol.username = username
            tunnelProtocol.serverAddress = serverAddress
            tunnelProtocol.providerBundleIdentifier = "com.myBundle.myApp"
            tunnelProtocol.providerConfiguration = ["ovpn": configData, "username": username, "password": password]
            tunnelProtocol.disconnectOnSleep = false
            self.providerManager.protocolConfiguration = tunnelProtocol
            self.providerManager.localizedDescription = "Light VPN"
            self.providerManager.isEnabled = true
            self.providerManager.saveToPreferences(completionHandler: { (error) in
                if error == nil  {
                    self.providerManager.loadFromPreferences(completionHandler: { (error) in
                        do {
                            try providerManager?.connection.stopVPNTunnel()
                            completion()
                        } catch let error {
                            print(error.localizedDescription)
                        }
                    })
                }
            })
        }
    }
}