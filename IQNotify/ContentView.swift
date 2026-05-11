import SwiftUI
import CoreBluetooth
import UserNotifications

struct ContentView: View {
    @StateObject private var bleManager = BLEManager()
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                VStack(spacing: 12) {
                    Image(systemName: bleManager.isConnected ? "applewatch.radiowaves.left.and.right" : "applewatch.slash")
                        .font(.system(size: 60))
                        .foregroundColor(bleManager.isConnected ? .green : .gray)
                    
                    Text(bleManager.isConnected ? "Montre connectée" : "Montre déconnectée")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Text("QW01s-5C4F")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(30)
                .background(Color(.systemGray6))
                .cornerRadius(20)
                
                Button(action: {
                    if bleManager.isConnected {
                        bleManager.disconnect()
                    } else {
                        bleManager.startScanning()
                    }
                }) {
                    HStack {
                        Image(systemName: bleManager.isScanning ? "antenna.radiowaves.left.and.right" : (bleManager.isConnected ? "xmark.circle" : "magnifyingglass"))
                        Text(bleManager.isScanning ? "Recherche..." : (bleManager.isConnected ? "Déconnecter" : "Connecter la montre"))
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(bleManager.isConnected ? Color.red : Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(14)
                }
                
                Button(action: {
                    bleManager.requestNotificationPermission()
                }) {
                    HStack {
                        Image(systemName: bleManager.notificationsEnabled ? "bell.fill" : "bell.slash")
                        Text(bleManager.notificationsEnabled ? "Notifications activées" : "Activer les notifications")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(bleManager.notificationsEnabled ? Color.green : Color.orange)
                    .foregroundColor(.white)
                    .cornerRadius(14)
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Journal")
                        .font(.headline)
                        .padding(.horizontal)
                    
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 4) {
                            ForEach(bleManager.logs.reversed(), id: \.self) { log in
                                Text(log)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal)
                            }
                        }
                    }
                    .frame(height: 200)
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                }
                
                Spacer()
            }
            .padding()
            .navigationTitle("IQNotify")
        }
        .onAppear {
            bleManager.requestNotificationPermission()
        }
    }
}
