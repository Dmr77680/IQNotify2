import SwiftUI

// BLEManager est créé ici directement — plus besoin d'EnvironmentObject
struct ContentView: View {
    @StateObject private var bleManager = BLEManager()

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    StatusCard(isConnected: bleManager.isConnected)
                    ConnectButton(
                        isConnected: bleManager.isConnected,
                        isScanning: bleManager.isScanning,
                        onTap: {
                            if bleManager.isConnected {
                                bleManager.disconnect()
                            } else {
                                bleManager.startScanning()
                            }
                        }
                    )
                    NotificationButton(
                        enabled: bleManager.notificationsEnabled,
                        onTap: { bleManager.requestNotificationPermission() }
                    )
                    if bleManager.isConnected {
                        TestButtons(bleManager: bleManager)
                    }
                    LogView(
                        logs: bleManager.logs,
                        onClear: { bleManager.logs.removeAll() }
                    )
                }
                .padding()
            }
            .navigationTitle("IQNotify")
        }
        .onAppear {
            bleManager.requestNotificationPermission()
            NotificationInterceptor.shared.setup(bleManager: bleManager)
        }
    }
}

// MARK: - Sous-vues

struct StatusCard: View {
    let isConnected: Bool
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: isConnected
                  ? "applewatch.radiowaves.left.and.right"
                  : "applewatch.slash")
                .font(.system(size: 60))
                .foregroundColor(isConnected ? .green : .gray)
            Text(isConnected ? "Montre connectée" : "Montre déconnectée")
                .font(.title2)
                .fontWeight(.semibold)
            Text("QW01s-5C4F")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(30)
        .frame(maxWidth: .infinity)
        .background(Color(.systemGray6))
        .cornerRadius(20)
    }
}

struct ConnectButton: View {
    let isConnected: Bool
    let isScanning: Bool
    let onTap: () -> Void

    private var iconName: String {
        if isScanning { return "antenna.radiowaves.left.and.right" }
        return isConnected ? "xmark.circle" : "magnifyingglass"
    }
    private var label: String {
        if isScanning { return "Recherche en cours…" }
        return isConnected ? "Déconnecter" : "Connecter la montre"
    }

    var body: some View {
        Button(action: onTap) {
            HStack {
                if isScanning {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .padding(.trailing, 4)
                }
                Image(systemName: iconName)
                Text(label)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(isConnected ? Color.red : Color.blue)
            .foregroundColor(.white)
            .cornerRadius(14)
        }
        .disabled(isScanning)
    }
}

struct NotificationButton: View {
    let enabled: Bool
    let onTap: () -> Void
    var body: some View {
        Button(action: onTap) {
            HStack {
                Image(systemName: enabled ? "bell.fill" : "bell.slash")
                Text(enabled ? "Notifications activées ✓" : "Activer les notifications")
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(enabled ? Color.green : Color.orange)
            .foregroundColor(.white)
            .cornerRadius(14)
        }
    }
}

struct TestButtons: View {
    let bleManager: BLEManager
    var body: some View {
        VStack(spacing: 10) {
            Text("Test de notification")
                .font(.headline)
            HStack(spacing: 10) {
                ForEach(["WhatsApp", "Discord", "Messages"], id: \.self) { app in
                    Button(app) {
                        bleManager.sendTestNotification(appName: app)
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .background(Color.purple.opacity(0.15))
                    .foregroundColor(.purple)
                    .cornerRadius(10)
                    .font(.caption)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color(.systemGray6))
        .cornerRadius(16)
    }
}

struct LogView: View {
    let logs: [String]
    let onClear: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Journal")
                    .font(.headline)
                Spacer()
                Button("Effacer", action: onClear)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(logs.reversed().enumerated()), id: \.offset) { _, log in
                        Text(log)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.horizontal)
                    }
                }
            }
            .frame(height: 220)
            .background(Color(.systemGray6))
            .cornerRadius(12)
        }
    }
}
