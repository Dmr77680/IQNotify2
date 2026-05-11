import Foundation
import CoreBluetooth
import UserNotifications
import SwiftUI

// UUIDs de la montre iqibla QW01s-5C4F
let SERVICE_AE30 = CBUUID(string: "AE30")
let CHAR_AE01_WRITE = CBUUID(string: "AE01")
let CHAR_AE02_NOTIFY = CBUUID(string: "AE02")
let CHAR_AE03_WRITE = CBUUID(string: "AE03")
let CHAR_AE04_NOTIFY = CBUUID(string: "AE04")
let CHAR_AE05_INDICATE = CBUUID(string: "AE05")
let CHAR_AE10_RW = CBUUID(string: "AE10")
let SERVICE_AE3A = CBUUID(string: "AE3A")
let CHAR_AE3B_WRITE = CBUUID(string: "AE3B")
let CHAR_AE3C_NOTIFY = CBUUID(string: "AE3C")
let WATCH_NAME = "QW01s"

struct BLEProtocol {
    let name: String
    let description: String
    let color: Color
    let buildPacket: (String, String, String, UInt8) -> [UInt8]
}

class BLEManager: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    
    @Published var isConnected = false
    @Published var isScanning = false
    @Published var notificationsEnabled = false
    @Published var logs: [String] = []
    
    private var centralManager: CBCentralManager!
    private var watchPeripheral: CBPeripheral?
    private var writeCharacteristic: CBCharacteristic?
    private var write2Characteristic: CBCharacteristic?
    
    // MARK: - Tous les protocoles connus
    lazy var protocols: [BLEProtocol] = [
        BLEProtocol(name: "Da Fit / Zeblaze", description: "AB 00 [len] FF 72 [appId] 01 [title] 00 [body]", color: .blue) { title, body, app, appId in
            var p: [UInt8] = [0xAB, 0x00, 0x00, 0xFF, 0x72, appId, 0x01]
            p += Array(title.utf8.prefix(20)); p.append(0x00)
            p += Array(body.utf8.prefix(40)); p.append(0x00)
            p[2] = UInt8(min(p.count - 4, 255)); return p
        },
        BLEProtocol(name: "Colmi / iQOO", description: "CD 00 [len] [appId] 01 [title] 00 [body]", color: .purple) { title, body, app, appId in
            var p: [UInt8] = [0xCD, 0x00, 0x00, appId, 0x01]
            p += Array(title.utf8.prefix(20)); p.append(0x00)
            p += Array(body.utf8.prefix(40)); p.append(0x00)
            p[2] = UInt8(min(p.count - 3, 255)); return p
        },
        BLEProtocol(name: "H Band / Haylou", description: "02 [appId] [len] [title+body UTF8]", color: .orange) { title, body, app, appId in
            let text = "\(title): \(body)"
            var p: [UInt8] = [0x02, appId]
            let textBytes = Array(text.utf8.prefix(60))
            p.append(UInt8(textBytes.count))
            p += textBytes; return p
        },
        BLEProtocol(name: "Amazfit / Huami", description: "07 [appId] 00 01 [title] 00 [body] 00", color: .green) { title, body, app, appId in
            var p: [UInt8] = [0x07, appId, 0x00, 0x01]
            p += Array(title.utf8.prefix(20)); p.append(0x00)
            p += Array(body.utf8.prefix(40)); p.append(0x00)
            return p
        },
        BLEProtocol(name: "Fitpolo / Bozlun", description: "23 [appId] [len] [body]", color: .red) { title, body, app, appId in
            let textBytes = Array(body.utf8.prefix(50))
            var p: [UInt8] = [0x23, appId, UInt8(textBytes.count)]
            p += textBytes; return p
        },
        BLEProtocol(name: "Lenovo / Fossil", description: "FE 00 [appId] 00 [title] 00 [body]", color: .pink) { title, body, app, appId in
            var p: [UInt8] = [0xFE, 0x00, appId, 0x00]
            p += Array(title.utf8.prefix(20)); p.append(0x00)
            p += Array(body.utf8.prefix(40)); p.append(0x00)
            return p
        },
        BLEProtocol(name: "Jieli (JL) chipset", description: "0A 01 [appId] [len16] [title] [body]", color: .teal) { title, body, app, appId in
            let text = "\(title)\0\(body)"
            let textBytes = Array(text.utf8.prefix(60))
            let len = UInt16(textBytes.count)
            var p: [UInt8] = [0x0A, 0x01, appId, UInt8(len >> 8), UInt8(len & 0xFF)]
            p += textBytes; return p
        },
        BLEProtocol(name: "Realtek RTL8762", description: "55 AA [appId] 01 00 [len] [title] [body]", color: .indigo) { title, body, app, appId in
            let titleBytes = Array(title.utf8.prefix(20))
            let bodyBytes = Array(body.utf8.prefix(40))
            let len = titleBytes.count + bodyBytes.count + 2
            var p: [UInt8] = [0x55, 0xAA, appId, 0x01, 0x00, UInt8(min(len, 255))]
            p += titleBytes; p.append(0x00)
            p += bodyBytes; p.append(0x00)
            return p
        },
        BLEProtocol(name: "Nordic NRF52 ANCS-like", description: "01 [notifUID x4] 00 [appId] [title] [body]", color: .cyan) { title, body, app, appId in
            var p: [UInt8] = [0x01, 0x00, 0x00, 0x00, 0x01, 0x00, appId]
            p += Array(title.utf8.prefix(20)); p.append(0x00)
            p += Array(body.utf8.prefix(40)); p.append(0x00)
            return p
        },
        BLEProtocol(name: "Generic QW / iQibla", description: "AE 01 [appId] [len] [title] 00 [body] 00", color: .brown) { title, body, app, appId in
            let titleBytes = Array(title.utf8.prefix(20))
            let bodyBytes = Array(body.utf8.prefix(40))
            let len = titleBytes.count + bodyBytes.count + 2
            var p: [UInt8] = [0xAE, 0x01, appId, UInt8(min(len, 255))]
            p += titleBytes; p.append(0x00)
            p += bodyBytes; p.append(0x00)
            return p
        }
    ]
    
    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
        setupNotificationObserver()
    }
    
    func addLog(_ message: String) {
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        DispatchQueue.main.async {
            self.logs.append("[\(timestamp)] \(message)")
            if self.logs.count > 100 { self.logs.removeFirst() }
        }
    }
    
    func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
            DispatchQueue.main.async {
                self.notificationsEnabled = granted
                self.addLog(granted ? "✅ Notifications autorisées" : "❌ Notifications refusées")
            }
        }
    }
    
    func setupNotificationObserver() {
        NotificationCenter.default.addObserver(self, selector: #selector(handleAppNotification(_:)),
                                               name: NSNotification.Name("NewNotificationReceived"), object: nil)
    }
    
    @objc func handleAppNotification(_ notification: Foundation.Notification) {
        guard let userInfo = notification.userInfo,
              let appName = userInfo["appName"] as? String,
              let title = userInfo["title"] as? String,
              let body = userInfo["body"] as? String else { return }
        sendNotificationToWatch(appName: appName, title: title, body: body)
    }
    
    func startScanning() {
        guard centralManager.state == .poweredOn else { addLog("⚠️ Bluetooth non disponible"); return }
        addLog("🔍 Recherche de QW01s...")
        DispatchQueue.main.async { self.isScanning = true }
        centralManager.scanForPeripherals(withServices: nil, options: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) {
            if !self.isConnected {
                self.centralManager.stopScan()
                DispatchQueue.main.async { self.isScanning = false }
                self.addLog("⏱ Scan terminé")
            }
        }
    }
    
    func disconnect() {
        if let p = watchPeripheral { centralManager.cancelPeripheralConnection(p) }
    }
    
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn { addLog("✅ Bluetooth prêt") }
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        guard let name = peripheral.name, name.contains(WATCH_NAME) else { return }
        addLog("📡 Montre trouvée: \(name)")
        centralManager.stopScan()
        DispatchQueue.main.async { self.isScanning = false }
        watchPeripheral = peripheral
        peripheral.delegate = self
        centralManager.connect(peripheral, options: nil)
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        addLog("✅ Connecté!")
        DispatchQueue.main.async { self.isConnected = true }
        peripheral.discoverServices([SERVICE_AE30, SERVICE_AE3A])
    }
    
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        addLog("🔌 Déconnecté")
        DispatchQueue.main.async { self.isConnected = false; self.writeCharacteristic = nil }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { self.startScanning() }
    }
    
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        addLog("❌ Echec connexion")
        DispatchQueue.main.async { self.isConnected = false }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        peripheral.services?.forEach { peripheral.discoverCharacteristics(nil, for: $0) }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        service.characteristics?.forEach { char in
            switch char.uuid {
            case CHAR_AE01_WRITE:
                writeCharacteristic = char
                addLog("✅ AE01 Write prêt")
            case CHAR_AE3B_WRITE:
                write2Characteristic = char
                addLog("✅ AE3B Write prêt")
            case CHAR_AE02_NOTIFY, CHAR_AE04_NOTIFY, CHAR_AE05_INDICATE, CHAR_AE3C_NOTIFY:
                peripheral.setNotifyValue(true, for: char)
                addLog("✅ \(char.uuid) Notify activé")
            default: break
            }
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let data = characteristic.value else { return }
        let hex = data.map { String(format: "%02X", $0) }.joined(separator: " ")
        addLog("📥 \(characteristic.uuid): \(hex)")
    }
    
    func writeToWatch(bytes: [UInt8], useSecondary: Bool = false) {
        guard let peripheral = watchPeripheral else { addLog("⚠️ Non connecté"); return }
        let char = useSecondary ? write2Characteristic : writeCharacteristic
        guard let char = char else { addLog("⚠️ Caractéristique non disponible"); return }
        let data = Data(bytes)
        let hex = bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
        addLog("📤 [\(char.uuid)] \(hex)")
        peripheral.writeValue(data, for: char, type: .withoutResponse)
    }
    
    // MARK: - Test d'un protocole spécifique
    func sendProtocolTest(index: Int) {
        guard index < protocols.count else { return }
        let p = protocols[index]
        addLog("🧪 Test Format \(index+1): \(p.name)")
        let packet = p.buildPacket("Test IQNotify", "Notification Discord test", "Discord", 0x06)
        writeToWatch(bytes: packet)
        // Essaie aussi sur AE3B
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.writeToWatch(bytes: packet, useSecondary: true)
        }
    }
    
    // MARK: - Envoi notification réelle
    func sendNotificationToWatch(appName: String, title: String, body: String) {
        guard isConnected else { return }
        addLog("🔔 [\(appName)] \(title)")
        let appId = appIDForApp(appName)
        // Envoie tous les formats en séquence
        for (i, proto) in protocols.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.2) {
                let packet = proto.buildPacket(title, body, appName, appId)
                self.writeToWatch(bytes: packet)
            }
        }
    }
    
    func sendTestNotification(appName: String) {
        sendNotificationToWatch(appName: appName, title: appName, body: "Notification test depuis IQNotify")
    }
    
    func appIDForApp(_ appName: String) -> UInt8 {
        switch appName.lowercased() {
        case let s where s.contains("whatsapp"):  return 0x03
        case let s where s.contains("discord"):   return 0x06
        case let s where s.contains("message"):   return 0x01
        case let s where s.contains("mail"):      return 0x02
        case let s where s.contains("phone"):     return 0x04
        case let s where s.contains("telegram"):  return 0x07
        case let s where s.contains("instagram"): return 0x08
        case let s where s.contains("twitter"):   return 0x09
        case let s where s.contains("snapchat"):  return 0x0A
        case let s where s.contains("gmail"):     return 0x0B
        case let s where s.contains("outlook"):   return 0x0C
        default: return 0x0F
        }
    }
}
