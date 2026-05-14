import Foundation
import CoreBluetooth
import UserNotifications

// MARK: - UUIDs
let SERVICE_AE30    = CBUUID(string: "AE30")
let CHAR_AE01_WRITE = CBUUID(string: "AE01")
let CHAR_AE02_NOTIFY = CBUUID(string: "AE02")

let WATCH_NAME = "QW01s"

// MARK: - Constantes protocole
private let IQIBLA_DIR_SEND: UInt8 = 0x21
private let IQIBLA_CMD_NOTIF_TITLE: UInt8 = 0x36
private let IQIBLA_CMD_NOTIF_FULL: UInt8 = 0x46

class BLEManager: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {

    @Published var isConnected = false
    @Published var isScanning = false
    @Published var notificationsEnabled = false
    @Published var logs: [String] = []

    private var centralManager: CBCentralManager!
    private var watchPeripheral: CBPeripheral?
    private var writeCharacteristic: CBCharacteristic?
    private var notifyCharacteristic: CBCharacteristic?

    private var seqCounter: UInt16 = 0x6A47

    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
        setupNotificationObserver()
    }

    // MARK: - Logging
    func addLog(_ message: String) {
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        let line = "[\(timestamp)] \(message)"
        DispatchQueue.main.async {
            self.logs.append(line)
            if self.logs.count > 100 { self.logs.removeFirst() }
        }
    }

    // MARK: - Notification Observer
    func setupNotificationObserver() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppNotification(_:)),
            name: NSNotification.Name("NewNotificationReceived"),
            object: nil
        )
    }

    @objc func handleAppNotification(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let appName = userInfo["appName"] as? String,
              let title = userInfo["title"] as? String,
              let body = userInfo["body"] as? String else { return }
        
        sendNotificationToWatch(appName: appName, title: title, body: body)
    }

    // MARK: - BLE Management
    func startScanning() {
        guard centralManager.state == .poweredOn else { return }
        centralManager.scanForPeripherals(withServices: nil, options: nil)
        DispatchQueue.main.async { self.isScanning = true }
    }

    func disconnect() {
        if let peripheral = watchPeripheral {
            centralManager.cancelPeripheralConnection(peripheral)
        }
    }

    // MARK: - CBCentralManagerDelegate
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            addLog("✅ Bluetooth activé")
            startScanning()
        case .poweredOff:
            addLog("❌ Bluetooth désactivé")
        default: break
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        guard let name = peripheral.name, name.contains(WATCH_NAME) else { return }
        addLog("📡 Montre trouvée : \(name)")
        central.stopScan()
        DispatchQueue.main.async { self.isScanning = false }
        
        watchPeripheral = peripheral
        peripheral.delegate = self
        central.connect(peripheral)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        addLog("✅ Connecté à la montre")
        DispatchQueue.main.async { self.isConnected = true }
        peripheral.discoverServices([SERVICE_AE30])
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        addLog("🔌 Déconnecté")
        DispatchQueue.main.async { self.isConnected = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            self.startScanning()
        }
    }

    // MARK: - CBPeripheralDelegate
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        for service in services {
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let characteristics = service.characteristics else { return }
        for char in characteristics {
            if char.uuid == CHAR_AE01_WRITE {
                writeCharacteristic = char
            } else if char.uuid == CHAR_AE02_NOTIFY {
                notifyCharacteristic = char
                peripheral.setNotifyValue(true, for: char)
            }
        }
    }

    // MARK: - Nettoyage texte (accents + emojis)
    private func cleanForWatch(_ text: String) -> String {
        var result = text
        
        let replacements: [String: String] = [
            "é": "e", "è": "e", "ê": "e", "ë": "e",
            "à": "a", "â": "a", "ä": "a",
            "î": "i", "ï": "i",
            "ô": "o", "ö": "o",
            "ù": "u", "û": "u", "ü": "u",
            "ç": "c",
            "É": "E", "È": "E", "Ê": "E",
            "À": "A", "Â": "A", "Ô": "O", "Ù": "U", "Ç": "C"
        ]
        
        for (accent, replacement) in replacements {
            result = result.replacingOccurrences(of: accent, with: replacement)
        }
        
        // Supprime emojis
        result = result.replacingOccurrences(of: #"\p{Emoji}"#, with: " ", options: .regularExpression)
        
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Envoi Notification
    func sendNotificationToWatch(appName: String, title: String, body: String) {
        guard let peripheral = watchPeripheral, let characteristic = writeCharacteristic else { return }

        let cleanTitle = cleanForWatch(title)
        let cleanBody = cleanForWatch(body)
        
        let titleData = cleanTitle.data(using: .gbk, allowLossyConversion: true) ?? cleanTitle.data(using: .utf8)!
        let bodyData = cleanBody.data(using: .gbk, allowLossyConversion: true) ?? cleanBody.data(using: .utf8)!
        
        let titleBytes = Array(titleData.prefix(40))
        let bodyBytes = Array(bodyData.prefix(80))
        let bundleStr = bundleID(for: appName)
        let bundleBytes = Array(bundleStr.utf8.prefix(31))

        let hasBody = !body.isEmpty
        let cmd: UInt8 = hasBody ? IQIBLA_CMD_NOTIF_FULL : IQIBLA_CMD_NOTIF_TITLE

        let tsMs = UInt32(Date().timeIntervalSince1970 * 1000) & 0x0FFFFFFF

        var payload: [UInt8] = []
        payload += [0xCD, 0x27, 0x10]
        payload += [0xCE] + withUnsafeBytes(of: tsMs.bigEndian) { Array($0) }
        payload += [0x00, 0xCE, 0x6A, 0x04, 0x80, 0x34, 0x00]
        
        payload += [0xA0 | UInt8(titleBytes.count)] + titleBytes
        
        if hasBody {
            payload += [0xA0 | UInt8(bodyBytes.count)] + bodyBytes
        }
        
        payload += [0x01]
        payload += [0xA0 | UInt8(bundleBytes.count)] + bundleBytes
        payload += [0xCE, 0x6A, 0x04, 0x80, 0x34, 0x00, 0x00, 0x00, 0x00]

        let innerLen = UInt32(payload.count)
        let (lo, hi) = nextSeq()

        var packet: [UInt8] = [lo, hi, IQIBLA_DIR_SEND, cmd]
        packet += [UInt8(innerLen & 0xFF), UInt8((innerLen >> 8) & 0xFF),
                   UInt8((innerLen >> 16) & 0xFF), UInt8((innerLen >> 24) & 0xFF)]
        packet += payload

        let data = Data(packet)
        peripheral.writeValue(data, for: characteristic, type: .withoutResponse)
        
        addLog("🔔 [\(appName)] \(cleanTitle)")
    }

    private func nextSeq() -> (lo: UInt8, hi: UInt8) {
        seqCounter &+= 1
        return (UInt8(seqCounter & 0xFF), UInt8((seqCounter >> 8) & 0xFF))
    }

    func bundleID(for appName: String) -> String {
        let lower = appName.lowercased()
        if lower.contains("whatsapp") { return "com.whatsapp" }
        if lower.contains("telegram") { return "org.telegram.TelegramSE" }
        if lower.contains("message") { return "com.apple.MobileSMS" }
        return "com.apple.generic"
    }

    func sendTestNotification() {
        sendNotificationToWatch(appName: "Test", title: "Test Accents", body: "Bonjour ça va ? éèàçù îï ôö")
    }
}
