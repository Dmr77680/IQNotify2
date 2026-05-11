import Foundation
import CoreBluetooth
import UserNotifications

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

class BLEManager: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    
    @Published var isConnected = false
    @Published var isScanning = false
    @Published var notificationsEnabled = false
    @Published var logs: [String] = []
    
    private var centralManager: CBCentralManager!
    private var watchPeripheral: CBPeripheral?
    private var writeCharacteristic: CBCharacteristic?
    private var notifyCharacteristic: CBCharacteristic?
    
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
                self.addLog(granted ? "✅ Notifications accordées" : "❌ Notifications refusées")
            }
        }
    }
    
    func setupNotificationObserver() {
        NotificationCenter.default.addObserver(self, selector: #selector(handleAppNotification(_:)), name: NSNotification.Name("NewNotificationReceived"), object: nil)
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
        addLog("🔍 Recherche de la montre QW01s...")
        DispatchQueue.main.async { self.isScanning = true }
        centralManager.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
            if !self.isConnected {
                self.centralManager.stopScan()
                DispatchQueue.main.async { self.isScanning = false }
                self.addLog("⏱ Scan terminé — montre non trouvée")
            }
        }
    }
    
    func disconnect() {
        if let peripheral = watchPeripheral { centralManager.cancelPeripheralConnection(peripheral) }
    }
    
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn: addLog("✅ Bluetooth activé")
        case .poweredOff: addLog("❌ Bluetooth désactivé")
        default: break
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        guard let name = peripheral.name, name.contains(WATCH_NAME) else { return }
        addLog("📡 Montre trouvée: \(name)")
        centralManager.stopScan()
        DispatchQueue.main.async { self.isScanning = false }
        watchPeripheral = peripheral
        peripheral.delegate = self
        centralManager.connect(peripheral, options: nil)
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        addLog("✅ Connecté à \(peripheral.name ?? "montre")")
        DispatchQueue.main.async { self.isConnected = true }
        peripheral.discoverServices([SERVICE_AE30, SERVICE_AE3A])
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { self.sendHandshake() }
    }
    
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        addLog("🔌 Déconnecté de la montre")
        DispatchQueue.main.async { self.isConnected = false; self.writeCharacteristic = nil; self.notifyCharacteristic = nil }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { self.addLog("🔄 Tentative de reconnexion..."); self.startScanning() }
    }
    
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        addLog("❌ Echec connexion: \(error?.localizedDescription ?? "inconnu")")
        DispatchQueue.main.async { self.isConnected = false }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        for service in services { addLog("🔧 Service: \(service.uuid)"); peripheral.discoverCharacteristics(nil, for: service) }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let characteristics = service.characteristics else { return }
        for char in characteristics {
            switch char.uuid {
            case CHAR_AE01_WRITE: writeCharacteristic = char; addLog("✅ Canal écriture AE01 prêt")
            case CHAR_AE02_NOTIFY: notifyCharacteristic = char; peripheral.setNotifyValue(true, for: char); addLog("✅ Canal notification AE02 activé")
            case CHAR_AE04_NOTIFY, CHAR_AE05_INDICATE, CHAR_AE3C_NOTIFY: peripheral.setNotifyValue(true, for: char)
            default: break
            }
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let data = characteristic.value else { return }
        let hex = data.map { String(format: "%02X", $0) }.joined(separator: " ")
        addLog("📥 Reçu sur \(characteristic.uuid): \(hex)")
    }
    
    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error { addLog("❌ Erreur écriture: \(error.localizedDescription)") }
    }
    
    func sendHandshake() {
        let commands: [[UInt8]] = [
            [0xAB, 0x00, 0x04, 0xFF, 0x31, 0x00, 0x00],
            [0xAB, 0x00, 0x04, 0xFF, 0x93, 0x00, 0x00],
            [0x01, 0x00, 0x00, 0x00],
        ]
        for (index, cmd) in commands.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * 0.5) { self.writeToWatch(bytes: cmd) }
        }
    }
    
    func writeToWatch(bytes: [UInt8]) {
        guard let peripheral = watchPeripheral, let characteristic = writeCharacteristic else { addLog("⚠️ Montre non connectée"); return }
        let data = Data(bytes)
        let hex = bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
        addLog("📤 Envoi: \(hex)")
        peripheral.writeValue(data, for: characteristic, type: .withoutResponse)
    }
    
    func sendNotificationToWatch(appName: String, title: String, body: String) {
        guard isConnected else { addLog("⚠️ Montre non connectée — notification ignorée"); return }
        addLog("🔔 Notification: [\(appName)] \(title)")
        let appId: UInt8 = appIDForApp(appName)
        let titleData = Array(title.utf8.prefix(20))
        let bodyData = Array(body.utf8.prefix(40))
        var packet1: [UInt8] = [0xAB, 0x00, 0x00, 0xFF, 0x72, appId, 0x00, 0x01]
        packet1.append(contentsOf: titleData); packet1.append(0x00)
        packet1.append(contentsOf: bodyData); packet1.append(0x00)
        packet1[2] = UInt8(packet1.count - 4)
        writeToWatch(bytes: packet1)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            var packet2: [UInt8] = [0xCD, 0x00, 0x00, appId, 0x01]
            packet2.append(contentsOf: titleData); packet2.append(0x00)
            packet2.append(contentsOf: bodyData); packet2.append(0x00)
            packet2[2] = UInt8(min(packet2.count - 3, 255))
            self.writeToWatch(bytes: packet2)
        }
    }
    
    func appIDForApp(_ appName: String) -> UInt8 {
        let appLower = appName.lowercased()
        switch true {
        case appLower.contains("whatsapp"): return 0x03
        case appLower.contains("discord"):  return 0x06
        case appLower.contains("message"):  return 0x01
        case appLower.contains("mail"):     return 0x02
        case appLower.contains("phone"):    return 0x04
        case appLower.contains("telegram"): return 0x07
        case appLower.contains("instagram"):return 0x08
        case appLower.contains("twitter") || appLower.contains("x.com"): return 0x09
        default: return 0x0F
        }
    }
    
    func sendTestNotification(appName: String) {
        sendNotificationToWatch(appName: appName, title: "Test \(appName)", body: "Notification de test depuis IQNotify")
    }
}
