import Foundation
import UserNotifications

class NotificationInterceptor: NSObject, UNUserNotificationCenterDelegate {
    
    static let shared = NotificationInterceptor()
    private var bleManager: BLEManager?
    
    func setup(bleManager: BLEManager) {
        self.bleManager = bleManager
        UNUserNotificationCenter.current().delegate = self
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        relayNotification(notification.request)
        completionHandler([.banner, .sound, .badge])
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        completionHandler()
    }
    
    private func relayNotification(_ request: UNNotificationRequest) {
        let content = request.content
        let appName = extractAppName(from: request)
        let title = content.title.isEmpty ? appName : content.title
        let body = content.body
        
        guard !body.isEmpty else { return }
        
        NotificationCenter.default.post(
            name: NSNotification.Name("NewNotificationReceived"),
            object: nil,
            userInfo: [
                "appName": appName,
                "title": title,
                "body": body
            ]
        )
    }
    
    private func extractAppName(from request: UNNotificationRequest) -> String {
        let bundleID = request.content.userInfo["bundle_id"] as? String ?? ""
        
        let knownApps: [String: String] = [
            "net.whatsapp": "WhatsApp",
            "com.hammerandchisel.discord": "Discord",
            "com.apple.MobileSMS": "Messages",
            "com.apple.mobilemail": "Mail",
            "org.telegram.TelegramSE": "Telegram",
            "com.burbn.instagram": "Instagram",
            "com.atebits.Tweetie2": "Twitter",
            "com.facebook.Facebook": "Facebook",
            "com.google.Gmail": "Gmail",
            "com.microsoft.Outlook": "Outlook",
            "com.snapchat.snapchat": "Snapchat",
            "com.tiktok.TikTok": "TikTok",
            "com.linkedin.LinkedIn": "LinkedIn",
        ]
        
        for (key, name) in knownApps {
            if bundleID.contains(key) { return name }
        }
        
        return request.content.categoryIdentifier.isEmpty ? "App" : request.content.categoryIdentifier
    }
}
