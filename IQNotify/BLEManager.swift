import Foundation
import CoreBluetooth
import UserNotifications

// MARK: - UUIDs réels de la montre iqibla QW01s-5C4F (confirmés par HCI log)
let SERVICE_AE30        = CBUUID(string: "AE30")
let CHAR_AE01_WRITE     = CBUUID(string: "AE01")  // handle ATT 0x0082 — Write Without Response
let CHAR_AE02_NOTIFY    = CBUUID(string: "AE02")  // handle ATT 0x0084 — Notify

let WATCH_NAME = "QW01s"

// MARK: - Constantes protocole iqibla (décodées depuis btsnoop_hci.log)
private let IQIBLA_CMD_ID: UInt16   = 0x2710          // ID fixe de toutes les commandes
private let IQIBLA_APP_CTX: UInt32  = 0x6A048034      // Contexte applicatif fixe
private let IQIBLA_DIR_SEND: UInt8  = 0x21            // Direction HOST → MONTRE
private let IQIBLA_CMD_NOTIF_TITLE: UInt8  = 0x36     // Notification titre seul
private let IQIBLA_CMD_NOTIF_FULL:  UInt8  = 0x46     // Notification titre + corps

class BLEManager: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {

    @Published var isConnected      = false
    @Published var isScanning       = false
    @Published var notificationsEnabled = false
    @Published var logs: [String]   = []

    private var centralManager:      CBCentralManager!
    private var watchPeripheral:     CBPeripheral?
    private var writeCharacteristic: CBCharacteristic?   // AE01 handle 0x0082
    private var notifyCharacteristic: CBCharacteristic?  // AE02 handle 0x0084

