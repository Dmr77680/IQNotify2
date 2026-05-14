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

    private var seqCounter: UInt16 = 0x6A47

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
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            self.startScanning()
        }
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
                addLog("✅ Characteristic Write prête")
            }
        }
    }

    // MARK: - Nettoyage texte
    private func cleanText(_ text: String) -> String {
        var result = text
        let map = ["é":"e","è":"e","ê":"e","ë":"e","à":"a","â":"a","ä":"a","î":"i","ï":"i",
                   "ô":"o","ö":"o","ù":"u","û":"u","ü":"u","ç":"c","É":"E","È":"E","Ê":"E",
                   "À
