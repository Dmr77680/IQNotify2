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
        DispatchQueue.main.async {
            self.logs.append("[\(timestamp)] \(message)")
            if self.logs.count > 100 { self.logs.removeFirst() }
        }
    }

    // MARK: - Permission & Observer
    func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
            DispatchQueue.main.async {
                self.notificationsEnabled = granted
                self.addLog(granted ? "✅ Notifications accordées" : "❌ Notifications refusées")
            }
        }
    }

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
              let title   = userInfo["title"] as? String,
              let body    = userInfo["body"] as? String else { return }
        sendNotificationToWatch(appName: appName, title: title, body: body)
    }

    // MARK: - BLE Methods (inchangés)
    func startScanning() {
        guard centralManager.state == .poweredOn else { return }
        addLog("🔍 Recherche de QW01s...")
        DispatchQueue.main.async { self.isScanning = true }
        centralManager.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
    }

    func disconnect() {
        if let p = watchPeripheral { centralManager.cancelPeripheralConnection(p) }
    }

    // MARK: - Delegates (inchangés)
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:  addLog("✅ Bluetooth activé")
        case .poweredOff: addLog("❌ Bluetooth désactivé")
        default: break
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        guard let name = peripheral.name, name.contains(WATCH_NAME) else { return }
        addLog("📡 Montre trouvée : \(name)")
        centralManager.stopScan()
        DispatchQueue.main.async { self.isScanning = false }
        watchPeripheral = peripheral
        peripheral.delegate = self
        centralManager.connect(peripheral)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        addLog("✅ Connecté à \(peripheral.name ?? "QW01s")")
        DispatchQueue.main.async { self.isConnected = true }
        peripheral.discoverServices([SERVICE_AE30])
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { self.sendHandshake() }
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        addLog("🔌 Déconnecté")
        DispatchQueue.main.async {
            self.isConnected = false
            self.writeCharacteristic = nil
            self.notifyCharacteristic = nil
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { self.startScanning() }
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        addLog("❌ Échec connexion")
        DispatchQueue.main.async { self.isConnected = false }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        for service in services {
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let chars = service.characteristics else { return }
        for char in chars {
            switch char.uuid {
            case CHAR_AE01_WRITE:
                writeCharacteristic = char
            case CHAR_AE02_NOTIFY:
                notifyCharacteristic = char
                peripheral.setNotifyValue(true, for: char)
            default:
                if char.properties.contains(.notify) || char.properties.contains(.indicate) {
                    peripheral.setNotifyValue(true, for: char)
                }
            }
        }
    }

    // MARK: - Nettoyage amélioré + GBK
    private func cleanForWatch(_ text: String) -> String {
        var result =