    // Compteur de séquence — incrémenté à chaque paquet envoyé
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
        if Thread.isMainThread {
            logs.append(line)
            if logs.count > 100 { logs.removeFirst() }
        } else {
            DispatchQueue.main.async {
                self.logs.append(line)
                if self.logs.count > 100 { self.logs.removeFirst() }
            }
        }
    }

    // MARK: - Permission notifications
    func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
            DispatchQueue.main.async {
                self.notificationsEnabled = granted
                self.addLog(granted ? "✅ Notifications accordées" : "❌ Notifications refusées")
            }
        }
    }

    // MARK: - Observer notifications système
    func setupNotificationObserver() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppNotification(_:)),
            name: NSNotification.Name("NewNotificationReceived"),
            object: nil
        )
    }

    @objc func handleAppNotification(_ notification: Foundation.Notification) {
        guard let userInfo  = notification.userInfo,
              let appName   = userInfo["appName"] as? String,
              let title     = userInfo["title"]   as? String,
              let body      = userInfo["body"]    as? String else { return }
        sendNotificationToWatch(appName: appName, title: title, body: body)
    }

    // MARK: - BLE Scanning
    func startScanning() {
        guard centralManager.state == .poweredOn else {
            addLog("⚠️ Bluetooth non disponible")
            return
        }
        addLog("🔍 Recherche de QW01s...")
        DispatchQueue.main.async { self.isScanning = true }
        centralManager.scanForPeripherals(withServices: nil,
                                          options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) {
            if !self.isConnected {
                self.centralManager.stopScan()
                DispatchQueue.main.async { self.isScanning = false }
                self.addLog("⏱ Scan terminé — montre non trouvée")
            }
        }
    }

    func disconnect() {
        if let p = watchPeripheral { centralManager.cancelPeripheralConnection(p) }
    }

    // MARK: - CBCentralManagerDelegate
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:  addLog("✅ Bluetooth activé")
        case .poweredOff: addLog("❌ Bluetooth désactivé")
        default: break
        }
    }

    func centralManager(_ central: CBCentralManager,
                        didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any],
                        rssi RSSI: NSNumber) {
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

        // Handshake ACKBAOS après 1 seconde (confirmé dans le log)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.sendHandshake()
        }
    }

    func centralManager(_ central: CBCentralManager,
                        didDisconnectPeripheral peripheral: CBPeripheral,
                        error: Error?) {
        addLog("🔌 Déconnecté")
        DispatchQueue.main.async {
            self.isConnected = false
            self.writeCharacteristic  = nil
            self.notifyCharacteristic = nil
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            self.addLog("🔄 Reconnexion...")
            self.startScanning()
        }
    }

    func centralManager(_ central: CBCentralManager,
                        didFailToConnect peripheral: CBPeripheral,
                        error: Error?) {
        addLog("❌ Échec connexion : \(error?.localizedDescription ?? "inconnu")")
        DispatchQueue.main.async { self.isConnected = false }
    }

    // MARK: - CBPeripheralDelegate
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        for service in services {
            addLog("🔧 Service : \(service.uuid)")
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didDiscoverCharacteristicsFor service: CBService,
                    error: Error?) {
        guard let chars = service.characteristics else { return }
        for char in chars {
            switch char.uuid {
            case CHAR_AE01_WRITE:
                writeCharacteristic = char
                addLog("   ✅ AE01 (écriture) prêt — handle 0x0082")
            case CHAR_AE02_NOTIFY:
                notifyCharacteristic = char
                peripheral.setNotifyValue(true, for: char)
                addLog("   ✅ AE02 (notifications) activé — handle 0x0084")
            default:
                // Activer les notifications sur toutes les autres caractéristiques notify/indicate
                if char.properties.contains(.notify) || char.properties.contains(.indicate) {
                    peripheral.setNotifyValue(true, for: char)
                }
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didUpdateValueFor characteristic: CBCharacteristic,
                    error: Error?) {
        guard let data = characteristic.value else { return }
        let hex = data.map { String(format: "%02X", $0) }.joined(separator: " ")
        addLog("📥 \(characteristic.uuid): \(hex)")

        // Détecter les ACK ACKBAOS de la montre (confirmé dans le log)
        if data.count >= 11 {
            let payload = Array(data)
            // Pattern: ... 41 43 4B 42 41 4F 53 ("ACKBAOS")
            if payload.contains(0x41) {
                let ascii = data.map { ($0 >= 32 && $0 < 127) ? String(UnicodeScalar($0)) : "." }.joined()
                if ascii.contains("ACKBAOS") {
                    addLog("🤝 Handshake ACKBAOS confirmé par la montre ✅")
                }
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didWriteValueFor characteristic: CBCharacteristic,
                    error: Error?) {
        if let error = error {
            addLog("❌ Erreur écriture : \(error.localizedDescription)")
        }
    }

    // MARK: - Compteur de séquence
    private func nextSeq() -> (lo: UInt8, hi: UInt8) {
        seqCounter &+= 1
        return (lo: UInt8(seqCounter & 0xFF), hi: UInt8((seqCounter >> 8) & 0xFF))
    }

    // MARK: - Écriture BLE bas niveau
    func writeToWatch(bytes: [UInt8]) {
        guard let peripheral = watchPeripheral,
              let char = writeCharacteristic else {
            addLog("⚠️ Montre non connectée")
            return
        }
        let data = Data(bytes)
        let hex  = bytes.prefix(16).map { String(format: "%02X", $0) }.joined(separator: " ")
        addLog("📤 \(hex)\(bytes.count > 16 ? "..." : "")")
        peripheral.writeValue(data, for: char, type: .withoutResponse)
    }

    // MARK: - Handshake réel ACKBAOS (confirmé HCI log)
    // Paquet observé : seq 0x47 dir 0x21 cmd 0x0F "ACKBAOS!x...."
    func sendHandshake() {
        let (lo, hi) = nextSeq()
        // Reproduit exactement le paquet vu dans le log
        let packet: [UInt8] = [
            lo, hi, IQIBLA_DIR_SEND,                      // seq + direction
            0x0F,                                           // CMD handshake
            0x0F, 0x00, 0x00, 0x00,                        // inner_len = 15
            0x41, 0x43, 0x4B, 0x42, 0x41, 0x4F, 0x53,    // "ACKBAOS"
            0x21,                                           // '!'
            0x78, 0xf6, 0xcc,                              // bytes fixes observés
            0x00, 0x00, 0x00                               // padding
        ]
        writeToWatch(bytes: packet)
        addLog("🤝 Handshake ACKBAOS envoyé")
    }

    // MARK: - Construction paquet notification (protocole réel iqibla)
    //
    // Structure confirmée par btsnoop_hci.log :
    // [seq_lo][seq_hi][0x21][CMD][inner_len 4B LE] + payload MessagePack :
    //   0xCD 0x27 0x10          → uint16 = 10000 (ID iqibla fixe)
    //   0xCE [uint32]           → paramètre interne (timestamp ms)
    //   0x00                    → flag
    //   0xCE 0x6A 0x04 0x80 0x34 → contexte app fixe
    //   0x00                    → séparateur
    //   [fixstr] titre          → 0xA0|len + UTF8
    //   [fixstr] corps          → 0xA0|len + UTF8 (seulement si CMD=0x46)
    //   0x01                    → flag non-lu
    //   [fixstr] bundleID       → 0xA0|len + UTF8
    //   0xCE 0x6A 0x04 0x80 0x34 → contexte app bis
    //   [4 bytes]               → CRC (on met 0x00 pour l'instant)

    func sendNotificationToWatch(appName: String, title: String, body: String) {
        guard isConnected else {
            addLog("⚠️ Montre non connectée — notification ignorée")
            return
        }
        addLog("🔔 [\(appName)] \(title)")

        let cleanTitle  = cleanForWatch(title)
        let cleanBody   = cleanForWatch(body)
        let titleBytes  = Array(cleanTitle.utf8.prefix(31))
        let bodyBytes   = Array(cleanBody.utf8.prefix(31))
        let bundleBytes = Array(bundleID(for: appName).utf8.prefix(31))

        let hasBody = !body.isEmpty
        let cmd: UInt8 = hasBody ? IQIBLA_CMD_NOTIF_FULL : IQIBLA_CMD_NOTIF_TITLE

        // Timestamp en ms (uint32) comme paramètre interne
        let tsMs = UInt32(Date().timeIntervalSince1970 * 1000) & 0x0FFFFFFF

        var payload: [UInt8] = []

        // uint16 ID iqibla : 0xCD 0x27 0x10
        payload += [0xCD, 0x27, 0x10]

        // uint32 timestamp : 0xCE + big-endian
        payload += [0xCE,
                    UInt8((tsMs >> 24) & 0xFF),
                    UInt8((tsMs >> 16) & 0xFF),
                    UInt8((tsMs >>  8) & 0xFF),
                    UInt8( tsMs        & 0xFF)]

        // flag
        payload += [0x00]

        // uint32 contexte app fixe : 0xCE 0x6A 0x04 0x80 0x34
        payload += [0xCE, 0x6A, 0x04, 0x80, 0x34]

        // séparateur
        payload += [0x00]

        // fixstr titre : 0xA0|len + bytes
        payload += [0xA0 | UInt8(titleBytes.count)] + titleBytes

        // fixstr corps (si CMD 0x46)
        if hasBody {
            payload += [0xA0 | UInt8(bodyBytes.count)] + bodyBytes
        }

        // flag non-lu
        payload += [0x01]

        // fixstr bundle ID
        payload += [0xA0 | UInt8(bundleBytes.count)] + bundleBytes

        // contexte app bis
        payload += [0xCE, 0x6A, 0x04, 0x80, 0x34]

        // CRC placeholder (4 bytes — on met 0x00, la montre semble ne pas le vérifier)
        payload += [0x00, 0x00, 0x00, 0x00]

        // inner_len = taille du payload (little-endian uint32)
        let innerLen = UInt32(payload.count)

        // Construire le paquet complet
        let (lo, hi) = nextSeq()
        var packet: [UInt8] = [lo, hi, IQIBLA_DIR_SEND, cmd]
        packet += [
            UInt8( innerLen        & 0xFF),
            UInt8((innerLen >>  8) & 0xFF),
            UInt8((innerLen >> 16) & 0xFF),
            UInt8((innerLen >> 24) & 0xFF)
        ]
        packet += payload

        writeToWatch(bytes: packet)
    }

    // MARK: - Nettoyage du texte pour la montre (ASCII uniquement)
    func cleanForWatch(_ text: String) -> String {
        let accentMap: [Character: String] = [
            "à": "a", "â": "a", "ä": "a", "á": "a", "ã": "a",
            "è": "e", "ê": "e", "ë": "e", "é": "e",
            "î": "i", "ï": "i", "í": "i", "ì": "i",
            "ô": "o", "ö": "o", "ó": "o", "ò": "o", "õ": "o",
            "û": "u", "ü": "u", "ú": "u", "ù": "u",
            "ç": "c", "ñ": "n", "ý": "y", "ÿ": "y",
            "À": "A", "Â": "A", "Ä": "A", "Á": "A",
            "È": "E", "Ê": "E", "Ë": "E", "É": "E",
            "Î": "I", "Ï": "I", "Í": "I",
            "Ô": "O", "Ö": "O", "Ó": "O",
            "Û": "U", "Ü": "U", "Ú": "U",
            "Ç": "C", "Ñ": "N",
            "\u{2019}": "'",
            "\u{201C}": "\"",
            "\u{201D}": "\"",
            "\u{2013}": "-",
            "\u{2014}": "-",
            "\u{2026}": "...",
        ]
        var result = ""
        for char in text {
            if let replacement = accentMap[char] {
                result += replacement
            } else if char.isASCII {
                result.append(char)
            }
            // Emojis et caractères non-ASCII supprimés
        }
        return result
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Bundle IDs réels (confirmés dans le log : "com.whatsapp")
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
        case lower.contains("twitter"),
             lower.contains("x.com"):     return "com.atebits.Tweetie2"
        case lower.contains("facebook"):  return "com.facebook.Facebook"
        case lower.contains("gmail"):     return "com.google.Gmail"
        case lower.contains("outlook"):   return "com.microsoft.Outlook"
        case lower.contains("snapchat"):  return "com.snapchat.snapchat"
        case lower.contains("tiktok"):    return "com.zhiliaoapp.musically"
        case lower.contains("linkedin"):  return "com.linkedin.LinkedIn"
        default:                          return "com.apple.generic"
        }
    }

    // MARK: - Test rapide
    func sendTestNotification(appName: String) {
        sendNotificationToWatch(
            appName: appName,
            title:   appName,
            body:    "Message de test depuis IQNotify 👋"
        )
    }
}
