import SwiftUI
import CoreBluetooth
import UserNotifications

struct ContentView: View {
    @StateObject private var bleManager = BLEManager()
    @State private var selectedTab = 0
    
    var body: some View {
        NavigationView {
            TabView(selection: $selectedTab) {
                
                // MARK: - Tab 1: Connexion
                VStack(spacing: 16) {
                    VStack(spacing: 12) {
                        Image(systemName: bleManager.isConnected ? "applewatch.radiowaves.left.and.right" : "applewatch.slash")
                            .font(.system(size: 60))
                            .foregroundColor(bleManager.isConnected ? .green : .gray)
                        Text(bleManager.isConnected ? "Montre connectée ✅" : "Montre déconnectée")
                            .font(.title2).fontWeight(.semibold)
                        Text("QW01s-5C4F")
                            .font(.caption).foregroundColor(.secondary)
                    }
                    .padding(20)
                    .background(Color(.systemGray6))
                    .cornerRadius(20)
                    
                    Button(action: {
                        if bleManager.isConnected { bleManager.disconnect() }
                        else { bleManager.startScanning() }
                    }) {
                        HStack {
                            Image(systemName: bleManager.isScanning ? "antenna.radiowaves.left.and.right" : (bleManager.isConnected ? "xmark.circle" : "magnifyingglass"))
                            Text(bleManager.isScanning ? "Recherche..." : (bleManager.isConnected ? "Déconnecter" : "Connecter la montre"))
                        }
                        .frame(maxWidth: .infinity).padding()
                        .background(bleManager.isConnected ? Color.red : Color.blue)
                        .foregroundColor(.white).cornerRadius(14)
                    }
                    
                    Button(action: { bleManager.requestNotificationPermission() }) {
                        HStack {
                            Image(systemName: bleManager.notificationsEnabled ? "bell.fill" : "bell.slash")
                            Text(bleManager.notificationsEnabled ? "Notifications activées" : "Activer les notifications")
                        }
                        .frame(maxWidth: .infinity).padding()
                        .background(bleManager.notificationsEnabled ? Color.green : Color.orange)
                        .foregroundColor(.white).cornerRadius(14)
                    }
                    
                    // Log
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Journal").font(.headline)
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 2) {
                                ForEach(bleManager.logs.reversed(), id: \.self) { log in
                                    Text(log).font(.system(size: 10, design: .monospaced))
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .frame(height: 180)
                        .background(Color(.systemGray6))
                        .cornerRadius(12)
                    }
                    Spacer()
                }
                .padding()
                .tabItem { Label("Connexion", systemImage: "antenna.radiowaves.left.and.right") }
                .tag(0)
                
                // MARK: - Tab 2: Test Protocoles
                VStack(spacing: 12) {
                    Text("Test protocoles")
                        .font(.title2).fontWeight(.bold)
                    Text("Appuie sur chaque format et vérifie si ta montre réagit")
                        .font(.caption).foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    
                    ScrollView {
                        VStack(spacing: 10) {
                            ForEach(0..<bleManager.protocols.count, id: \.self) { i in
                                let p = bleManager.protocols[i]
                                Button(action: { bleManager.sendProtocolTest(index: i) }) {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("Format \(i+1) — \(p.name)")
                                                .font(.subheadline).fontWeight(.semibold)
                                                .foregroundColor(.white)
                                            Text(p.description)
                                                .font(.caption)
                                                .foregroundColor(.white.opacity(0.8))
                                        }
                                        Spacer()
                                        Image(systemName: "play.fill")
                                            .foregroundColor(.white)
                                    }
                                    .padding()
                                    .background(p.color)
                                    .cornerRadius(12)
                                }
                            }
                        }
                        .padding(.horizontal)
                    }
                    Spacer()
                }
                .padding(.top)
                .tabItem { Label("Protocoles", systemImage: "wrench.and.screwdriver") }
                .tag(1)
                
                // MARK: - Tab 3: Apps
                VStack(spacing: 12) {
                    Text("Test par app")
                        .font(.title2).fontWeight(.bold)
                    Text("Teste l'envoi de notification pour chaque app")
                        .font(.caption).foregroundColor(.secondary)
                    
                    ScrollView {
                        VStack(spacing: 10) {
                            ForEach(["WhatsApp", "Discord", "Messages", "Mail", "Telegram", "Instagram", "Twitter", "Snapchat", "Gmail", "Outlook"], id: \.self) { app in
                                Button(action: { bleManager.sendTestNotification(appName: app) }) {
                                    HStack {
                                        Text(appEmoji(app))
                                            .font(.title2)
                                        Text(app)
                                            .font(.subheadline).fontWeight(.semibold)
                                        Spacer()
                                        Image(systemName: "paperplane.fill")
                                            .foregroundColor(.blue)
                                    }
                                    .padding()
                                    .background(Color(.systemGray6))
                                    .cornerRadius(12)
                                }
                                .foregroundColor(.primary)
                            }
                        }
                        .padding(.horizontal)
                    }
                    Spacer()
                }
                .padding(.top)
                .tabItem { Label("Apps", systemImage: "bell.badge") }
                .tag(2)
            }
            .navigationTitle("IQNotify")
        }
        .onAppear { bleManager.requestNotificationPermission() }
    }
    
    func appEmoji(_ app: String) -> String {
        switch app {
        case "WhatsApp": return "💬"
        case "Discord": return "🎮"
        case "Messages": return "✉️"
        case "Mail": return "📧"
        case "Telegram": return "✈️"
        case "Instagram": return "📸"
        case "Twitter": return "🐦"
        case "Snapchat": return "👻"
        case "Gmail": return "📨"
        case "Outlook": return "📅"
        default: return "🔔"
        }
    }
}
