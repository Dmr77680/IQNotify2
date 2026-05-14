import Foundation
import CoreBluetooth
import UserNotifications

// MARK: - UUIDs réels de la montre iqibla QW01s-5C4F
let SERVICE_AE30        = CBUUID(string: "AE30")
let CHAR_AE01_WRITE     = CBUUID(string: "AE01")
let CHAR_AE02_NOTIFY    = CBUUID(string: "AE02")

let WATCH_NAME = "QW01s"

// MARK: - Constantes protocole
private let IQIBLA_CMD_ID: UInt16   = 0x2710
private let IQIBLA_APP_CTX: UInt32  = 0x6A048034
private let IQIBLA_DIR_SEND: UInt8  = 0x21
private let IQIBLA_CMD_NOTIF_TITLE: UInt8  = 0x36
private let IQIBLA_CMD_NOTIF_FULL:  UInt8  = 0x46

class BLEManager: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {

    @Published var isConnected      = false
    @Published var isScanning       = false
    @Published var notificationsEnabled = false
    @Published var logs: [String]   = []

    private var centralManager:      CBCentralManager!
    private var watchPeripheral:     CBPeripheral?
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

    @objc func handleAppNotification(_ notification: Foundation.Notification) {
        guard let userInfo = notification.userInfo,
              let appName = userInfo["appName"] as? String,
              let title   = userInfo["title"]   as? String,
              let body    = userInfo["body"]    as? String else { return }
        
        sendNotificationToWatch(appName: appName, title: title, body: body)
    }

    // MARK: - BLE Methods (inchangés)
    func startScanning() { /* ... ton code existant ... */ }
    func disconnect() { /* ... ton code existant ... */ }
    
    // (Je garde tes autres fonctions CBCentralManagerDelegate et CBPeripheralDelegate telles quelles)
    // Copie-colle ici tout le code que tu avais pour ces parties si besoin.

    // MARK: - Nettoyage amélioré pour accents + emojis
    func cleanForWatchImproved(_ text: String) -> String {
        var result = text
        
        let accentMap: [Character: String] = [
            "é": "e", "è": "e", "ê": "e", "ë": "e",
            "à": "a", "â": "a", "ä": "a", "á": "a",
            "î": "i", "ï": "i", "í": "i",
            "ô": "o", "ö": "o", "ó": "o",
            "ù": "u", "û": "u", "ü": "u",
            "ç": "c", "ñ": "n",
            "É": "E", "È": "E", "Ê": "E",
            "À": "A", "Â": "A", "Ô": "O", "Ù": "U", "Ç": "C",
            "\u{2019}": "'", "\u{201C}": "\"", "\u{201D}": "\""
        ]
        
        for (key, value) in accentMap {
            result = result.replacingOccurrences(of: String(key), with: value)
        }
        
        // Supprime les emojis
        result = result.replacingOccurrences(of: #"\p{Emoji}"#, with: " ", options: .regularExpression)
        
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Envoi Notification (version améliorée)
    func sendNotificationToWatch(appName: String, title: String, body: String) {
        guard isConnected, let peripheral = watchPeripheral, let char = writeCharacteristic else {
            addLog("⚠️ Montre non connectée")
            return
        }

        let cleanTitle = cleanForWatchImproved(title)
        let cleanBody  = cleanForWatchImproved(body)
        
        // Encodage GBK (le plus compatible avec ces montres)
        let titleData = cleanTitle.data(using: .gbk, allowLossyConversion: true) ?? cleanTitle.data(using: .utf8)!
        let bodyData  = cleanBody.data(using: .gbk, allowLossyConversion: true) ?? cleanBody.data(using: .utf8)!
        
        let titleBytes  = Array(titleData.prefix(40))
        let bodyBytes   = Array(bodyData.prefix(80))
        let bundleBytes = Array(bundleID(for: appName).utf8.prefix(31))

        let hasBody = !body.isEmpty
        let cmd: UInt8 = hasBody ? IQIBLA_CMD_NOTIF_FULL : IQIBLA_CMD_NOTIF_TITLE

        let tsMs = UInt32(Date().timeIntervalSince1970 * 1000) & 0x0FFFFFFF

        var payload: [UInt8] = []
        payload += [0xCD, 0x27, 0x10]
        payload += [0xCE] + withUnsafeBytes(of: tsMs.bigEndian, { Array($0) })
        payload += [0x00]
        payload += [0xCE, 0x6A, 0x04, 0x80, 0x34]
        payload += [0x00]
        
        payload += [0xA0 | UInt8(titleBytes.count)] + titleBytes
        
        if hasBody {
            payload += [0xA0 | UInt8(bodyBytes.count)] + bodyBytes
        }
        
        payload += [0x01]
        payload += [0xA0 | UInt8(bundleBytes.count)] + bundleBytes
        payload += [0xCE, 0x6A, 0x04, 0x80, 0x34]
        payload += [0x00, 0x00, 0x00, 0x00]

        let innerLen = UInt32(payload.count)
        let (lo, hi) = nextSeq()

        var packet: [UInt8] = [lo, hi, IQIBLA_DIR_SEND, cmd]
        packet += [UInt8(innerLen & 0xFF), UInt8((innerLen >> 8) & 0xFF),
                   UInt8((innerLen >> 16) & 0xFF), UInt8((innerLen >> 24) & 0xFF)]
        packet += payload

        writeToWatch(bytes: packet)
        addLog("🔔 [\(appName)] \(cleanTitle)")
    }

    // MARK: - Autres fonctions existantes (à garder)
    private func nextSeq() -> (lo: UInt8, hi: UInt8) {
        seqCounter &+= 1
        return (lo: UInt8(seqCounter & 0xFF), hi: UInt8((seqCounter >> 8) & 0xFF))
    }

    func writeToWatch(bytes: [UInt8]) {
        guard let peripheral = watchPeripheral, let char = writeCharacteristic else { return }
        let data = Data(bytes)
        peripheral.writeValue(data, for: char, type: .withoutResponse)
    }

    func bundleID(for appName: String) -> String {
        let lower = appName.lowercased()
        switch true {
        case lower.contains("whatsapp"): return "com.whatsapp"
        case lower.contains("telegram"): return "org.telegram.TelegramSE"
        case lower.contains("message"), lower.contains("sms"): return "com.apple.MobileSMS"
        case lower.contains("mail"): return "com.apple.mobilemail"
        default: return "com.apple.generic"
        }
    }

    func sendTestNotification() {
        sendNotificationToWatch(appName: "Test", title: "Test Accents", body: "Bonjour ça va ? éèàçù îï ôö")
    }
}
