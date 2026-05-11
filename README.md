# IQNotify — App custom pour montre iqibla QW01s

## Description
App iOS qui se connecte à ta montre iqibla QW01s via BLE et relaie TOUTES les notifications sans restriction (Discord, WhatsApp, Mail, etc.)

## Fichiers
- `IQNotifyApp.swift` — Point d'entrée de l'app
- `ContentView.swift` — Interface utilisateur
- `BLEManager.swift` — Gestion BLE et connexion à la montre
- `NotificationInterceptor.swift` — Interception de toutes les notifications iOS
- `Info.plist` — Permissions et configuration

## Comment compiler et installer

### Prérequis
- Xcode 15+ sur Mac (ou via PC avec SideStore)
- Apple ID gratuit

### Étapes Xcode
1. Crée un nouveau projet Xcode → App → SwiftUI
2. Remplace les fichiers générés par ceux-ci
3. Dans les entitlements du projet, active :
   - `bluetooth-central` background mode
   - `remote-notification` background mode
4. Signe avec ton Apple ID gratuit
5. Archive → IPA → installe via SideStore

### Via SideStore directement
1. Compile le projet → Archive → Share → IPA
2. Transfère l'IPA sur ton iPhone (AirDrop ou iCloud)
3. Ouvre SideStore → + → sélectionne l'IPA
4. Lance l'app et connecte la montre

## UUIDs de la montre QW01s-5C4F
- Service principal : `AE30`
- Write (commandes) : `AE01`
- Notify (réponses) : `AE02`
- Write secondaire : `AE03`
- Notify secondaire : `AE04`

## Apps supportées
- WhatsApp ✅
- Discord ✅
- Messages ✅
- Mail ✅
- Telegram ✅
- Instagram ✅
- Twitter/X ✅
- Facebook ✅
- Gmail ✅
- Outlook ✅
- Snapchat ✅
- Et toutes les autres apps via l'ID générique 0x0F

## Note technique
Le protocole AE30 d'iqibla n'est pas documenté publiquement.
L'app tente plusieurs formats de paquets connus sur les montres chinoises similaires.
Si les notifications n'apparaissent pas sur la montre, le format exact devra être ajusté
une fois qu'on aura capturé le trafic réel via HCI Snoop Log Android.
