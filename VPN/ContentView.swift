//
//  ContentView.swift
//  VPN
//
//  Created by Stas Stukalow on 05.07.2024.
//
//
import SwiftUI

struct ContentView: View {
    @State private var serverAddress = ""
    @State private var username = ""
    @State private var password = ""
    @State private var isConnected = false

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("VPN Configuration")) {
                    TextField("Server Address", text: $serverAddress)
                    TextField("Username", text: $username)
                    SecureField("Password", text: $password)
                }

                Section {
                    Button(action: {
                        // Здесь должен быть код для подключения к VPN
                        self.connectVPN()
                    }) {
                        Text(isConnected ? "Disconnect" : "Connect")
                    }
                }
            }
                    .navigationBarTitle("Light VPN")
        }
    }

    func connectVPN() {
        // Здесь должен быть код для управления VPN-соединением
        // Это может включать вызов метода для настройки VPN и управления подключением
        if isConnected {
            // Отключиться от VPN
            isConnected = false
        } else {
            // Подключиться к VPN
            isConnected = true
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}