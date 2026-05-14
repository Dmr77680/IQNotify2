import Foundation
import CoreBluetooth
import UserNotifications

let SERVICE_AE30        = CBUUID(string: "AE30")
let CHAR_AE01_WRITE     = CBUUID(string: "AE01")
let CHAR_AE02_NOTIFY    = CBUUID(string: "AE02")
let WATCH_NAME = "QW01s"

private let IQIBLA_DIR_SEND: UInt8         = 0x21
private let IQIBLA_CMD_NOTIF_TITLE: UInt8  = 0x36
private let IQIBLA_CMD_NOTIF_FULL:  UInt8  = 0x46

class BLEManager: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {

    @Published var isConnected      = false
    @Published var isScanning       = false
    @Published var notificationsEnabled = false
    @Published var logs: [String]   = []

    private var centralManager:       CBCentralManager!
    private var watchPeripheral:      CBPeripheral?
    private var writeCharacteristic:  CBCharacteristic?
    private var notifyCharacteristic: CBCharacteristic?
    private var seqCounter: UInt16 = 0x6A47

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
        NotificationCenter.default.addObserver(self, selector: #selector(handleAppNotification(_:)),
                                               name: NSNotification.Name("NewNotificationReceived"), object: nil)
    }

    @objc func handleAppNotification(_ notification: Foundation.Notification) {
        guard let userInfo = notification.userInfo,
              let appName  = userInfo["appName"] as? String,
              let title    = userInfo["title"]   as? String,
              let body     = userInfo["body"]    as? String else { return }
        sendNotificationToWatch(appName: appName, title: title, body: body)
    }

    // MARK: - Nettoyage texte — supprime emojis, convertit accents en ASCII
    func sanitizeForWatch(_ text: String) -> String {
        let accentMap: [Character: String] = [
            "à": "a", "â": "a", "ä": "a", "á": "a", "ã": "a",
            "è": "e", "é": "e", "ê": "e", "ë": "e",
            "î": "i", "ï": "i", "í": "i", "ì": "i",
            "ô": "o", "ö": "o", "ó": "o", "ò": "o", "õ": "o",
            "ù": "u", "û": "u", "ü": "u", "ú": "u",
            "ç": "c", "ñ": "n",
            "À": "A", "Â": "A", "Ä": "A", "Á": "A",
            "È": "E", "É": "E", "Ê": "E", "Ë": "E",
            "Î": "I", "Ï": "I", "Í": "I",
            "Ô": "O", "Ö": "O", "Ó": "O",
            "Ù": "U", "Û": "U", "Ü": "U", "Ú": "U",
            "Ç": "C", "Ñ": "N",
            "\u{2019}": "'", "\u{2018}": "'",
            "\u{201C}": "\"", "\u{201D}": "\"",
            "\u{2013}": "-", "\u{2014}": "-",
            "\u{2026}": "...",
        ]
        var result = ""
        for scalar in text.unicodeScalars {
            let char = Character(scalar)
            if let replacement = accentMap[char] {
                result += replacement
            } else if scalar.value >= 32 && scalar.value <= 126 {
                result.append(char)
            } else if scalar.value == 9 || scalar.value == 10 {
                result += " "
            }
            // Emojis et autres caractères non-ASCII → ignorés
        }
        while result.contains("  ") {
            result = result.replacingOccurrences(of: "  ", with: " ")
        }
        return result.trimmingCharacters(in: .whitespaces)
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
        if central.state == .poweredOn { addLog("✅ Bluetooth activé") }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        guard let name = peripheral.name, name.contains(WATCH_NAME) else { return }
        addLog("📡 Montre trouvée : \(name)")
        centralManager.stopScan()
        DispatchQueue.main.async { self.isScanning = false }
        watchPeripheral = peripheral
        peripheral.delegate = self
        centralManager.connect(peripheral, options: nil)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        addLog("✅ Connecté à \(peripheral.name ?? "QW01s")")
        DispatchQueue.main.async { self.isConnected = true }
        peripheral.discoverServices([SERVICE_AE30])
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { self.sendHandshake() }
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        addLog("🔌 Déconnecté")
        DispatchQueue.main.async { self.isConnected = false; self.writeCharacteristic = nil }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { self.startScanning() }
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        addLog("❌ Échec connexion")
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
                addLog("   ✅ AE01 (écriture) prêt")
            case CHAR_AE02_NOTIFY:
                notifyCharacteristic = char
                peripheral.setNotifyValue(true, for: char)
                addLog("   ✅ AE02 (notifications) activé")
            default:
                if char.properties.contains(.notify) || char.properties.contains(.indicate) {
                    peripheral.setNotifyValue(true, for: char)
                }
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let data = characteristic.value else { return }
        let hex = data.map { String(format: "%02X", $0) }.joined(separator: " ")
        addLog("📥 \(characteristic.uuid): \(hex)")
        let ascii = data.map { ($0 >= 32 && $0 < 127) ? String(UnicodeScalar($0)) : "." }.joined()
        if ascii.contains("ACKBAOS") { addLog("🤝 Handshake ACKBAOS confirmé ✅") }
    }

    private func nextSeq() -> (lo: UInt8, hi: UInt8) {
        seqCounter &+= 1
        return (lo: UInt8(seqCounter & 0xFF), hi: UInt8((seqCounter >> 8) & 0xFF))
    }

    func writeToWatch(bytes: [UInt8]) {
        guard let peripheral = watchPeripheral, let char = writeCharacteristic else {
            addLog("⚠️ Montre non connectée"); return
        }
        let hex = bytes.prefix(16).map { String(format: "%02X", $0) }.joined(separator: " ")
        addLog("📤 \(hex)\(bytes.count > 16 ? "..." : "")")
        peripheral.writeValue(Data(bytes), for: char, type: .withoutResponse)
    }

    func sendHandshake() {
        let (lo, hi) = nextSeq()
        let packet: [UInt8] = [
            lo, hi, IQIBLA_DIR_SEND, 0x0F,
            0x0F, 0x00, 0x00, 0x00,
            0x41, 0x43, 0x4B, 0x42, 0x41, 0x4F, 0x53,
            0x21, 0x78, 0xf6, 0xcc,
            0x00, 0x00, 0x00
        ]
        writeToWatch(bytes: packet)
        addLog("🤝 Handshake ACKBAOS envoyé")
    }

    func sendNotificationToWatch(appName: String, title: String, body: String) {
        guard isConnected else { addLog("⚠️ Non connectée"); return }

        // Nettoyage — emojis et accents supprimés/convertis
        let cleanTitle  = sanitizeForWatch(title)
        let cleanBody   = sanitizeForWatch(body)

        addLog("🔔 [\(appName)] \(cleanTitle)")

        let titleBytes  = Array(cleanTitle.utf8.prefix(31))
        let bodyBytes   = Array(cleanBody.utf8.prefix(31))
        let bundleBytes = Array(bundleID(for: appName).utf8.prefix(31))

        let hasBody = !cleanBody.isEmpty
        let cmd: UInt8 = hasBody ? IQIBLA_CMD_NOTIF_FULL : IQIBLA_CMD_NOTIF_TITLE
        let tsMs = UInt32(Date().timeIntervalSince1970 * 1000) & 0x0FFFFFFF

        var payload: [UInt8] = []
        payload += [0xCD, 0x27, 0x10]
        payload += [0xCE, UInt8((tsMs >> 24) & 0xFF), UInt8((tsMs >> 16) & 0xFF),
                    UInt8((tsMs >> 8) & 0xFF), UInt8(tsMs & 0xFF)]
        payload += [0x00]
        payload += [0xCE, 0x6A, 0x04, 0x80, 0x34]
        payload += [0x00]
        payload += [0xA0 | UInt8(titleBytes.count)] + titleBytes
        if hasBody { payload += [0xA0 | UInt8(bodyBytes.count)] + bodyBytes }
        payload += [0x01]
        payload += [0xA0 | UInt8(bundleBytes.count)] + bundleBytes
        payload += [0xCE, 0x6A, 0x04, 0x80, 0x34]
        payload += [0x00, 0x00, 0x00, 0x00]

        let innerLen = UInt32(payload.count)
        let (lo, hi) = nextSeq()
        var packet: [UInt8] = [lo, hi, IQIBLA_DIR_SEND, cmd,
                               UInt8(innerLen & 0xFF), UInt8((innerLen >> 8) & 0xFF),
                               UInt8((innerLen >> 16) & 0xFF), UInt8((innerLen >> 24) & 0xFF)]
        packet += payload
        writeToWatch(bytes: packet)
    }

    func bundleID(for appName: String) -> String {
        let lower = appName.lowercased()
        switch true {
        case lower.contains("whatsapp"):  return "com.whatsapp"
        case lower.contains("discord"):   return "com.hammerandchisel.discord"
        case lower.contains("message"):   return "com.apple.MobileSMS"
        case lower.contains("mail"):      return "com.apple.mobilemail"
        case lower.contains("phone"):     return "com.apple.mobilephone"
        case lower.contains("telegram"):  return "org.telegram.TelegramSE"
        case lower.contains("instagram"): return "com.burbn.instagram"
        case lower.contains("twitter"), lower.contains("x.com"): return "com.atebits.Tweetie2"
        case lower.contains("facebook"):  return "com.facebook.Facebook"
        case lower.contains("gmail"):     return "com.google.Gmail"
        case lower.contains("outlook"):   return "com.microsoft.Outlook"
        case lower.contains("snapchat"):  return "com.snapchat.snapchat"
        case lower.contains("tiktok"):    return "com.zhiliaoapp.musically"
        case lower.contains("linkedin"):  return "com.linkedin.LinkedIn"
        default:                          return "com.apple.generic"
        }
    }

    func sendTestNotification(appName: String) {
        sendNotificationToWatch(appName: appName, title: appName, body: "Message de test depuis IQNotify")
    }
}
