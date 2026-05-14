import Foundation
import CoreBluetooth
import UserNotifications

// MARK: - UUIDs
let SERVICE_AE30    = CBUUID(string: "AE30")
let CHAR_AE01_WRITE = CBUUID(string: "AE01")
let CHAR_AE02_NOTIFY = CBUUID(string: "AE02")

let WATCH_NAME = "QW01s"

class BLEManager: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {

    @Published var isConnected = false
    @Published var isScanning = false
    @Published var logs: [String] = []

    private var centralManager: CBCentralManager!
    private var watchPeripheral: CBPeripheral?
    private var writeCharacteristic: CBCharacteristic?

    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }

    func addLog(_ message: String) {
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        DispatchQueue.main.async {
            self.logs.append("[\(timestamp)] \(message)")
            if self.logs.count > 100 { self.logs.removeFirst() }
        }
    }

    // MARK: - Scanning
    func startScanning() {
        guard centralManager.state == .poweredOn else { return }
        centralManager.scanForPeripherals(withServices: nil, options: nil)
        isScanning = true
    }

    // MARK: - Delegates
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            addLog("✅ Bluetooth activé")
            startScanning()
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        guard let name = peripheral.name, name.contains(WATCH_NAME) else { return }
        addLog("📡 Montre trouvée")
        central.stopScan()
        isScanning = false
        watchPeripheral = peripheral
        peripheral.delegate = self
        central.connect(peripheral)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        addLog("✅ Connecté")
        isConnected = true
        peripheral.discoverServices([SERVICE_AE30])
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        addLog("🔌 Déconnecté")
        isConnected = false
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        for service in services {
            peripheral.discoverCharacteristics([CHAR_AE01_WRITE], for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let chars = service.characteristics else { return }
        for char in chars {
            if char.uuid == CHAR_AE01_WRITE {
                writeCharacteristic = char
                addLog("✅ Write Characteristic prête")
            }
        }
    }

    // MARK: - Nettoyage texte (accents)
    private func cleanText(_ text: String) -> String {
        var result = text
        let map = ["é":"e","è":"e","ê":"e","ë":"e","à":"a","â":"a","ä":"a","î":"i","ï":"i",
                   "ô":"o","ö":"o","ù":"u","û":"u","ü":"u","ç":"c",
                   "É":"E","È":"E","Ê":"E","À":"A","Â":"A","Ô":"O","Ù":"U","Ç":"C"]
        for (k, v) in map {
            result = result.replacingOccurrences(of: k, with: v)
        }
        result = result.replacingOccurrences(of: #"\p{Emoji}"#, with: " ", options: .regularExpression)
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Envoi simple
    func sendNotificationToWatch(appName: String, title: String, body: String) {
        guard let peripheral = watchPeripheral, let char = writeCharacteristic else { return }

        let cleanTitle = cleanText(title)
        let cleanBody = cleanText(body)
        let full = "\(cleanTitle): \(cleanBody)"
        
        guard let data = full.data(using: .gbk, allowLossyConversion: true) else { return }

        var packet = Data([0x02, 0x00, 0x02, 0x51, 0x00, UInt8(data.count + 30), 0x00, 0x04, 0x00, 0x52, 0x82, 0x00])
        packet.append(data)

        while packet.count < 75 {
            packet.append(0x00)
        }

        var checksum: UInt8 = 0
        for byte in packet {
            checksum ^= byte
        }
        packet.append(checksum)

        peripheral.writeValue(packet, for: char, type: .withoutResponse)
        addLog("🔔 [\(appName)] \(cleanTitle)")
    }

    func sendTestNotification() {
        sendNotificationToWatch(appName: "Test", title: "Test", body: "Bonjour ça va ? éèàçù îï")
    }
}
