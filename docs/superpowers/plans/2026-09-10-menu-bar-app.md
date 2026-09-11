# SonyBridge barre des menus — plan d'implémentation

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal :** transformer SonyBridge (app à fenêtre SwiftUI) en app de barre des menus native, avec toutes les
fonctions existantes, les corrections WH-1000XM6, les options de connexion automatique, et un build sans Xcode.

**Architecture :** `NSStatusItem` + `NSMenu` (AppKit). Les lignes riches (en-tête, curseurs, interrupteurs,
égaliseur) sont des vues SwiftUI hébergées dans des `NSMenuItem` (`NSHostingView`). Le modèle
`HeadphonesModel` (Swift, observable) pilote le pont Obj-C++ `HeadphonesBridge`, qui pilote le cœur C++
existant. La logique pure (reconnexion, anti-retour d'affichage, limitation d'envoi, décodage des trames) est
isolée dans de petits fichiers testés par des exécutables de test.

**Tech Stack :** Swift 5 (mode de langage), SwiftUI, AppKit, Combine, IOBluetooth, ServiceManagement ;
C++17 et Obj-C++ (ARC) ; build `swiftc` + `clang++` via `scripts/build.sh` et `Makefile` ; Python 3 (vérif. des
traductions).

**Spec :** `docs/superpowers/specs/2026-09-10-menu-bar-app-design.md`

## Global Constraints

- macOS minimum : **13.0** (`LSMinimumSystemVersion`, cible `<arch>-apple-macos13.0`).
- Pas de Xcode : tout se compile avec les Command Line Tools (`make`, `make test`, `make run`, `make release`).
- Swift compilé avec `-swift-version 5` ; C++ en `-std=c++17` ; Obj-C++ avec `-fobjc-arc`.
- Bundle : `SonyBridge.app`, exécutable `SonyBridge`, identifiant **`com.semvis123.SonyHeadphonesClient`**
  (inchangé), `LSUIElement = YES`.
- Textes : **tout texte affiché** passe par `tr("…")` en Swift ou `NSLocalizedString(@"…", nil)` en Obj-C++,
  avec la clé en anglais et sa traduction dans `Client/macos/fr.lproj/Localizable.strings`. Pas de texte affiché
  en dur ailleurs. `make test` le vérifie (à partir de la tâche 2).
- Sécurité XM6 : **ne jamais envoyer au casque une commande dont le format n'est pas vérifié** (spec §7). En
  particulier, aucune écriture d'égaliseur sur la disposition 10 bandes avant la tâche 8.
- Git : c'est **l'utilisateur** qui committe. À chaque étape « Commit », afficher la commande proposée et
  attendre qu'il la lance.
- Test matériel : l'agent ne voit pas l'écran. Chaque vérification visuelle est demandée à l'utilisateur, avec
  une liste précise de choses à regarder. Les échanges avec le casque se lisent dans `build/app.log`
  (`make run DEBUG=1`).

## Carte des fichiers

| Fichier | Tâche | Responsabilité |
|---|---|---|
| `scripts/build.sh` | 1 | Compile et assemble `build/SonyBridge.app` |
| `scripts/test.sh` | 2 | Compile et lance les exécutables de test + vérif. des traductions |
| `scripts/check_localization.py` | 2 | Chaque clé `tr()` a sa traduction, aucune traduction inutilisée |
| `Makefile` | 1, 2 | `make`, `run`, `test`, `release`, `clean` |
| `.github/workflows/build.yml` | 1, 2 | CI : tests + build universel |
| `Client/macos/info.plist` | 1 | App d'agent, macOS 13, nom SonyBridge |
| `Client/macos/Resources/AppIcon.iconset/` | 1 | Icône de l'app (compilée par `iconutil`) |
| `Client/macos/SonyBridgeApp.swift` | 1 | Point d'entrée `@main` |
| `Client/macos/AppDelegate.swift` | 1, 7 | Assemble modèle, réglages, surveillance Bluetooth, icône de barre |
| `Client/macos/Localization.swift` | 1 | `tr(_:)` |
| `Client/macos/MenuSupport.swift` | 1, 5, 6 | `ActionMenuItem`, `sectionHeader`, `hostingMenuItem`, `MenuMetrics`, `titleWithValue` |
| `Client/macos/StatusItemController.swift` | 1, 4, 7 | L'icône de la barre et son menu |
| `Client/macos/StatusIcon.swift` | 6 | Choix du symbole selon le mode |
| `Client/macos/HeadphonesMenu.swift` | 1, 6, 7, 8 | Construit le `NSMenu` et le synchronise avec le modèle |
| `Client/macos/MenuRows/*.swift` | 5 | `HeaderRow`, `AmbientLevelRow`, `ToggleRow`, `EqualizerRow` |
| `Client/macos/HeadphonesModel.swift` | 4, 7, 8 | État observable + actions + minuteurs + reconnexion |
| `Client/macos/ReconnectPolicy.swift` | 2 | Délais de reconnexion |
| `Client/macos/PollGuard.swift` | 2 | Ignore les relectures 3 s après un changement |
| `Client/macos/SendThrottle.swift` | 2 | Limite les envois des curseurs à 1 / 150 ms |
| `Client/macos/AppSettings.swift` | 7 | Les 3 options + lancement à l'ouverture de session |
| `Client/macos/DeviceWatcher.swift` | 7 | Connexions / déconnexions Bluetooth de macOS |
| `Client/macos/HeadphonesBridge.h/.mm` | 3, 4, 7, 8 | Pont Obj-C++ |
| `Client/ProtocolParsers.h/.cpp` | 3, 8 | Décodage / encodage purs des trames |
| `Client/Headphones.h/.cpp` | 3, 8 | Utilise `ProtocolParsers`, canal NC `0x19` |
| `Client/tests/LogicTests/main.swift` | 2 | Tests de la logique Swift |
| `Client/tests/ProtocolParsersTests.cpp` | 3, 8 | Tests du décodage avec les trames réelles |
| `Client/macos/fr.lproj/Localizable.strings` | toutes | Traductions |
| `README.md` | 1, 9 | Build, description |

**Supprimés en tâche 1 :** `Client/macos/{main.mm, AppDelegate.h, AppDelegate.mm, ViewController.h,
ViewController.mm, Main.storyboard, ContentView.swift, exportOptions.plist}`,
`Client/macos/SonyHeadphonesClient.xcodeproj/`, `Client/macos/Assets.xcassets/`,
`.github/workflows/xcodebuild.yml`.

---

### Task 1: Build par script + app d'agent avec un menu minimal

Remplace le projet Xcode et la fenêtre par un build en ligne de commande et une icône de barre des menus. Le
menu minimal contient l'en-tête, les trois modes, Connecter/Déconnecter et Quitter. Il utilise le modèle
**existant** (`HeadphonesModel` actuel, avec `connected`, `connecting`, `mode`, `setMode`, `connect`, `disconnect`).

**Files:**
- Create: `scripts/build.sh`, `Makefile`, `.github/workflows/build.yml`
- Create: `Client/macos/SonyBridgeApp.swift`, `Client/macos/AppDelegate.swift`, `Client/macos/Localization.swift`,
  `Client/macos/MenuSupport.swift`, `Client/macos/StatusItemController.swift`, `Client/macos/HeadphonesMenu.swift`
- Create: `Client/macos/Resources/AppIcon.iconset/*.png` (copiés depuis `Assets.xcassets`)
- Modify: `Client/macos/info.plist`, `Client/macos/fr.lproj/Localizable.strings`, `README.md` (section build)
- Delete: la liste « Supprimés en tâche 1 » ci-dessus

**Interfaces:**
- Consumes : `HeadphonesModel` actuel (`@Published connected/connecting/mode/deviceName/batteryLevel`,
  `connect()`, `disconnect()`, `setMode(_:)`), `SHCAmbientMode` (`.off/.noiseCanceling/.ambientSound`).
- Produces :
  - `func tr(_ key: String) -> String`
  - `final class ActionMenuItem: NSMenuItem { init(_ title: String, key: String = "", handler: @escaping () -> Void) }`
  - `func sectionHeader(_ title: String) -> NSMenuItem`
  - `final class StatusItemController { init(model: HeadphonesModel) }`
  - `final class HeadphonesMenu { let menu: NSMenu; init(model: HeadphonesModel) }`
  - commandes `make`, `make run [DEBUG=1]`, `make release`, `make clean` ; app dans `build/SonyBridge.app`

- [ ] **Step 1 : Copier l'icône dans un `.iconset`, puis supprimer les anciens fichiers**

```bash
S=Client/macos/Assets.xcassets/AppIcon.appiconset; D=Client/macos/Resources/AppIcon.iconset
mkdir -p "$D"
for s in 16 32 128 256 512; do
  cp "$S/icon_$s.png" "$D/icon_${s}x${s}.png"
  cp "$S/icon_$((s*2)).png" "$D/icon_${s}x${s}@2x.png"
done
ls "$D" | wc -l   # attendu : 10
git rm -r -q Client/macos/main.mm Client/macos/AppDelegate.h Client/macos/AppDelegate.mm \
  Client/macos/ViewController.h Client/macos/ViewController.mm Client/macos/Main.storyboard \
  Client/macos/ContentView.swift Client/macos/exportOptions.plist \
  Client/macos/SonyHeadphonesClient.xcodeproj Client/macos/Assets.xcassets .github/workflows/xcodebuild.yml
```

- [ ] **Step 2 : Écrire `scripts/build.sh`** (puis `chmod +x scripts/build.sh`)

`/bin/bash` sur macOS est la version 3.2 : pas de tableau vide avec `set -u`, d'où les options passées en chaînes.

```bash
#!/bin/bash
# Builds build/SonyBridge.app with the Command Line Tools only (no Xcode needed).
#   CONFIG=debug|release (default: debug)
#   ARCHS="arm64 x86_64"  (default: this Mac's architecture; several = universal binary via lipo)
#   DEBUG_PROTOCOL=1      (hex-dumps every frame exchanged with the headphones to stderr)
set -euo pipefail
shopt -s nullglob

ROOT=$(cd "$(dirname "$0")/.." && pwd)
CORE=$ROOT/Client
MAC=$CORE/macos
OUT=$ROOT/build
APP=$OUT/SonyBridge.app
SDK=$(xcrun --show-sdk-path)
CONFIG=${CONFIG:-debug}
ARCHS=${ARCHS:-$(uname -m)}
MIN_MACOS=13.0

if [ "$CONFIG" = release ]; then SWIFT_OPT="-O"; CXX_OPT="-O2"; else SWIFT_OPT="-Onone -g"; CXX_OPT="-O0 -g"; fi
SWIFT_DEFINES=""; CXX_DEFINES=""
if [ "${DEBUG_PROTOCOL:-0}" = 1 ]; then SWIFT_DEFINES="-D DEBUG_PROTOCOL"; CXX_DEFINES="-DSHC_DEBUG_PROTOCOL"; fi

SWIFT_SOURCES=("$MAC"/*.swift "$MAC"/MenuRows/*.swift)
CXX_SOURCES=("$CORE"/*.cpp)
OBJCXX_SOURCES=("$MAC"/*.mm)

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
BINARIES=""

for ARCH in $ARCHS; do
    OBJ=$OUT/obj/$CONFIG-$ARCH
    rm -rf "$OBJ"; mkdir -p "$OBJ"
    TARGET=$ARCH-apple-macos$MIN_MACOS
    CXXFLAGS="-target $TARGET -isysroot $SDK -std=c++17 $CXX_OPT $CXX_DEFINES -I $CORE -I $MAC"

    echo "== [$ARCH] Swift"
    swiftc -target "$TARGET" -sdk "$SDK" -swift-version 5 $SWIFT_OPT $SWIFT_DEFINES -wmo -parse-as-library \
        -module-name SonyBridge \
        -import-objc-header "$MAC/SonyHeadphonesClient-Bridging-Header.h" -I "$MAC" -I "$CORE" \
        -c "${SWIFT_SOURCES[@]}" -o "$OBJ/swift.o"

    echo "== [$ARCH] C++"
    for f in "${CXX_SOURCES[@]}"; do clang++ $CXXFLAGS -c "$f" -o "$OBJ/$(basename "$f" .cpp).o"; done

    echo "== [$ARCH] Obj-C++"
    for f in "${OBJCXX_SOURCES[@]}"; do
        clang++ $CXXFLAGS -fobjc-arc -fmodules -fcxx-modules -c "$f" -o "$OBJ/$(basename "$f" .mm).o"
    done

    echo "== [$ARCH] Link"
    swiftc -target "$TARGET" -sdk "$SDK" "$OBJ"/*.o -o "$OBJ/SonyBridge" -lc++ \
        -framework AppKit -framework SwiftUI -framework Combine -framework IOBluetooth \
        -framework IOBluetoothUI -framework ServiceManagement
    BINARIES="$BINARIES $OBJ/SonyBridge"
done

lipo -create $BINARIES -output "$APP/Contents/MacOS/SonyBridge"

echo "== Resources"
cp "$MAC/info.plist" "$APP/Contents/Info.plist"
cp -R "$MAC"/*.lproj "$APP/Contents/Resources/"
iconutil -c icns "$MAC/Resources/AppIcon.iconset" -o "$APP/Contents/Resources/AppIcon.icns"

echo "== Sign (ad-hoc)"
codesign --force --sign - --entitlements "$MAC/SonyHeadphonesClient.entitlements" "$APP"
echo "OK -> $APP"
```

- [ ] **Step 3 : Écrire le `Makefile`**

```make
# SonyBridge — build without Xcode. See scripts/build.sh for the knobs.
DEBUG ?= 0

.PHONY: all build run release clean

all: build

build:
	DEBUG_PROTOCOL=$(DEBUG) ./scripts/build.sh

run: build
	-pkill -x SonyBridge
	open --stdout build/app.log --stderr build/app.log build/SonyBridge.app

release:
	CONFIG=release ARCHS="arm64 x86_64" ./scripts/build.sh
	cd build && rm -f SonyBridge.zip && ditto -c -k --keepParent SonyBridge.app SonyBridge.zip

clean:
	rm -rf build
```

- [ ] **Step 4 : Écrire `.github/workflows/build.yml`** (la tâche 2 y ajoutera `make test`)

```yaml
name: macOS

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  build:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v4
      - name: Build (release, universal)
        run: make release
      - uses: actions/upload-artifact@v4
        with:
          name: SonyBridge-macOS
          path: build/SonyBridge.zip
```

- [ ] **Step 5 : Réécrire `Client/macos/info.plist`**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>en</string>
	<key>CFBundleLocalizations</key>
	<array>
		<string>en</string>
		<string>fr</string>
	</array>
	<key>CFBundleExecutable</key>
	<string>SonyBridge</string>
	<key>CFBundleIdentifier</key>
	<string>com.semvis123.SonyHeadphonesClient</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>SonyBridge</string>
	<key>CFBundleDisplayName</key>
	<string>SonyBridge</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>0.5.0</string>
	<key>CFBundleVersion</key>
	<string>1</string>
	<key>CFBundleIconFile</key>
	<string>AppIcon</string>
	<key>LSApplicationCategoryType</key>
	<string>public.app-category.utilities</string>
	<key>LSMinimumSystemVersion</key>
	<string>13.0</string>
	<key>LSUIElement</key>
	<true/>
	<key>NSHighResolutionCapable</key>
	<true/>
	<key>NSBluetoothAlwaysUsageDescription</key>
	<string>This app uses Bluetooth in order to connect to your headphones.</string>
	<key>NSPrincipalClass</key>
	<string>NSApplication</string>
</dict>
</plist>
```

Run : `plutil -lint Client/macos/info.plist` → `OK`.

- [ ] **Step 6 : Écrire les fichiers Swift de base**

`Client/macos/SonyBridgeApp.swift` :

```swift
import AppKit

// Entry point: a menu bar-only app (LSUIElement), no window and no Dock icon.
@main
enum SonyBridgeApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
}
```

`Client/macos/AppDelegate.swift` :

```swift
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = HeadphonesModel()
    private var statusItemController: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItemController = StatusItemController(model: model)
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.disconnect()
    }
}
```

`Client/macos/Localization.swift` :

```swift
import Foundation

// Looks up a UI string in Localizable.strings. Every user-facing string goes through this (checked by make test).
func tr(_ key: String) -> String {
    NSLocalizedString(key, comment: "")
}
```

`Client/macos/MenuSupport.swift` :

```swift
import AppKit

// A menu item that runs a closure (NSMenuItem only supports target/selector natively).
final class ActionMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(_ title: String, key: String = "", handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(fire), keyEquivalent: key)
        target = self
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    @objc private func fire() {
        handler()
    }
}

// A small grey, non-clickable title above a group of items (like "Contrôle du son ambiant").
func sectionHeader(_ title: String) -> NSMenuItem {
    let item = NSMenuItem()
    item.attributedTitle = NSAttributedString(string: title, attributes: [
        .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize, weight: .semibold),
        .foregroundColor: NSColor.secondaryLabelColor,
    ])
    item.isEnabled = false
    return item
}
```

`Client/macos/StatusItemController.swift` (icône provisoire ; la tâche 6 ajoute `StatusIcon`) :

```swift
import AppKit
import Combine

// Owns the menu bar icon and attaches the headphones menu to it.
final class StatusItemController {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let headphonesMenu: HeadphonesMenu
    private var cancellables = Set<AnyCancellable>()

    init(model: HeadphonesModel) {
        headphonesMenu = HeadphonesMenu(model: model)
        statusItem.menu = headphonesMenu.menu
        let image = NSImage(systemSymbolName: "headphones", accessibilityDescription: "SonyBridge")
        image?.isTemplate = true
        statusItem.button?.image = image
        model.$connected
            .receive(on: DispatchQueue.main)
            .sink { [weak self] connected in self?.statusItem.button?.appearsDisabled = !connected }
            .store(in: &cancellables)
    }
}
```

`Client/macos/HeadphonesMenu.swift` (version minimale, remplacée entièrement en tâche 6) :

```swift
import AppKit
import Combine

// The status item's menu. Minimal for now: header, modes, connect/disconnect, quit.
final class HeadphonesMenu {
    let menu = NSMenu()
    private let model: HeadphonesModel
    private var cancellables = Set<AnyCancellable>()
    private let headerItem = NSMenuItem()
    private var modeItems: [(SHCAmbientMode, NSMenuItem)] = []
    private var connectItem: ActionMenuItem!

    init(model: HeadphonesModel) {
        self.model = model
        menu.autoenablesItems = false

        headerItem.isEnabled = false
        menu.addItem(headerItem)
        menu.addItem(.separator())

        menu.addItem(sectionHeader(tr("Ambient Sound Control")))
        let modes: [(SHCAmbientMode, String)] = [
            (.noiseCanceling, tr("Noise Canceling")), (.ambientSound, tr("Ambient Sound")), (.off, tr("Off")),
        ]
        for (mode, title) in modes {
            let item = ActionMenuItem(title) { [weak model] in model?.setMode(mode) }
            modeItems.append((mode, item))
            menu.addItem(item)
        }
        menu.addItem(.separator())

        connectItem = ActionMenuItem(tr("Connect…")) { [weak self] in self?.toggleConnection() }
        menu.addItem(connectItem)
        menu.addItem(.separator())
        menu.addItem(ActionMenuItem(tr("Quit SonyBridge"), key: "q") { NSApp.terminate(nil) })

        // objectWillChange fires before the new value is stored; hopping to the main queue reads the new state.
        model.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.update() }
            .store(in: &cancellables)
        update()
    }

    private func update() {
        let connected = model.connected
        var header = model.deviceName.isEmpty ? "SonyBridge" : model.deviceName
        if connected && model.batteryLevel >= 0 {
            header += " — " + String(format: tr("%ld%%"), model.batteryLevel)
        }
        headerItem.title = header
        for (mode, item) in modeItems {
            item.state = connected && model.mode == mode ? .on : .off
            item.isEnabled = connected
        }
        connectItem.title = connected ? tr("Disconnect") : (model.connecting ? tr("Connecting…") : tr("Connect…"))
        connectItem.isEnabled = !model.connecting
    }

    private func toggleConnection() {
        if model.connected {
            model.disconnect()
        } else {
            NSApp.activate(ignoringOtherApps: true) // the fallback Bluetooth picker is a modal window
            model.connect()
        }
    }
}
```

- [ ] **Step 7 : Remplacer `Client/macos/fr.lproj/Localizable.strings`** par les seules clés utilisées maintenant

```
/* SonyBridge — French UI strings. Keys are the English source strings; missing keys fall back to English. */

/* Menu */
"Ambient Sound Control" = "Contrôle du son ambiant";
"Noise Canceling" = "Réduction de bruit";
"Ambient Sound" = "Son ambiant";
"Off" = "Désactivé";
"Connect…" = "Connecter…";
"Connecting…" = "Connexion…";
"Disconnect" = "Déconnecter";
"Quit SonyBridge" = "Quitter SonyBridge";
"%ld%%" = "%ld %%";

/* Errors (HeadphonesBridge.mm, HeadphonesModel.swift) */
"Headphones disconnected." = "Casque déconnecté.";
"No connected Sony headset found. Connect your headphones in macOS Bluetooth settings first." = "Aucun casque Sony connecté. Connectez d’abord votre casque dans les réglages Bluetooth de macOS.";
"Connection timed out." = "Délai de connexion dépassé.";
"Not connected." = "Non connecté.";
"Equalizer control isn't supported on this device yet." = "Le réglage de l’égaliseur n’est pas encore pris en charge sur cet appareil.";
"Not supported on this device." = "Non pris en charge sur cet appareil.";
```

Run : `plutil -lint Client/macos/fr.lproj/Localizable.strings` → `OK`.

- [ ] **Step 8 : Mettre à jour la section build du `README.md`**

Remplacer le bloc `<details>` « macOS (native SwiftUI app) » de « 🚀 Build from source » par :

````markdown
<details>
<summary><b>macOS (menu bar app)</b></summary>

Requires the **Xcode Command Line Tools** (`xcode-select --install`) — the full Xcode app is not needed.

```sh
git clone https://github.com/AmitRajput-Dev/SonyBridge.git
cd SonyBridge
make run          # builds build/SonyBridge.app and launches it
```

`make test` runs the unit tests, `make release` builds a universal (Apple Silicon + Intel) zip, and
`make run DEBUG=1` logs every frame exchanged with the headphones to `build/app.log`.
</details>
````

- [ ] **Step 9 : Compiler**

Run : `make`
Attendu : les étapes `== [arm64] Swift`, `C++`, `Obj-C++`, `Link`, `Resources`, `Sign`, puis
`OK -> …/build/SonyBridge.app`, sans erreur.

- [ ] **Step 10 : Lancer et vérifier avec l'utilisateur**

Run : `make run DEBUG=1 && pgrep -x SonyBridge`
Attendu : un PID. Demander à l'utilisateur de vérifier :
1. Une icône de casque est dans la barre des menus, grisée, et **rien dans le Dock**.
2. Le menu s'ouvre : « SonyBridge », « Contrôle du son ambiant », les 3 modes (grisés), « Connecter… »,
   « Quitter SonyBridge ⌘Q », en français.
3. « Connecter… » connecte le XM6 : l'icône n'est plus grisée, et l'en-tête affiche « WH-1000XM6 — 68 % ».
4. Cliquer sur « Son ambiant » change bien le mode dans le casque. **Connu, corrigé en tâche 3** : la coche
   peut revenir sur « Désactivé » au bout de 2 s (mauvaise relecture du XM6).
5. « Quitter » ferme l'app.

- [ ] **Step 11 : Commit** (par l'utilisateur)

```bash
git add -A && git commit -m "feat(macos): menu bar agent app built with make (drop Xcode project and window UI)"
```

---

### Task 2: Logique pure (reconnexion, anti-retour, limitation) + `make test`

**Files:**
- Create: `Client/macos/ReconnectPolicy.swift`, `Client/macos/PollGuard.swift`, `Client/macos/SendThrottle.swift`
- Create: `Client/tests/LogicTests/main.swift`, `scripts/test.sh`, `scripts/check_localization.py`
- Modify: `Makefile` (cible `test`), `.github/workflows/build.yml` (étape `make test`)

**Interfaces:**
- Produces :
  - `struct ReconnectPolicy { static let delays: [TimeInterval]; private(set) var attempt: Int; mutating func nextDelay() -> TimeInterval; mutating func reset() }`
  - `struct PollGuard<Key: Hashable> { init(window: TimeInterval = 3); mutating func userChanged(_ key: Key, at date: Date = Date()); func shouldAcceptPoll(for key: Key, at date: Date = Date()) -> Bool }`
  - `struct SendThrottle { init(interval: TimeInterval = 0.15); mutating func shouldSend(at date: Date = Date(), final: Bool) -> Bool }`
  - `make test` : lance `LogicTests` puis `check_localization.py` (la tâche 3 ajoute les tests C++)

- [ ] **Step 1 : Écrire les tests** `Client/tests/LogicTests/main.swift`

```swift
import Foundation

// Minimal test runner (XCTest isn't available without Xcode). Exit code 1 on any failure.
var failures = 0
func check(_ condition: Bool, _ message: String, line: Int = #line) {
    if !condition {
        failures += 1
        print("FAIL line \(line): \(message)")
    }
}

// ReconnectPolicy: 3 s, 10 s, 30 s, then every 60 s; reset restarts.
do {
    var policy = ReconnectPolicy()
    let delays = (0..<6).map { _ in policy.nextDelay() }
    check(delays == [3, 10, 30, 60, 60, 60], "reconnect schedule was \(delays)")
    policy.reset()
    check(policy.nextDelay() == 3, "reset restarts the schedule")
}

// PollGuard: a poll is ignored for 3 s after the user changed that setting.
do {
    var pollGuard = PollGuard<String>(window: 3)
    let t0 = Date(timeIntervalSince1970: 1_000)
    check(pollGuard.shouldAcceptPoll(for: "ambient", at: t0), "no user change: accept")
    pollGuard.userChanged("ambient", at: t0)
    check(!pollGuard.shouldAcceptPoll(for: "ambient", at: t0.addingTimeInterval(2.9)), "inside the window: reject")
    check(pollGuard.shouldAcceptPoll(for: "ambient", at: t0.addingTimeInterval(3)), "after the window: accept")
    check(pollGuard.shouldAcceptPoll(for: "eq", at: t0.addingTimeInterval(1)), "other keys are unaffected")
}

// SendThrottle: at most one send per 150 ms while dragging; the final value always goes out.
do {
    var throttle = SendThrottle(interval: 0.15)
    let t0 = Date(timeIntervalSince1970: 1_000)
    check(throttle.shouldSend(at: t0, final: false), "first drag event sends")
    check(!throttle.shouldSend(at: t0.addingTimeInterval(0.10), final: false), "too soon: skip")
    check(throttle.shouldSend(at: t0.addingTimeInterval(0.16), final: false), "after the interval: send")
    check(throttle.shouldSend(at: t0.addingTimeInterval(0.17), final: true), "final value always sends")
}

if failures > 0 {
    print("LogicTests: \(failures) failure(s)")
    exit(1)
}
print("LogicTests: all passed")
```

- [ ] **Step 2 : Écrire `scripts/test.sh`** (puis `chmod +x scripts/test.sh`)

```bash
#!/bin/bash
# Builds and runs the unit test executables (plain asserts, no XCTest), then checks the translations.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
MAC=$ROOT/Client/macos
OUT=$ROOT/build/tests
SDK=$(xcrun --show-sdk-path)
TARGET=$(uname -m)-apple-macos13.0
mkdir -p "$OUT"

echo "== LogicTests"
swiftc -target "$TARGET" -sdk "$SDK" -swift-version 5 \
    "$ROOT/Client/tests/LogicTests/main.swift" \
    "$MAC/ReconnectPolicy.swift" "$MAC/PollGuard.swift" "$MAC/SendThrottle.swift" \
    -o "$OUT/LogicTests"
"$OUT/LogicTests"

echo "== Localization"
python3 "$ROOT/scripts/check_localization.py"
```

- [ ] **Step 3 : Ajouter la cible `test` au `Makefile`**

Remplacer la ligne `.PHONY` et ajouter la cible :

```make
.PHONY: all build run test release clean

test:
	./scripts/test.sh
```

- [ ] **Step 4 : Lancer les tests pour les voir échouer**

Run : `make test`
Attendu : échec de compilation, `cannot find 'ReconnectPolicy' in scope` (et `PollGuard`, `SendThrottle`).

- [ ] **Step 5 : Écrire les trois fichiers de logique**

`Client/macos/ReconnectPolicy.swift` :

```swift
import Foundation

// Delays between automatic reconnection attempts: 3 s, 10 s, 30 s, then every 60 s.
struct ReconnectPolicy {
    static let delays: [TimeInterval] = [3, 10, 30, 60]
    private(set) var attempt = 0

    // Delay before the next attempt; each call advances the schedule.
    mutating func nextDelay() -> TimeInterval {
        let delay = Self.delays[min(attempt, Self.delays.count - 1)]
        attempt += 1
        return delay
    }

    mutating func reset() {
        attempt = 0
    }
}
```

`Client/macos/PollGuard.swift` :

```swift
import Foundation

// Ignores a polled value for a setting the user changed less than `window` seconds ago, so a read-back that
// raced the user's command doesn't briefly flip the menu back to the old state.
struct PollGuard<Key: Hashable> {
    let window: TimeInterval
    private var lastUserChange: [Key: Date] = [:]

    init(window: TimeInterval = 3) {
        self.window = window
    }

    mutating func userChanged(_ key: Key, at date: Date = Date()) {
        lastUserChange[key] = date
    }

    func shouldAcceptPoll(for key: Key, at date: Date = Date()) -> Bool {
        guard let changed = lastUserChange[key] else { return true }
        return date.timeIntervalSince(changed) >= window
    }
}
```

`Client/macos/SendThrottle.swift` :

```swift
import Foundation

// Rate-limits slider commands: at most one every `interval` while dragging; the final value always goes out.
struct SendThrottle {
    let interval: TimeInterval
    private var lastSend: Date?

    init(interval: TimeInterval = 0.15) {
        self.interval = interval
    }

    mutating func shouldSend(at date: Date = Date(), final: Bool) -> Bool {
        if !final, let last = lastSend, date.timeIntervalSince(last) < interval {
            return false
        }
        lastSend = date
        return true
    }
}
```

- [ ] **Step 6 : Écrire `scripts/check_localization.py`**

```python
#!/usr/bin/env python3
"""Every tr("…") / NSLocalizedString("…") key must have a French translation, and every French key must be used."""
import json
import pathlib
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
MAC = ROOT / "Client" / "macos"
STRINGS = MAC / "fr.lproj" / "Localizable.strings"
LITERAL = r'"((?:[^"\\]|\\.)*)"'
PATTERNS = [re.compile(r"\btr\(" + LITERAL + r"\)"), re.compile(r"NSLocalizedString\(@?" + LITERAL)]

french = set(json.loads(subprocess.check_output(["plutil", "-convert", "json", "-o", "-", str(STRINGS)])))
used = set()
for path in sorted(MAC.rglob("*.swift")) + sorted(MAC.rglob("*.mm")):
    text = path.read_text(encoding="utf-8")
    for pattern in PATTERNS:
        used.update(key.replace("\\n", "\n") for key in pattern.findall(text))

missing = sorted(used - french)
unused = sorted(french - used)
for key in missing:
    print(f"missing French translation: {key!r}")
for key in unused:
    print(f"unused French key: {key!r}")
if missing or unused:
    sys.exit(1)
print(f"Localization: {len(used)} keys, all translated")
```

- [ ] **Step 7 : Relancer les tests**

Run : `make test`
Attendu : `LogicTests: all passed` puis `Localization: 15 keys, all translated` (les 15 clés de la tâche 1).
Si la vérif. des traductions échoue, corriger `Localizable.strings` : la tâche 1 doit être propre.

- [ ] **Step 8 : Ajouter les tests à la CI**

Dans `.github/workflows/build.yml`, avant l'étape « Build (release, universal) » :

```yaml
      - name: Test
        run: make test
```

- [ ] **Step 9 : Commit** (par l'utilisateur)

```bash
git add -A && git commit -m "test: reconnect/poll-guard/throttle logic, localization check, make test"
```

---

### Task 3: Décodage des trames + corrections XM6 (canal `0x19`, égaliseur 10 bandes en lecture)

**Files:**
- Create: `Client/ProtocolParsers.h`, `Client/ProtocolParsers.cpp`, `Client/tests/ProtocolParsersTests.cpp`
- Modify: `Client/Headphones.h`, `Client/Headphones.cpp` (`requestAmbientState`, `requestEqualizer`,
  `setEqualizerCustom`, nouvelles méthodes), `Client/macos/HeadphonesBridge.h/.mm`, `scripts/test.sh`

**Interfaces:**
- Produces (C++) :
  - `namespace ProtocolParsers { struct NcAsmState { bool enabled; bool ambient; bool focusOnVoice; int level; }; std::optional<NcAsmState> parseNcAsmState(const Buffer&); struct EqualizerState { unsigned char preset; bool hasClearBass; int clearBass; std::vector<int> bands; }; std::optional<EqualizerState> parseEqualizer(const Buffer&); }`
  - `Headphones::probeNcAsmInquiryType()`, `int Headphones::getEqualizerBandCount()`, `bool Headphones::equalizerHasClearBass()`
- Produces (Obj-C, visible en Swift) : `equalizerBandCount: Int`, `equalizerHasClearBass: Bool`,
  `equalizerWritable: Bool` sur `HeadphonesBridge`.

- [ ] **Step 1 : Écrire les tests** `Client/tests/ProtocolParsersTests.cpp` (trames réelles du XM6, spec §7)

```cpp
#include "ProtocolParsers.h"
#include "CommandSerializer.h"
#include <cstdio>
#include <initializer_list>

// Minimal test runner (no framework). Exit code 1 on any failure.
static int failures = 0;
#define CHECK(cond) do { if (!(cond)) { failures++; std::printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond); } } while (0)

static Buffer bytes(std::initializer_list<int> values)
{
	Buffer b;
	for (int v : values) b.push_back((char)v);
	return b;
}

int main()
{
	using namespace ProtocolParsers;

	// --- NC/ASM state ---
	// WH-1000XM6 answer to the legacy 0x17 inquiry: all zeros = "not this channel".
	CHECK(!parseNcAsmState(bytes({ 0x67, 0x17, 0x00, 0x00, 0x00, 0x00, 0x00 })).has_value());
	// WH-1000XM6 notify on 0x19: Ambient Sound on, level 10, no voice focus.
	{
		auto s = parseNcAsmState(bytes({ 0x69, 0x19, 0x01, 0x01, 0x01, 0x00, 0x0a, 0x00, 0x00 }));
		CHECK(s && s->enabled && s->ambient && !s->focusOnVoice && s->level == 10);
	}
	// WH-1000XM6 reply on 0x19: Noise Cancelling (ambient byte = 0).
	{
		auto s = parseNcAsmState(bytes({ 0x67, 0x19, 0x01, 0x01, 0x00, 0x00, 0x0a, 0x00, 0x00 }));
		CHECK(s && s->enabled && !s->ambient);
	}
	// Legacy 0x17 layout (WH-CH720N): effect off.
	{
		auto s = parseNcAsmState(bytes({ 0x67, 0x17, 0x01, 0x00, 0x00, 0x00, 0x01 }));
		CHECK(s && !s->enabled);
	}
	CHECK(!parseNcAsmState(bytes({ 0x67, 0x17, 0x01 })).has_value());                          // too short
	CHECK(!parseNcAsmState(bytes({ 0x57, 0x17, 0x01, 0x01, 0x01, 0x00, 0x0a })).has_value());   // wrong opcode

	// --- Equalizer ---
	// WH-1000XM6: unknown preset 0x30, 10 bands (offset +10 hypothesis, spec §7).
	{
		auto e = parseEqualizer(bytes({ 0x57, 0x00, 0x30, 0x0a, 0x0a, 0x0a, 0x05, 0x05, 0x06, 0x06, 0x06, 0x06, 0x06, 0x06 }));
		CHECK(e && e->preset == 0x30 && !e->hasClearBass && e->bands.size() == 10);
		CHECK(e && e->bands[0] == 0 && e->bands[2] == -5 && e->bands[9] == -4);
	}
	// 5 bands + Clear Bass (WH-CH720N): Manual, bass +3, bands -2..+2.
	{
		auto e = parseEqualizer(bytes({ 0x57, 0x00, 0xa0, 0x06, 13, 8, 9, 10, 11, 12 }));
		CHECK(e && e->preset == 0xa0 && e->hasClearBass && e->clearBass == 3);
		CHECK(e && e->bands == std::vector<int>({ -2, -1, 0, 1, 2 }));
	}
	// Preset only, no band data.
	{
		auto e = parseEqualizer(bytes({ 0x57, 0x00, 0x16 }));
		CHECK(e && e->preset == 0x16 && e->bands.empty());
	}
	CHECK(!parseEqualizer(bytes({ 0x23, 0x00, 0x44, 0x00 })).has_value());                     // battery reply

	// --- Framing ---
	// Round trip, with a payload byte (0x3c = END_MARKER) that must be escaped.
	{
		Buffer payload = bytes({ 0x68, 0x17, 0x01, 0x01, 0x01, 0x00, 0x3c });
		auto frame = CommandSerializer::packageDataForBt(payload, DATA_TYPE::DATA_MDR, 1);
		CHECK(frame.front() == START_MARKER && frame.back() == END_MARKER);
		auto msg = CommandSerializer::unpackBtMessage(Buffer(frame.begin() + 1, frame.end() - 1));
		CHECK(msg.dataType == DATA_TYPE::DATA_MDR && msg.seqNumber == 1 && msg.payload == payload);
	}
	// Real WH-1000XM6 battery frame (68 %), between the 3e/3c markers.
	{
		auto msg = CommandSerializer::unpackBtMessage(bytes({ 0x0c, 0x00, 0x00, 0x00, 0x00, 0x04, 0x23, 0x00, 0x44, 0x00, 0x77 }));
		CHECK(msg.payload == bytes({ 0x23, 0x00, 0x44, 0x00 }));
	}

	if (failures) { std::printf("ProtocolParsersTests: %d failure(s)\n", failures); return 1; }
	std::printf("ProtocolParsersTests: all passed\n");
	return 0;
}
```

- [ ] **Step 2 : Brancher le test dans `scripts/test.sh`**, juste avant `echo "== Localization"` :

```bash
echo "== ProtocolParsersTests"
clang++ -target "$TARGET" -isysroot "$SDK" -std=c++17 -I "$ROOT/Client" \
    "$ROOT/Client/tests/ProtocolParsersTests.cpp" "$ROOT/Client/ProtocolParsers.cpp" \
    "$ROOT/Client/CommandSerializer.cpp" "$ROOT/Client/ByteMagic.cpp" \
    -o "$OUT/ProtocolParsersTests"
"$OUT/ProtocolParsersTests"
```

- [ ] **Step 3 : Voir le test échouer**

Run : `make test`
Attendu : échec, `'ProtocolParsers.h' file not found`.

- [ ] **Step 4 : Écrire `Client/ProtocolParsers.h`**

```cpp
#pragma once

#include <optional>
#include <vector>
#include "Constants.h"

// Pure decoders for v2 inquiry replies. `payload` is the frame's <DATA> field, starting with the reply opcode.
namespace ProtocolParsers
{
	struct NcAsmState
	{
		bool enabled;       // NC/ASM effect on
		bool ambient;       // true = Ambient Sound, false = Noise Cancelling
		bool focusOnVoice;
		int level;          // ambient level (meaningful when ambient)
	};

	// Accepts "67|69 17 01 <on> <ambient> <voice> <level>" and the WH-1000XM6 "67|69 19 01 <on> <ambient> <voice>
	// <level> <x> <y>". Returns nullopt when too short, for other opcodes, and for the all-zero body the XM6 sends
	// back on the channel it doesn't use (67 17 00 00 00 00 00).
	std::optional<NcAsmState> parseNcAsmState(const Buffer& payload);

	struct EqualizerState
	{
		unsigned char preset;       // raw preset id (EQ_PRESET values, or ids we don't know yet like 0x30)
		bool hasClearBass;          // 5-band layout only
		int clearBass;              // -10..10 when hasClearBass
		std::vector<int> bands;     // 5 or 10 values in -10..10; empty when the reply carried no band data
	};

	// "57 00 <preset> 06 <bass+10> <b1..b5 +10>" (5 bands + Clear Bass) or "57 00 <preset> 0a <b1..b10 +10>".
	std::optional<EqualizerState> parseEqualizer(const Buffer& payload);
}
```

- [ ] **Step 5 : Écrire `Client/ProtocolParsers.cpp`**

```cpp
#include "ProtocolParsers.h"

#include <algorithm>

namespace ProtocolParsers
{
	std::optional<NcAsmState> parseNcAsmState(const Buffer& payload)
	{
		if (payload.size() < 7) return std::nullopt;
		auto opcode = (unsigned char)payload[0];
		auto type = (unsigned char)payload[1];
		if ((opcode != 0x67 && opcode != 0x69) || (type != 0x17 && type != 0x19)) return std::nullopt;
		if (std::all_of(payload.begin() + 2, payload.end(), [](char b) { return b == 0; })) return std::nullopt;

		NcAsmState state;
		state.enabled = payload[3] != 0;
		state.ambient = payload[4] != 0;
		state.focusOnVoice = payload[5] != 0;
		state.level = (unsigned char)payload[6];
		return state;
	}

	std::optional<EqualizerState> parseEqualizer(const Buffer& payload)
	{
		if (payload.size() < 3 || (unsigned char)payload[0] != 0x57) return std::nullopt;

		EqualizerState state{ (unsigned char)payload[2], false, 0, {} };
		if (payload.size() < 4) return state;
		size_t count = (unsigned char)payload[3];
		if (payload.size() < 4 + count) return state;

		auto value = [&](size_t i) { return (int)(unsigned char)payload[4 + i] - 10; };
		if (count == 6)
		{
			state.hasClearBass = true;
			state.clearBass = value(0);
			for (size_t i = 1; i < 6; i++) state.bands.push_back(value(i));
		}
		else if (count == 10)
		{
			for (size_t i = 0; i < 10; i++) state.bands.push_back(value(i));
		}
		return state;
	}
}
```

- [ ] **Step 6 : Relancer les tests**

Run : `make test`
Attendu : `LogicTests: all passed`, `ProtocolParsersTests: all passed`, `Localization: 15 keys, all translated`.

- [ ] **Step 7 : Brancher les décodeurs dans `Client/Headphones.h`**

Sous `void requestEqualizer();` / `EQ_PRESET getEqualizerPreset();`, ajouter :

```cpp
	int getEqualizerBandCount();   // 0 until read, then 5 (+ Clear Bass) or 10
	bool equalizerHasClearBass();
```

Sous `void requestAmbientState();`, ajouter :

```cpp
	// Picks the NC/ASM inquiry channel: 0x19 when the device answers it (WH-1000XM6), else the legacy 0x17.
	void probeNcAsmInquiryType();
```

Remplacer le membre `std::vector<int> _eqBands = { 0, 0, 0, 0, 0 };` par :

```cpp
	std::vector<int> _eqBands;              // empty until the first read; 5 or 10 values
	bool _eqHasClearBass = false;
	unsigned char _ncAsmInquiryType = 0x17; // 0x19 on the WH-1000XM6, see probeNcAsmInquiryType()
```

- [ ] **Step 8 : Modifier `Client/Headphones.cpp`**

Ajouter `#include "ProtocolParsers.h"` après `#include "CommandSerializer.h"`.

Remplacer tout le corps de `Headphones::requestEqualizer()` par :

```cpp
void Headphones::requestEqualizer()
{
	// GET: 56 00 -> RET: 57 00 <preset> <count> <values...> (decoded by ProtocolParsers::parseEqualizer)
	auto resp = this->_conn.sendCommandAndReadResponse({ (char)V2Command::EQ_GET, 0x00 }, V2Command::EQ_RET);
	if (auto eq = ProtocolParsers::parseEqualizer(resp))
	{
		std::lock_guard guard(this->_propertyMtx);
		this->_eqPreset = static_cast<EQ_PRESET>(eq->preset);
		if (!eq->bands.empty())
		{
			this->_eqBands = eq->bands;
			this->_eqHasClearBass = eq->hasClearBass;
			this->_eqClearBass = eq->clearBass;
		}
	}
}

int Headphones::getEqualizerBandCount() { return (int)this->_eqBands.size(); }
bool Headphones::equalizerHasClearBass() { return this->_eqHasClearBass; }
```

Dans `Headphones::setEqualizerCustom`, remplacer la boucle finale qui écrit `this->_eqBands[i]` par :

```cpp
	this->_eqBands.assign(bands.begin(), bands.end());
```

Dans `Headphones::requestAmbientState()`, remplacer le bloc `if (protocolVersion == SonyProtocolVersion::V2) { … }` par :

```cpp
	if (protocolVersion == SonyProtocolVersion::V2)
	{
		// GET: 66 <type> -> RET: 67 <type> 01 <effect> <0=NC/1=Ambient> <voice> <level> [2 more bytes on 0x19]
		auto resp = this->_conn.sendCommandAndReadResponse({ 0x66, (char)this->_ncAsmInquiryType }, 0x67, this->_ncAsmInquiryType);
		if (auto state = ProtocolParsers::parseNcAsmState(resp))
		{
			std::lock_guard guard(this->_propertyMtx);
			// Update both current and desired so the UI reflects reality and isChanged() stays false.
			this->_ambientSoundControl.current = this->_ambientSoundControl.desired = state->enabled;
			this->_asmLevel.current = this->_asmLevel.desired = state->ambient ? state->level : 0;
			this->_focusOnVoice.current = this->_focusOnVoice.desired = state->focusOnVoice;
		}
	}
```

Ajouter après `requestAmbientState()` :

```cpp
void Headphones::probeNcAsmInquiryType()
{
	// The WH-1000XM6 answers the legacy 0x17 inquiry with all zeros and reports its real state on 0x19.
	// Setting the mode still goes through 68 17, which the XM6 accepts.
	try
	{
		auto resp = this->_conn.sendCommandAndReadResponse({ 0x66, 0x19 }, 0x67, 0x19);
		if (ProtocolParsers::parseNcAsmState(resp)) this->_ncAsmInquiryType = 0x19;
	}
	catch (...) {}
}
```

- [ ] **Step 9 : Exposer l'égaliseur dans `Client/macos/HeadphonesBridge.h`**

Sous `@property (nonatomic, readonly) BOOL supportsEqualizer;`, ajouter :

```objc
@property (nonatomic, readonly) NSInteger equalizerBandCount;   // 0 until read, then 5 or 10
@property (nonatomic, readonly) BOOL equalizerHasClearBass;     // 5-band layout
// NO while this device's equalizer write format is unverified (the WH-1000XM6's 10-band layout, spec §7).
@property (nonatomic, readonly) BOOL equalizerWritable;
```

- [ ] **Step 10 : Modifier `Client/macos/HeadphonesBridge.mm`**

Après `- (NSInteger)clearBass { … }`, ajouter :

```objc
- (NSInteger)equalizerBandCount { return _hp ? _hp->getEqualizerBandCount() : 0; }
- (BOOL)equalizerHasClearBass { return _hp && _hp->equalizerHasClearBass(); }
// Only the 5-band + Clear Bass layout (WH-CH720N family) has a verified write format.
- (BOOL)equalizerWritable { return self.supportsEqualizer && _hp && _hp->equalizerHasClearBass(); }
```

Dans `refreshStatusWithCompletion:`, remplacer :

```objc
            if (!self->_initialized) {
                hp->initDevice();
                self->_initialized = YES;
            }
```

par :

```objc
            if (!self->_initialized) {
                hp->initDevice();
                hp->probeNcAsmInquiryType();
                self->_initialized = YES;
            }
```

Dans `setEqualizerPreset:completion:`, remplacer la condition
`if (_bt->getProtocolVersion() != SonyProtocolVersion::V2) {` par `if (!self.equalizerWritable) {`.
Dans `setCustomEqualizerBass:bands:completion:`, remplacer
`if (!_hp || !self.connected || _bt->getProtocolVersion() != SonyProtocolVersion::V2) {` par
`if (!_hp || !self.connected || !self.equalizerWritable) {`.

- [ ] **Step 11 : Compiler et tester**

Run : `make test && make`
Attendu : les trois lignes « all passed / all translated », puis `OK -> …/build/SonyBridge.app`.

- [ ] **Step 12 : Vérifier sur le XM6 avec l'utilisateur**

Run : `make run DEBUG=1`, demander à l'utilisateur de cliquer sur « Connecter… », puis
`grep -E '\[send\].* 66 19|\[recv\].* 67 19' build/app.log | head -4`
Attendu : une demande `66 19` et une réponse `67 19 …` non nulle.
Demander ensuite à l'utilisateur :
1. Choisir « Son ambiant » dans le menu : la coche **reste** sur « Son ambiant » (plus de retour sur
   « Désactivé »).
2. Appuyer sur le bouton NC du casque : en 2 s environ, la coche suit le mode du casque (menu fermé puis
   rouvert ; les mises à jour menu ouvert viennent en tâche 4).

- [ ] **Step 13 : Commit** (par l'utilisateur)

```bash
git add -A && git commit -m "fix(xm6): read NC/ASM state on channel 0x19, decode 10-band equalizer (read-only)"
```

---

### Task 4: Nouveau `HeadphonesModel` (état, minuteurs menu ouvert, anti-retour, limitation, batterie)

Réécrit le modèle pour le menu : un état de connexion unique, les propriétés en lecture seule, les minuteurs
en mode `.common`, `PollGuard` et `SendThrottle`, la relecture de la batterie toutes les 60 s, et les erreurs
affichées seulement pour les actions de l'utilisateur.

**Files:**
- Modify (réécriture complète) : `Client/macos/HeadphonesModel.swift`
- Modify : `Client/macos/HeadphonesBridge.h/.mm` (`refreshBatteryWithCompletion:`),
  `Client/macos/StatusItemController.swift`, `Client/macos/HeadphonesMenu.swift`,
  `Client/macos/fr.lproj/Localizable.strings`

**Interfaces:**
- Consumes : `PollGuard`, `SendThrottle` (tâche 2) ; `equalizerBandCount`, `equalizerHasClearBass`,
  `equalizerWritable` (tâche 3).
- Produces (utilisé par les tâches 5 à 8) :
  - `enum ConnectionState { case disconnected, connecting, connected }`
  - `HeadphonesModel` : `connectionState`, `connected` (calculé), `deviceName`, `deviceMac`, `protocolVersion`,
    `firmware`, `codec`, `maxAmbientLevel`, `mode`, `ambientLevel`, `focusOnVoice`, `batteryLevel`,
    `batteryCharging`, `hasDualBattery`, `batteryLeft`, `batteryRight`, `batteryCase`, `supportsEqualizer`,
    `equalizerWritable`, `eqPreset: Int`, `eqBands: [Int]`, `eqHasClearBass`, `clearBass`, `dsee`,
    `hasAutoPowerOff`, `autoPowerOff`, `hasSpeakToChat`, `speakToChat`, `hasAdaptiveVolume`, `adaptiveVolume`,
    `errorMessage: String?` (tous `@Published private(set)`)
  - Actions : `connect()`, `disconnect()`, `setMode(_:)`, `setLevel(_:final:)`, `setFocusOnVoice(_:)`,
    `setEqualizerPreset(_:)`, `setEqualizerBand(_:value:final:)`, `setClearBass(_:final:)`, `resetEqualizer()`,
    `setDsee(_:)`, `setAutoPowerOff(_:)`, `setSpeakToChat(_:)`, `setAdaptiveVolume(_:)`, `showError(_:)`
  - Point d'extension pour la tâche 7 : `handleConnectResult(ok:error:userInitiated:)` et `linkLost()`

- [ ] **Step 1 : Ajouter la relecture de la batterie au pont**

`Client/macos/HeadphonesBridge.h`, sous `refreshDynamicWithCompletion:` :

```objc
// Re-reads the battery level (v2 devices only). Completion on the main thread.
- (void)refreshBatteryWithCompletion:(void (^)(void))completion;
```

`Client/macos/HeadphonesBridge.mm`, après `refreshDynamicWithCompletion:` :

```objc
- (void)refreshBatteryWithCompletion:(void (^)(void))completion {
    // CRITICAL: 0x22 is BATTERY_LEVEL_REQUEST on v2 but POWER_OFF on v1 - never send it to a v1 device.
    if (!_hp || !self.connected || _bt->getProtocolVersion() != SonyProtocolVersion::V2) { completion(); return; }
    Headphones *hp = _hp.get();
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        try { hp->requestBattery(); } catch (std::exception &exc) {}
        dispatch_async(dispatch_get_main_queue(), ^{ completion(); });
    });
}
```

- [ ] **Step 2 : Réécrire `Client/macos/HeadphonesModel.swift`**

```swift
import Foundation
import Combine

enum ConnectionState {
    case disconnected, connecting, connected
}

// Observable state of the headphones and the actions the menu triggers. Wraps the Obj-C++ HeadphonesBridge.
final class HeadphonesModel: ObservableObject {
    private enum PolledSetting { case ambient }

    private let bridge = HeadphonesBridge()

    @Published private(set) var connectionState: ConnectionState = .disconnected
    var connected: Bool { connectionState == .connected }

    // Kept after a disconnect so the header still names the last headset.
    @Published private(set) var deviceName = ""
    @Published private(set) var deviceMac = ""
    @Published private(set) var protocolVersion = ""
    @Published private(set) var firmware = ""
    @Published private(set) var codec = ""
    @Published private(set) var maxAmbientLevel = 20

    @Published private(set) var mode: SHCAmbientMode = .off
    @Published private(set) var ambientLevel = 10
    @Published private(set) var focusOnVoice = false

    @Published private(set) var batteryLevel = -1
    @Published private(set) var batteryCharging = false
    @Published private(set) var hasDualBattery = false
    @Published private(set) var batteryLeft = -1
    @Published private(set) var batteryRight = -1
    @Published private(set) var batteryCase = -1

    @Published private(set) var supportsEqualizer = false
    @Published private(set) var equalizerWritable = false
    @Published private(set) var eqPreset = 0
    @Published private(set) var eqBands: [Int] = []
    @Published private(set) var eqHasClearBass = false
    @Published private(set) var clearBass = 0
    @Published private(set) var dsee = false

    @Published private(set) var hasAutoPowerOff = false
    @Published private(set) var autoPowerOff = 0
    @Published private(set) var hasSpeakToChat = false
    @Published private(set) var speakToChat = false
    @Published private(set) var hasAdaptiveVolume = false
    @Published private(set) var adaptiveVolume = false

    // Last error from a user action; cleared by the next successful one.
    @Published private(set) var errorMessage: String?

    private var timers: [Timer] = []
    private var pollGuard = PollGuard<PolledSetting>()
    private var levelThrottle = SendThrottle()
    private var eqThrottle = SendThrottle()

    // MARK: - Connection

    // User-initiated: uses the already-connected Sony headset, else the macOS Bluetooth picker.
    func connect() {
        connectionState = .connecting
        errorMessage = nil
        // Defer so the menu can show "Connecting…" before a modal picker blocks the main thread.
        DispatchQueue.main.async {
            self.bridge.scanAndConnect { ok, error in
                self.handleConnectResult(ok: ok, error: error, userInitiated: true)
            }
        }
    }

    func disconnect() {
        stopTimers()
        bridge.disconnect()
        connectionState = .disconnected
    }

    func handleConnectResult(ok: Bool, error: String?, userInitiated: Bool) {
        guard ok else {
            connectionState = .disconnected
            if userInitiated, let error = error { errorMessage = error }
            return
        }
        connectionState = .connected
        syncFromBridge()
        bridge.refreshStatus { [weak self] in self?.syncFromBridge() } // called after reads, then after probes
        startTimers()
    }

    // The control link dropped on its own (idle power-save). Task 7 adds the automatic reconnection here.
    func linkLost() {
        stopTimers()
        connectionState = .disconnected
    }

    // MARK: - Actions

    func setMode(_ newMode: SHCAmbientMode) {
        mode = newMode
        pollGuard.userChanged(.ambient)
        pushAmbient()
    }

    func setLevel(_ level: Int, final: Bool) {
        ambientLevel = level
        pollGuard.userChanged(.ambient)
        if mode == .ambientSound && levelThrottle.shouldSend(final: final) { pushAmbient() }
    }

    func setFocusOnVoice(_ on: Bool) {
        focusOnVoice = on
        pollGuard.userChanged(.ambient)
        pushAmbient()
    }

    func setEqualizerPreset(_ preset: Int) {
        eqPreset = preset
        bridge.setEqualizerPreset(preset) { [weak self] ok, error in self?.finish(ok, error) }
    }

    func setEqualizerBand(_ index: Int, value: Int, final: Bool) {
        guard eqBands.indices.contains(index) else { return }
        eqBands[index] = value
        eqPreset = 0xA0
        if eqThrottle.shouldSend(final: final) { pushCustomEqualizer() }
    }

    func setClearBass(_ value: Int, final: Bool) {
        clearBass = value
        eqPreset = 0xA0
        if eqThrottle.shouldSend(final: final) { pushCustomEqualizer() }
    }

    func resetEqualizer() {
        eqBands = Array(repeating: 0, count: eqBands.count)
        clearBass = 0
        eqPreset = 0xA0
        pushCustomEqualizer()
    }

    func setDsee(_ on: Bool) {
        dsee = on
        bridge.setDsee(on) { [weak self] ok, error in self?.finish(ok, error) }
    }

    func setAutoPowerOff(_ index: Int) {
        autoPowerOff = index
        bridge.setAutoPowerOff(index) { [weak self] ok, error in self?.finish(ok, error) }
    }

    func setSpeakToChat(_ on: Bool) {
        speakToChat = on
        bridge.setSpeakToChat(on) { [weak self] ok, error in self?.finish(ok, error) }
    }

    func setAdaptiveVolume(_ on: Bool) {
        adaptiveVolume = on
        bridge.setAdaptiveVolume(on) { [weak self] ok, error in self?.finish(ok, error) }
    }

    func showError(_ message: String) {
        errorMessage = message
    }

    private func pushAmbient() {
        bridge.applyMode(mode, level: ambientLevel, focusVoice: focusOnVoice) { [weak self] ok, error in
            self?.finish(ok, error)
        }
    }

    private func pushCustomEqualizer() {
        bridge.setCustomEqualizerBass(clearBass, bands: eqBands.map { NSNumber(value: $0) }) { [weak self] ok, error in
            self?.finish(ok, error)
        }
    }

    private func finish(_ ok: Bool, _ error: String?) {
        errorMessage = ok ? nil : error
    }

    // MARK: - Polling

    private func startTimers() {
        stopTimers()
        timers = [
            repeating(every: 1.5) { [weak self] in self?.checkLink() },
            repeating(every: 2) { [weak self] in self?.pollAmbient() },
            repeating(every: 60) { [weak self] in self?.pollBattery() },
        ]
    }

    private func stopTimers() {
        timers.forEach { $0.invalidate() }
        timers = []
    }

    // Added in .common mode so they keep firing while the menu is open (menus run the event-tracking mode).
    private func repeating(every interval: TimeInterval, _ block: @escaping () -> Void) -> Timer {
        let timer = Timer(timeInterval: interval, repeats: true) { _ in block() }
        RunLoop.main.add(timer, forMode: .common)
        return timer
    }

    private func checkLink() {
        if connected && !bridge.connected { linkLost() }
    }

    // Follows the headset's own NC button, unless the user just changed the mode from the menu.
    private func pollAmbient() {
        guard connected, pollGuard.shouldAcceptPoll(for: .ambient) else { return }
        bridge.refreshDynamic { [weak self] in
            guard let self = self, self.pollGuard.shouldAcceptPoll(for: .ambient) else { return }
            self.readAmbientFromBridge()
        }
    }

    private func pollBattery() {
        guard connected else { return }
        bridge.refreshBattery { [weak self] in self?.readBatteryFromBridge() }
    }

    // MARK: - Reading the bridge

    private func syncFromBridge() {
        deviceName = bridge.deviceName ?? deviceName
        deviceMac = bridge.deviceMac ?? deviceMac
        protocolVersion = bridge.protocolVersionString ?? ""
        maxAmbientLevel = bridge.maxAmbientLevel
        readAmbientFromBridge()
        readBatteryFromBridge()
        supportsEqualizer = bridge.supportsEqualizer
        equalizerWritable = bridge.equalizerWritable
        eqPreset = bridge.eqPreset
        eqHasClearBass = bridge.equalizerHasClearBass
        clearBass = bridge.clearBass
        eqBands = (0..<bridge.equalizerBandCount).map { bridge.equalizerBand(at: $0) }
        dsee = bridge.dsee
        hasAutoPowerOff = bridge.hasAutoPowerOff
        autoPowerOff = bridge.autoPowerOff
        hasSpeakToChat = bridge.hasSpeakToChat
        speakToChat = bridge.speakToChat
        hasAdaptiveVolume = bridge.hasAdaptiveVolume
        adaptiveVolume = bridge.adaptiveVolume
        firmware = bridge.firmware ?? ""
        codec = bridge.codec ?? ""
    }

    private func readAmbientFromBridge() {
        mode = bridge.mode
        let level = bridge.ambientLevel
        if level > 0 { ambientLevel = level }
        focusOnVoice = bridge.focusOnVoice
    }

    private func readBatteryFromBridge() {
        batteryLevel = bridge.batteryLevel
        batteryCharging = bridge.batteryCharging
        hasDualBattery = bridge.hasDualBattery
        batteryLeft = bridge.batteryLeft
        batteryRight = bridge.batteryRight
        batteryCase = bridge.batteryCase
    }
}
```

- [ ] **Step 3 : Adapter l'icône et le menu minimal au nouvel état**

`Client/macos/StatusItemController.swift` : remplacer le bloc `model.$connected … .store(in: &cancellables)` par :

```swift
        model.$connectionState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in self?.statusItem.button?.appearsDisabled = state != .connected }
            .store(in: &cancellables)
```

`Client/macos/HeadphonesMenu.swift`, dans `update()` : remplacer
`(model.connecting ? tr("Connecting…") : tr("Connect…"))` par
`(model.connectionState == .connecting ? tr("Connecting…") : tr("Connect…"))`, et
`connectItem.isEnabled = !model.connecting` par `connectItem.isEnabled = model.connectionState != .connecting`.

- [ ] **Step 4 : Retirer la clé devenue inutile**

Dans `Client/macos/fr.lproj/Localizable.strings`, supprimer la ligne `"Headphones disconnected." = …;` (le
modèle n'affiche plus d'erreur quand la liaison se coupe d'elle-même).

- [ ] **Step 5 : Tests et build**

Run : `make test && make`
Attendu : tout passe, `Localization: 14 keys, all translated`, puis `OK -> …`.

- [ ] **Step 6 : Vérifier avec l'utilisateur**

Run : `make run DEBUG=1`. Demander à l'utilisateur de :
1. Se connecter, **ouvrir le menu et le laisser ouvert**, puis appuyer sur le bouton NC du casque : la coche
   change pendant que le menu est ouvert (les minuteurs tournent en mode `.common`).
2. Choisir « Son ambiant » : la coche ne revient pas en arrière.
Après au moins 2 minutes connecté : `grep -c '\[send\].* 22 00' build/app.log` → au moins 2 (lecture à la
connexion + relecture toutes les 60 s).

- [ ] **Step 7 : Commit** (par l'utilisateur)

```bash
git add -A && git commit -m "refactor(macos): menu-oriented HeadphonesModel (connection state, common-mode timers, poll guard, battery polling)"
```

---

### Task 5: Lignes riches du menu (vues SwiftUI hébergées)

Crée les quatre vues et les vérifie tôt dans le vrai menu : c'est le risque technique principal (spec §11).
Les curseurs de l'égaliseur sont des `NSSlider` natifs verticaux (via `NSViewRepresentable`) : les contrôles
AppKit suivent la souris de façon fiable dans un menu.

**Files:**
- Modify : `Client/macos/MenuSupport.swift` (`MenuMetrics`, `hostingMenuItem`)
- Create : `Client/macos/MenuRows/HeaderRow.swift`, `AmbientLevelRow.swift`, `ToggleRow.swift`, `EqualizerRow.swift`
- Modify : `Client/macos/HeadphonesMenu.swift` (branchement provisoire de l'en-tête et du curseur),
  `Client/macos/fr.lproj/Localizable.strings`

**Interfaces:**
- Consumes : l'API `HeadphonesModel` de la tâche 4.
- Produces :
  - `enum MenuMetrics { static let width: CGFloat; static let equalizerWidth: CGFloat; static let leading: CGFloat; static let indent: CGFloat }`
  - `func hostingMenuItem<Content: View>(width: CGFloat = MenuMetrics.width, @ViewBuilder _ content: () -> Content) -> NSMenuItem`
  - `struct HeaderRow: View { init(model:) }`, `struct AmbientLevelRow: View { init(model:) }`,
    `struct ToggleRow: View { init(model:title:indent:isOn:set:) }`, `struct EqualizerRow: View { init(model:) }`

- [ ] **Step 1 : Ajouter à `Client/macos/MenuSupport.swift`** (ajouter `import SwiftUI` en tête du fichier)

```swift
enum MenuMetrics {
    static let width: CGFloat = 280           // main menu rows
    static let equalizerWidth: CGFloat = 300  // equalizer submenu
    static let leading: CGFloat = 14          // lines up with native item titles
    static let indent: CGFloat = 36           // rows nested under "Son ambiant"
}

// Wraps a SwiftUI view in a menu item, for rows a plain NSMenuItem can't express (sliders, switches, header).
// Rows keep a fixed height: optional lines (the error line, notes) are separate plain items instead.
func hostingMenuItem<Content: View>(width: CGFloat = MenuMetrics.width, @ViewBuilder _ content: () -> Content) -> NSMenuItem {
    let host = NSHostingView(rootView: content().frame(width: width, alignment: .leading))
    host.frame = NSRect(origin: .zero, size: host.fittingSize)
    let item = NSMenuItem()
    item.view = host
    return item
}
```

- [ ] **Step 2 : Écrire `Client/macos/MenuRows/HeaderRow.swift`**

```swift
import SwiftUI

// Menu header: headset name, connection state + codec, battery.
struct HeaderRow: View {
    @ObservedObject var model: HeadphonesModel

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(model.deviceName.isEmpty ? "SonyBridge" : model.deviceName)
                    .font(.system(size: 13, weight: .semibold))
                Text(statusLine)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            Spacer(minLength: 8)
            if model.connected { battery }
        }
        .padding(.horizontal, MenuMetrics.leading)
        .padding(.vertical, 4)
    }

    private var statusLine: String {
        switch model.connectionState {
        case .connecting: return tr("Connecting…")
        case .disconnected: return tr("Not connected")
        case .connected: return model.codec.isEmpty ? tr("Connected") : "\(tr("Connected")) · \(model.codec)"
        }
    }

    @ViewBuilder private var battery: some View {
        if model.hasDualBattery {
            Text(String(format: tr("L %ld%%  R %ld%%"), model.batteryLeft, model.batteryRight))
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        } else if model.batteryLevel >= 0 {
            HStack(spacing: 4) {
                Text(String(format: tr("%ld%%"), model.batteryLevel))
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                Image(systemName: batterySymbol)
                    .foregroundColor(model.batteryLevel <= 20 && !model.batteryCharging ? .red : .secondary)
            }
        }
    }

    private var batterySymbol: String {
        if model.batteryCharging { return "battery.100.bolt" }
        switch model.batteryLevel {
        case ..<13: return "battery.0"
        case ..<38: return "battery.25"
        case ..<63: return "battery.50"
        case ..<88: return "battery.75"
        default: return "battery.100"
        }
    }
}
```

- [ ] **Step 3 : Écrire `Client/macos/MenuRows/AmbientLevelRow.swift`**

```swift
import SwiftUI

// Ambient Sound level slider (1…max), shown under "Son ambiant".
struct AmbientLevelRow: View {
    @ObservedObject var model: HeadphonesModel

    var body: some View {
        HStack(spacing: 8) {
            Slider(
                value: Binding(get: { Double(model.ambientLevel) },
                               set: { model.setLevel(Int($0.rounded()), final: false) }),
                in: 1...Double(max(model.maxAmbientLevel, 2)),
                step: 1,
                onEditingChanged: { editing in
                    if !editing { model.setLevel(model.ambientLevel, final: true) }
                }
            )
            .controlSize(.small)
            Text(verbatim: "\(model.ambientLevel)")
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .foregroundColor(.secondary)
                .frame(width: 20, alignment: .trailing)
        }
        .padding(.leading, MenuMetrics.indent)
        .padding(.trailing, MenuMetrics.leading)
        .padding(.vertical, 2)
        .disabled(!model.connected)
    }
}
```

- [ ] **Step 4 : Écrire `Client/macos/MenuRows/ToggleRow.swift`**

```swift
import SwiftUI

// A title with a switch on the right (Focus on Voice, DSEE, Speak-to-Chat, Adaptive Volume).
struct ToggleRow: View {
    @ObservedObject var model: HeadphonesModel
    let title: String
    var indent: CGFloat = MenuMetrics.leading
    let isOn: (HeadphonesModel) -> Bool
    let set: (HeadphonesModel, Bool) -> Void

    var body: some View {
        HStack {
            Text(title).font(.system(size: 13))
            Spacer(minLength: 8)
            Toggle("", isOn: Binding(get: { isOn(model) }, set: { set(model, $0) }))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
        }
        .padding(.leading, indent)
        .padding(.trailing, MenuMetrics.leading)
        .padding(.vertical, 2)
        .disabled(!model.connected)
        .opacity(model.connected ? 1 : 0.5)
    }
}
```

- [ ] **Step 5 : Écrire `Client/macos/MenuRows/EqualizerRow.swift`**

```swift
import AppKit
import SwiftUI

// Manual equalizer: 10 vertical sliders (WH-1000XM6) or Clear Bass + 5 (older models). Active only on "Manual"
// and when the device's write format is verified (model.equalizerWritable).
struct EqualizerRow: View {
    @ObservedObject var model: HeadphonesModel

    private static let labels5 = ["400", "1k", "2.5k", "6.3k", "16k"]
    private static let labels10 = ["31", "63", "125", "250", "500", "1k", "2k", "4k", "8k", "16k"]

    private var editable: Bool { model.connected && model.equalizerWritable && model.eqPreset == 0xA0 }
    private var labels: [String] { model.eqBands.count == 10 ? Self.labels10 : Self.labels5 }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            if model.eqHasClearBass {
                band(tr("Clear Bass"), value: model.clearBass) { model.setClearBass($0, final: $1) }
            }
            ForEach(Array(model.eqBands.enumerated()), id: \.offset) { index, value in
                band(index < labels.count ? labels[index] : "", value: value) {
                    model.setEqualizerBand(index, value: $0, final: $1)
                }
            }
        }
        .padding(.horizontal, MenuMetrics.leading)
        .padding(.vertical, 6)
    }

    private func band(_ label: String, value: Int, onChange: @escaping (Int, Bool) -> Void) -> some View {
        VStack(spacing: 3) {
            VerticalBandSlider(value: value, enabled: editable, onChange: onChange)
                .frame(width: 20, height: 72)
            Text(verbatim: label)
                .font(.system(size: 9))
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }
}

// A native vertical NSSlider in -10…10. onChange(value, final): final is true on mouse-up.
struct VerticalBandSlider: NSViewRepresentable {
    let value: Int
    let enabled: Bool
    let onChange: (Int, Bool) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onChange: onChange)
    }

    func makeNSView(context: Context) -> NSSlider {
        let slider = NSSlider(value: Double(value), minValue: -10, maxValue: 10,
                              target: context.coordinator, action: #selector(Coordinator.changed(_:)))
        slider.isVertical = true
        slider.isContinuous = true
        slider.controlSize = .small
        return slider
    }

    func updateNSView(_ slider: NSSlider, context: Context) {
        context.coordinator.onChange = onChange
        if Int(slider.doubleValue.rounded()) != value { slider.doubleValue = Double(value) }
        slider.isEnabled = enabled
    }

    final class Coordinator: NSObject {
        var onChange: (Int, Bool) -> Void

        init(onChange: @escaping (Int, Bool) -> Void) {
            self.onChange = onChange
        }

        @objc func changed(_ sender: NSSlider) {
            let final = NSApp.currentEvent?.type == .leftMouseUp
            onChange(Int(sender.doubleValue.rounded()), final)
        }
    }
}
```

- [ ] **Step 6 : Ajouter les nouvelles clés à `Client/macos/fr.lproj/Localizable.strings`** (section « Menu »)

```
"Not connected" = "Non connecté";
"Connected" = "Connecté";
"L %ld%%  R %ld%%" = "G %ld %%  D %ld %%";
"Clear Bass" = "Clear Bass";
```

- [ ] **Step 7 : Branchement provisoire dans le menu minimal** (remplacé entièrement en tâche 6)

Dans `Client/macos/HeadphonesMenu.swift` :
- Remplacer `headerItem.isEnabled = false` / `menu.addItem(headerItem)` par
  `menu.addItem(hostingMenuItem { HeaderRow(model: model) })`, supprimer la propriété `headerItem` et, dans
  `update()`, les lignes qui construisent `header` et affectent `headerItem.title`.
- Dans la boucle des modes, juste après `menu.addItem(item)`, ajouter :

```swift
            if mode == .ambientSound {
                menu.addItem(hostingMenuItem { AmbientLevelRow(model: model) })
                menu.addItem(hostingMenuItem {
                    ToggleRow(model: model, title: tr("Focus on Voice"), indent: MenuMetrics.indent,
                              isOn: { $0.focusOnVoice }, set: { $0.setFocusOnVoice($1) })
                })
            }
```

et la clé `"Focus on Voice" = "Focalisation sur la voix";` dans `Localizable.strings`.

- [ ] **Step 8 : Tests et build**

Run : `make test && make`
Attendu : tout passe, `Localization: 19 keys, all translated` (la clé `"%ld%%"` sert maintenant à
`HeaderRow` ; `update()` ne l'utilise plus), puis `OK -> …`.

- [ ] **Step 9 : Vérifier avec l'utilisateur**

Run : `make run`. Demander à l'utilisateur, casque connecté :
1. L'en-tête montre le nom, « Connecté · AAC » et la batterie avec son icône, bien alignés, sans être coupés.
2. Le curseur de niveau se **fait glisser** dans le menu ouvert, et le son ambiant change dans le casque
   pendant le glissement (au plus toutes les 150 ms) et au relâchement.
3. L'interrupteur « Focalisation sur la voix » bascule, et le menu reste ouvert.
Si le glissement ou l'interrupteur ne réagissent pas dans le menu : **arrêter** et remonter le problème avant
la tâche 6. Toute l'approche en dépend.

- [ ] **Step 10 : Commit** (par l'utilisateur)

```bash
git add -A && git commit -m "feat(macos): SwiftUI menu rows (header, level slider, switches, equalizer)"
```

---

### Task 6: Menu complet (spec §4) + icône selon le mode

**Files:**
- Modify (réécriture complète) : `Client/macos/HeadphonesMenu.swift`, `Client/macos/StatusItemController.swift`
- Create : `Client/macos/StatusIcon.swift`
- Modify : `Client/macos/MenuSupport.swift` (`titleWithValue`), `Client/macos/fr.lproj/Localizable.strings`

**Interfaces:**
- Consumes : tâches 1, 4 et 5.
- Produces :
  - `enum StatusIcon { static func symbolName(for: SHCAmbientMode) -> String; static func image(connected: Bool, mode: SHCAmbientMode) -> NSImage? }`
  - `func titleWithValue(_ title: String, _ value: String, width: CGFloat = MenuMetrics.width - 60) -> NSAttributedString`
  - `HeadphonesMenu` : `private var connectItem` et la méthode `addAppSection()`, où la tâche 7 insère le
    sous-menu des options.

- [ ] **Step 1 : Ajouter `titleWithValue` à `Client/macos/MenuSupport.swift`**

```swift
// "Title        value": the value right-aligned in the secondary color, like "Égaliseur        Graves ›".
func titleWithValue(_ title: String, _ value: String, width: CGFloat = MenuMetrics.width - 60) -> NSAttributedString {
    let paragraph = NSMutableParagraphStyle()
    paragraph.tabStops = [NSTextTab(textAlignment: .right, location: width)]
    let font = NSFont.menuFont(ofSize: 0)
    let text = NSMutableAttributedString(string: title, attributes: [.font: font, .paragraphStyle: paragraph])
    if !value.isEmpty {
        text.append(NSAttributedString(string: "\t" + value, attributes: [
            .font: font, .paragraphStyle: paragraph, .foregroundColor: NSColor.secondaryLabelColor,
        ]))
    }
    return text
}
```

- [ ] **Step 2 : Écrire `Client/macos/StatusIcon.swift`**

```swift
import AppKit

// Menu bar icon: one monochrome SF Symbol per mode, dimmed when disconnected (spec §6.6).
enum StatusIcon {
    static func symbolName(for mode: SHCAmbientMode) -> String {
        switch mode {
        case .noiseCanceling: return "headphones.circle.fill"
        case .ambientSound: return "ear.and.waveform"
        default: return "headphones"
        }
    }

    static func image(connected: Bool, mode: SHCAmbientMode) -> NSImage? {
        let name = connected ? symbolName(for: mode) : "headphones"
        let image = NSImage(systemSymbolName: name, accessibilityDescription: "SonyBridge")
            ?? NSImage(systemSymbolName: "headphones", accessibilityDescription: "SonyBridge")
        image?.isTemplate = true // macOS tints it for light/dark menu bars
        return image
    }
}
```

- [ ] **Step 3 : Réécrire `Client/macos/StatusItemController.swift`**

```swift
import AppKit
import Combine

// Owns the menu bar icon (it follows the mode and connection state) and attaches the headphones menu to it.
final class StatusItemController {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let headphonesMenu: HeadphonesMenu
    private var cancellables = Set<AnyCancellable>()

    init(model: HeadphonesModel) {
        headphonesMenu = HeadphonesMenu(model: model)
        statusItem.menu = headphonesMenu.menu
        model.$connectionState.combineLatest(model.$mode)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state, mode in
                let connected = state == .connected
                self?.statusItem.button?.image = StatusIcon.image(connected: connected, mode: mode)
                self?.statusItem.button?.appearsDisabled = !connected
            }
            .store(in: &cancellables)
    }
}
```

- [ ] **Step 4 : Réécrire `Client/macos/HeadphonesMenu.swift`**

```swift
import AppKit
import Combine

// The status item's menu (spec §4). Built once; update() refreshes states, visibility and values in place,
// including while the menu is open.
final class HeadphonesMenu {
    let menu = NSMenu()
    private let model: HeadphonesModel
    private var cancellables = Set<AnyCancellable>()

    private let errorItem = NSMenuItem()
    private var modeItems: [(SHCAmbientMode, NSMenuItem)] = []
    private var ambientRows: [NSMenuItem] = []            // level slider + focus on voice
    private let equalizerItem = NSMenuItem()
    private var presetItems: [(Int, NSMenuItem)] = []
    private let equalizerNoteItem = NSMenuItem()
    private var equalizerResetItem = NSMenuItem()
    private var dseeItem = NSMenuItem()
    private var speakToChatItem = NSMenuItem()
    private var adaptiveVolumeItem = NSMenuItem()
    private let autoPowerOffItem = NSMenuItem()
    private var autoPowerOffItems: [NSMenuItem] = []
    private let aboutItem = NSMenuItem()
    private let aboutMenu = NSMenu()
    private var connectItem = NSMenuItem()

    private static var presets: [(Int, String)] {
        [(0x00, tr("Off")), (0x10, tr("Bright")), (0x11, tr("Excited")), (0x12, tr("Mellow")),
         (0x13, tr("Relaxed")), (0x14, tr("Vocal")), (0x15, tr("Treble")), (0x16, tr("Bass")),
         (0x17, tr("Speech")), (0xA0, tr("Manual"))]
    }

    // Index = the bridge's auto power-off option (0=Off, 1=5 min, 2=30 min, 3=1 h, 4=3 h, 5=when taken off).
    private static var autoPowerOffOptions: [String] {
        [tr("Off"), tr("5 min"), tr("30 min"), tr("1 hour"), tr("3 hours"), tr("When taken off")]
    }

    init(model: HeadphonesModel) {
        self.model = model
        menu.autoenablesItems = false

        menu.addItem(hostingMenuItem { HeaderRow(model: model) })
        errorItem.isEnabled = false
        menu.addItem(errorItem)
        menu.addItem(.separator())
        addAmbientSection()
        menu.addItem(.separator())
        addSoundSection()
        menu.addItem(.separator())
        addAppSection()

        // objectWillChange fires before the new value is stored; hopping to the main queue reads the new state.
        model.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.update() }
            .store(in: &cancellables)
        update()
    }

    // MARK: - Building

    private func addAmbientSection() {
        menu.addItem(sectionHeader(tr("Ambient Sound Control")))
        let modes: [(SHCAmbientMode, String)] = [
            (.noiseCanceling, tr("Noise Canceling")), (.ambientSound, tr("Ambient Sound")), (.off, tr("Off")),
        ]
        for (mode, title) in modes {
            let item = ActionMenuItem(title) { [weak model] in model?.setMode(mode) }
            item.image = NSImage(systemSymbolName: StatusIcon.symbolName(for: mode), accessibilityDescription: nil)
            modeItems.append((mode, item))
            menu.addItem(item)
            if mode == .ambientSound {
                ambientRows = [
                    hostingMenuItem { AmbientLevelRow(model: model) },
                    hostingMenuItem {
                        ToggleRow(model: model, title: tr("Focus on Voice"), indent: MenuMetrics.indent,
                                  isOn: { $0.focusOnVoice }, set: { $0.setFocusOnVoice($1) })
                    },
                ]
                ambientRows.forEach { menu.addItem($0) }
            }
        }
    }

    private func addSoundSection() {
        let equalizerMenu = NSMenu()
        equalizerMenu.autoenablesItems = false
        for (code, title) in Self.presets {
            let item = ActionMenuItem(title) { [weak model] in model?.setEqualizerPreset(code) }
            presetItems.append((code, item))
            equalizerMenu.addItem(item)
        }
        equalizerMenu.addItem(.separator())
        equalizerMenu.addItem(hostingMenuItem(width: MenuMetrics.equalizerWidth) { EqualizerRow(model: model) })
        equalizerNoteItem.title = tr("Manual equalizer coming soon for this model")
        equalizerNoteItem.isEnabled = false
        equalizerMenu.addItem(equalizerNoteItem)
        equalizerResetItem = ActionMenuItem(tr("Reset")) { [weak model] in model?.resetEqualizer() }
        equalizerMenu.addItem(equalizerResetItem)
        equalizerItem.submenu = equalizerMenu
        menu.addItem(equalizerItem)

        dseeItem = hostingMenuItem {
            ToggleRow(model: model, title: tr("DSEE"), isOn: { $0.dsee }, set: { $0.setDsee($1) })
        }
        speakToChatItem = hostingMenuItem {
            ToggleRow(model: model, title: tr("Speak-to-Chat"), isOn: { $0.speakToChat }, set: { $0.setSpeakToChat($1) })
        }
        adaptiveVolumeItem = hostingMenuItem {
            ToggleRow(model: model, title: tr("Adaptive Volume"), isOn: { $0.adaptiveVolume }, set: { $0.setAdaptiveVolume($1) })
        }
        for item in [dseeItem, speakToChatItem, adaptiveVolumeItem] { menu.addItem(item) }

        let autoPowerOffMenu = NSMenu()
        autoPowerOffMenu.autoenablesItems = false
        for (index, title) in Self.autoPowerOffOptions.enumerated() {
            let item = ActionMenuItem(title) { [weak model] in model?.setAutoPowerOff(index) }
            autoPowerOffItems.append(item)
            autoPowerOffMenu.addItem(item)
        }
        autoPowerOffItem.submenu = autoPowerOffMenu
        menu.addItem(autoPowerOffItem)
    }

    private func addAppSection() {
        aboutItem.title = tr("About the Headphones")
        aboutMenu.autoenablesItems = false
        aboutItem.submenu = aboutMenu
        menu.addItem(aboutItem)
        connectItem = ActionMenuItem(tr("Connect…")) { [weak self] in self?.toggleConnection() }
        menu.addItem(connectItem)
        menu.addItem(.separator())
        menu.addItem(ActionMenuItem(tr("Quit SonyBridge"), key: "q") { NSApp.terminate(nil) })
    }

    // MARK: - Updating

    private func update() {
        let connected = model.connected

        errorItem.isHidden = model.errorMessage == nil
        errorItem.title = "⚠︎ " + (model.errorMessage ?? "")

        for (mode, item) in modeItems {
            item.state = connected && model.mode == mode ? .on : .off
            item.isEnabled = connected
        }
        ambientRows.forEach { $0.isHidden = model.mode != .ambientSound }

        equalizerItem.isHidden = !model.supportsEqualizer
        equalizerItem.isEnabled = connected
        equalizerItem.attributedTitle = titleWithValue(tr("Equalizer"), Self.presetName(model.eqPreset))
        for (code, item) in presetItems {
            item.state = model.eqPreset == code ? .on : .off
            item.isEnabled = connected && model.equalizerWritable
        }
        equalizerNoteItem.isHidden = model.equalizerWritable || model.eqBands.isEmpty
        equalizerResetItem.isEnabled = connected && model.equalizerWritable && model.eqPreset == 0xA0

        dseeItem.isHidden = !model.supportsEqualizer
        speakToChatItem.isHidden = !model.hasSpeakToChat
        adaptiveVolumeItem.isHidden = !model.hasAdaptiveVolume

        let options = Self.autoPowerOffOptions
        autoPowerOffItem.isHidden = !model.hasAutoPowerOff
        autoPowerOffItem.isEnabled = connected
        autoPowerOffItem.attributedTitle = titleWithValue(
            tr("Auto Power-Off"), options.indices.contains(model.autoPowerOff) ? options[model.autoPowerOff] : "")
        for (index, item) in autoPowerOffItems.enumerated() {
            item.state = index == model.autoPowerOff ? .on : .off
        }

        updateAbout()
        aboutItem.isEnabled = connected

        switch model.connectionState {
        case .connected: connectItem.title = tr("Disconnect")
        case .connecting: connectItem.title = tr("Connecting…")
        case .disconnected: connectItem.title = tr("Connect…")
        }
        connectItem.isEnabled = model.connectionState != .connecting
    }

    private func updateAbout() {
        aboutMenu.removeAllItems()
        let rows: [(String, String)] = [
            (tr("Firmware"), model.firmware), (tr("Codec"), model.codec),
            (tr("Protocol"), model.protocolVersion), (tr("Bluetooth"), model.deviceMac),
        ]
        for (title, value) in rows where !value.isEmpty {
            let item = NSMenuItem()
            item.attributedTitle = titleWithValue(title, value)
            item.isEnabled = false
            aboutMenu.addItem(item)
        }
    }

    private static func presetName(_ code: Int) -> String {
        presets.first { $0.0 == code }?.1 ?? tr("Custom")
    }

    private func toggleConnection() {
        if model.connected {
            model.disconnect()
        } else {
            NSApp.activate(ignoringOtherApps: true) // the fallback Bluetooth picker is a modal window
            model.connect()
        }
    }
}
```

- [ ] **Step 5 : Ajouter les clés à `Client/macos/fr.lproj/Localizable.strings`** (section « Menu »)

```
"Equalizer" = "Égaliseur";
"Bright" = "Brillant";
"Excited" = "Dynamique";
"Mellow" = "Doux";
"Relaxed" = "Détendu";
"Vocal" = "Voix";
"Treble" = "Aigus";
"Bass" = "Graves";
"Speech" = "Parole";
"Manual" = "Manuel";
"Custom" = "Personnalisé";
"Manual equalizer coming soon for this model" = "Égaliseur manuel bientôt disponible pour ce modèle";
"Reset" = "Réinitialiser";
"DSEE" = "DSEE";
"Speak-to-Chat" = "Speak-to-Chat";
"Adaptive Volume" = "Volume adaptatif";
"Auto Power-Off" = "Arrêt automatique";
"5 min" = "5 min";
"30 min" = "30 min";
"1 hour" = "1 heure";
"3 hours" = "3 heures";
"When taken off" = "Quand le casque est retiré";
"About the Headphones" = "À propos du casque";
"Firmware" = "Firmware";
"Codec" = "Codec";
"Protocol" = "Protocole";
"Bluetooth" = "Bluetooth";
```

- [ ] **Step 6 : Tests et build**

Run : `make test && make`
Attendu : tout passe, `Localization: 46 keys, all translated`, puis `OK -> …`.

- [ ] **Step 7 : Vérifier avec l'utilisateur** (casque connecté, `make run`)

Parcourir le menu avec lui, dans l'ordre de la spec §4 :
1. L'icône de la barre change avec le mode (réduction de bruit / son ambiant / désactivé) et se grise une
   fois déconnecté. **Lui montrer les 3 glyphes** et demander s'ils lui conviennent (sinon, changer les noms de
   symboles dans `StatusIcon.symbolName`).
2. Le curseur et « Focalisation sur la voix » n'apparaissent qu'en « Son ambiant ».
3. « Égaliseur » affiche « Personnalisé » à droite (preset `0x30` du XM6). Le sous-menu montre les presets
   grisés, 10 curseurs grisés, et « Égaliseur manuel bientôt disponible pour ce modèle ».
4. DSEE et Speak-to-Chat sont présents ; Volume adaptatif est absent (le XM6 ne le gère pas).
5. « Arrêt automatique » affiche l'option en cours à droite ; changer d'option déplace la coche.
6. « À propos du casque » : Firmware 3.1.5, Codec AAC, Protocole v2, adresse Bluetooth.
7. Déconnecter : les réglages restent affichés mais grisés, et l'en-tête dit « Non connecté ».
8. Les valeurs à droite sont bien alignées et le menu n'est pas trop large (sinon, ajuster
   `MenuMetrics.width` et le `width` de `titleWithValue`).

- [ ] **Step 8 : Commit** (par l'utilisateur)

```bash
git add -A && git commit -m "feat(macos): full headphones menu with per-mode status icon"
```

---

### Task 7: Options — connexion auto, reconnexion auto, lancement à l'ouverture de session

**Files:**
- Create : `Client/macos/AppSettings.swift`, `Client/macos/DeviceWatcher.swift`
- Modify : `Client/macos/MacOSBluetoothConnector.h/.mm` (coupure de liaison sûre),
  `Client/macos/HeadphonesBridge.h/.mm` (connexion par adresse, aides de classe),
  `Client/macos/HeadphonesModel.swift`, `Client/macos/HeadphonesMenu.swift`,
  `Client/macos/StatusItemController.swift`, `Client/macos/AppDelegate.swift`,
  `Client/macos/fr.lproj/Localizable.strings`

**Interfaces:**
- Consumes : `ReconnectPolicy` (tâche 2), `HeadphonesModel.handleConnectResult(ok:error:userInitiated:)` et
  `linkLost()` (tâche 4), `HeadphonesMenu.addAppSection()` (tâche 6).
- Produces :
  - `final class AppSettings: ObservableObject { var autoConnect: Bool; var autoReconnect: Bool; private(set) var launchAtLogin: Bool; var lastDeviceAddress: String?; func setLaunchAtLogin(_ enabled: Bool) -> String? }`
  - `final class DeviceWatcher { var onConnect: ((String, String) -> Void)?; var onDisconnect: ((String) -> Void)?; func start() }` (adresse, nom)
  - `HeadphonesBridge` (Swift) : `looksLikeSonyHeadset(_:)`, `connectedSonyHeadsetAddress()`,
    `isDeviceConnectedToMac(_:)`, `connect(toAddress:completion:)`
  - `HeadphonesModel` : `var settings: AppSettings?`, `autoConnectOnLaunch()`, `autoConnect(toAddress:)`,
    `headsetConnectedToMac(address:name:)`, `headsetDisconnectedFromMac(address:)`, `cancelReconnect()`
  - `StatusItemController(model:settings:)`, `HeadphonesMenu(model:settings:)`

- [ ] **Step 1 : Rendre la coupure de liaison sûre dans `MacOSBluetoothConnector`**

Aujourd'hui, quand le casque ferme le canal, `rfcommChannelClosed` appelle `disconnect()` **sur le fil du
connecteur lui-même**, et `disconnect()` fait `uthread.join()` : un fil qui s'attend lui-même lève une
exception dans une fonction `noexcept`, donc l'app plante. Une reconnexion ferait aussi `uthread = std::thread(…)`
sur un fil encore « joignable », ce qui plante aussi. À corriger avant toute reconnexion automatique.

`Client/macos/MacOSBluetoothConnector.h` :
- ajouter, sous `virtual void closeConnection();` :

```cpp
    // Called from the channel-closed callback, on the connector thread: stops that thread's loop without joining it.
    void markClosed() noexcept;
```

- initialiser les pointeurs privés : `void *rfcommDevice = nullptr;` et `void *rfcommchannel = nullptr;`.

`Client/macos/MacOSBluetoothConnector.mm` :
- dans `rfcommChannelClosed:`, remplacer `delegateCPP->disconnect();` par `delegateCPP->markClosed();`
- remplacer le destructeur, `disconnect()` et le début de `connect()` :

```objc
MacOSBluetoothConnector::~MacOSBluetoothConnector()
{
    disconnect();
}

void MacOSBluetoothConnector::markClosed() noexcept
{
    running = false;
    disconnectionConditionVariable.notify_all();
}

void MacOSBluetoothConnector::disconnect() noexcept
{
    closeConnection();
    markClosed();
    // Never join from the connector thread itself (the channel-closed callback runs there).
    if (uthread.joinable() && uthread.get_id() != std::this_thread::get_id()) {
        uthread.join();
    }
}
```

et, en première ligne de `MacOSBluetoothConnector::connect(const std::string& addrStr)` :

```objc
    // A previous link's thread has stopped (markClosed) but may not have been joined yet.
    if (uthread.joinable()) uthread.join();
```

- dans `closeConnection()`, ajouter en première ligne `if (!rfcommchannel) return;`.

- [ ] **Step 2 : Connexion par adresse dans le pont**

`Client/macos/HeadphonesBridge.h`, sous `scanAndConnectWithCompletion:` :

```objc
// Name heuristic for Sony headsets (WH-/WF-/WI-/MDR-/XB/LinkBuds).
+ (BOOL)looksLikeSonyHeadset:(NSString *)name NS_SWIFT_NAME(looksLikeSonyHeadset(_:));
// Address of the first Sony headset currently connected to macOS, or nil.
+ (nullable NSString *)connectedSonyHeadsetAddress NS_SWIFT_NAME(connectedSonyHeadsetAddress());
// YES if the device with this address is connected to macOS (its audio link is up).
+ (BOOL)isDeviceConnectedToMac:(NSString *)address NS_SWIFT_NAME(isDeviceConnectedToMac(_:));
// Opens the control channel to a specific device, without the picker. Completion on the main thread.
- (void)connectToAddress:(NSString *)address
              completion:(void (^)(BOOL ok, NSString * _Nullable error))completion NS_SWIFT_NAME(connect(toAddress:completion:));
```

`Client/macos/HeadphonesBridge.mm` : dans `scanAndConnectWithCompletion:`, remplacer tout le code qui suit le
test `if (!device) { … return; }` (le `try { _bt->connect(…) }`, la boucle d'attente, et la création de `_hp`
jusqu'à `completion(YES, nil);`) par `[self connectDevice:device completion:completion];`, puis ajouter après
la méthode :

```objc
- (void)connectDevice:(IOBluetoothDevice *)device completion:(void (^)(BOOL, NSString * _Nullable))completion {
    try {
        _bt->connect([[device addressString] UTF8String]);
    } catch (RecoverableException &exc) {
        completion(NO, @(exc.what()));
        return;
    }

    // A real RFCOMM open (SDP + link setup, sometimes with encryption renegotiation) can take a few
    // seconds; pump the run loop until it lands or we give up.
    int timeout = 80;
    while (!_bt->isConnected() && timeout >= 0) {
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
        timeout--;
    }

    if (!_bt->isConnected()) {
        _bt->disconnect();
        completion(NO, NSLocalizedString(@"Connection timed out.", nil));
        return;
    }

    _deviceName = [device nameOrAddress];
    _deviceMac = [device addressString];
    _hp = std::make_unique<Headphones>(*_bt);
    completion(YES, nil);
}

+ (BOOL)looksLikeSonyHeadset:(NSString *)name {
    return SHCLooksLikeSonyHeadset(name);
}

+ (nullable NSString *)connectedSonyHeadsetAddress {
    for (IOBluetoothDevice *paired in [IOBluetoothDevice pairedDevices]) {
        if ([paired isConnected] && SHCLooksLikeSonyHeadset([paired name])) return [paired addressString];
    }
    return nil;
}

+ (BOOL)isDeviceConnectedToMac:(NSString *)address {
    IOBluetoothDevice *device = [IOBluetoothDevice deviceWithAddressString:address];
    return device != nil && [device isConnected];
}

- (void)connectToAddress:(NSString *)address completion:(void (^)(BOOL, NSString * _Nullable))completion {
    IOBluetoothDevice *device = [IOBluetoothDevice deviceWithAddressString:address];
    if (!device) {
        completion(NO, NSLocalizedString(@"Not connected.", nil));
        return;
    }
    [self connectDevice:device completion:completion];
}
```

- [ ] **Step 3 : Écrire `Client/macos/AppSettings.swift`**

```swift
import Foundation
import ServiceManagement

// The three user options, persisted in UserDefaults. Launch at login is backed by SMAppService (macOS 13+).
final class AppSettings: ObservableObject {
    private enum Keys {
        static let autoConnect = "autoConnect"
        static let autoReconnect = "autoReconnect"
        static let lastDeviceAddress = "lastDeviceAddress"
    }

    private let defaults: UserDefaults

    @Published var autoConnect: Bool {
        didSet { defaults.set(autoConnect, forKey: Keys.autoConnect) }
    }
    @Published var autoReconnect: Bool {
        didSet { defaults.set(autoReconnect, forKey: Keys.autoReconnect) }
    }
    @Published private(set) var launchAtLogin: Bool

    var lastDeviceAddress: String? {
        get { defaults.string(forKey: Keys.lastDeviceAddress) }
        set { defaults.set(newValue, forKey: Keys.lastDeviceAddress) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // Spec §4: auto-connect and auto-reconnect default on; launch at login stays off until the user asks.
        defaults.register(defaults: [Keys.autoConnect: true, Keys.autoReconnect: true])
        autoConnect = defaults.bool(forKey: Keys.autoConnect)
        autoReconnect = defaults.bool(forKey: Keys.autoReconnect)
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    // Returns an error message if macOS refused the change.
    func setLaunchAtLogin(_ enabled: Bool) -> String? {
        defer { launchAtLogin = SMAppService.mainApp.status == .enabled }
        do {
            if enabled {
                try SMAppService.mainApp.register()
                if SMAppService.mainApp.status == .requiresApproval {
                    SMAppService.openSystemSettingsLoginItems()
                }
            } else {
                try SMAppService.mainApp.unregister()
            }
            return nil
        } catch {
            return error.localizedDescription
        }
    }
}
```

- [ ] **Step 4 : Écrire `Client/macos/DeviceWatcher.swift`**

```swift
import Foundation
import IOBluetooth

// Reports Bluetooth devices connecting to / disconnecting from macOS, as (address, name).
final class DeviceWatcher: NSObject {
    var onConnect: ((_ address: String, _ name: String) -> Void)?
    var onDisconnect: ((_ address: String) -> Void)?

    private var connectNotification: IOBluetoothUserNotification?
    private var disconnectNotifications: [String: IOBluetoothUserNotification] = [:]

    func start() {
        connectNotification = IOBluetoothDevice.register(forConnectNotifications: self,
                                                         selector: #selector(deviceConnected(_:device:)))
        for case let device as IOBluetoothDevice in IOBluetoothDevice.pairedDevices() ?? [] where device.isConnected() {
            if let address = device.addressString { watchDisconnect(device, address: address) }
        }
    }

    @objc private func deviceConnected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        guard let address = device.addressString else { return }
        watchDisconnect(device, address: address)
        onConnect?(address, device.name ?? "")
    }

    @objc private func deviceDisconnected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        notification.unregister()
        guard let address = device.addressString else { return }
        disconnectNotifications[address] = nil
        onDisconnect?(address)
    }

    private func watchDisconnect(_ device: IOBluetoothDevice, address: String) {
        guard disconnectNotifications[address] == nil else { return }
        disconnectNotifications[address] = device.register(forDisconnectNotification: self,
                                                            selector: #selector(deviceDisconnected(_:device:)))
    }
}
```

- [ ] **Step 5 : Connexion et reconnexion automatiques dans `Client/macos/HeadphonesModel.swift`**

Ajouter sous `private var eqThrottle = SendThrottle()` :

```swift
    // Set by AppDelegate; nil means "no automatic behaviour".
    var settings: AppSettings?
    private var reconnectPolicy = ReconnectPolicy()
    private var reconnectTimer: Timer?
    private var reconnectAddress: String?
    private var userDisconnected = false // after "Déconnecter": no auto-reconnect until the headset reconnects to macOS
```

Dans `connect()`, ajouter en première ligne :

```swift
        userDisconnected = false
        cancelReconnect()
```

Remplacer `disconnect()`, `handleConnectResult(ok:error:userInitiated:)` et `linkLost()` par :

```swift
    func disconnect() {
        userDisconnected = true
        cancelReconnect()
        stopTimers()
        bridge.disconnect()
        connectionState = .disconnected
    }

    func handleConnectResult(ok: Bool, error: String?, userInitiated: Bool) {
        guard ok else {
            connectionState = .disconnected
            if userInitiated, let error = error { errorMessage = error }
            if !userInitiated && reconnectAddress != nil { scheduleReconnect() }
            return
        }
        cancelReconnect()
        connectionState = .connected
        syncFromBridge()
        settings?.lastDeviceAddress = deviceMac
        bridge.refreshStatus { [weak self] in self?.syncFromBridge() } // called after reads, then after probes
        startTimers()
    }

    // The control link dropped on its own (idle power-save): retry while the headset is still connected to macOS.
    func linkLost() {
        stopTimers()
        bridge.disconnect() // resets sequence numbers and buffers for the next connection
        connectionState = .disconnected
        guard settings?.autoReconnect == true, !userDisconnected, !deviceMac.isEmpty else { return }
        reconnectAddress = deviceMac
        scheduleReconnect()
    }

    // MARK: - Automatic connection

    // Not user-initiated: failures stay silent (normal while the headset sleeps).
    func autoConnect(toAddress address: String) {
        guard connectionState == .disconnected else { return }
        connectionState = .connecting
        bridge.connect(toAddress: address) { ok, error in
            self.handleConnectResult(ok: ok, error: error, userInitiated: false)
        }
    }

    // At launch: the last headset if macOS has it connected, else any connected Sony headset.
    func autoConnectOnLaunch() {
        let remembered = settings?.lastDeviceAddress.flatMap { HeadphonesBridge.isDeviceConnectedToMac($0) ? $0 : nil }
        if let address = remembered ?? HeadphonesBridge.connectedSonyHeadsetAddress() {
            autoConnect(toAddress: address)
        }
    }

    // DeviceWatcher: a device just connected to macOS.
    func headsetConnectedToMac(address: String, name: String) {
        guard settings?.autoConnect == true, HeadphonesBridge.looksLikeSonyHeadset(name),
              connectionState == .disconnected else { return }
        userDisconnected = false
        cancelReconnect()
        // Give the audio link ~2 s to settle before opening the control channel.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.autoConnect(toAddress: address) }
    }

    // DeviceWatcher: a device left macOS; stop retrying it (headsetConnectedToMac takes over when it's back).
    func headsetDisconnectedFromMac(address: String) {
        if address == reconnectAddress { cancelReconnect() }
    }

    func cancelReconnect() {
        reconnectTimer?.invalidate()
        reconnectTimer = nil
        reconnectAddress = nil
        reconnectPolicy.reset()
    }

    private func scheduleReconnect() {
        guard let address = reconnectAddress else { return }
        reconnectTimer?.invalidate()
        let timer = Timer(timeInterval: reconnectPolicy.nextDelay(), repeats: false) { [weak self] _ in
            guard let self = self else { return }
            guard HeadphonesBridge.isDeviceConnectedToMac(address) else { self.cancelReconnect(); return }
            self.autoConnect(toAddress: address)
        }
        RunLoop.main.add(timer, forMode: .common)
        reconnectTimer = timer
    }
```

- [ ] **Step 6 : Sous-menu « Options de SonyBridge » dans `Client/macos/HeadphonesMenu.swift`**

- Remplacer `init(model: HeadphonesModel) {` / `self.model = model` par :

```swift
    init(model: HeadphonesModel, settings: AppSettings) {
        self.model = model
        self.settings = settings
```

- Ajouter les propriétés, sous `private let model: HeadphonesModel` :

```swift
    private let settings: AppSettings
    private var launchAtLoginItem = NSMenuItem()
    private var autoConnectItem = NSMenuItem()
    private var autoReconnectItem = NSMenuItem()
```

- Dans `init`, après l'abonnement à `model.objectWillChange`, ajouter :

```swift
        settings.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.update() }
            .store(in: &cancellables)
```

- Dans `addAppSection()`, juste avant `connectItem = ActionMenuItem(…)`, ajouter :

```swift
        let optionsMenu = NSMenu()
        optionsMenu.autoenablesItems = false
        launchAtLoginItem = ActionMenuItem(tr("Launch at Login")) { [weak self] in self?.toggleLaunchAtLogin() }
        autoConnectItem = ActionMenuItem(tr("Connect Automatically")) { [weak settings] in settings?.autoConnect.toggle() }
        autoReconnectItem = ActionMenuItem(tr("Reconnect Automatically")) { [weak settings] in settings?.autoReconnect.toggle() }
        for item in [launchAtLoginItem, autoConnectItem, autoReconnectItem] { optionsMenu.addItem(item) }
        let optionsItem = NSMenuItem(title: tr("SonyBridge Options"), action: nil, keyEquivalent: "")
        optionsItem.submenu = optionsMenu
        menu.addItem(optionsItem)
```

- À la fin de `update()`, ajouter :

```swift
        launchAtLoginItem.state = settings.launchAtLogin ? .on : .off
        autoConnectItem.state = settings.autoConnect ? .on : .off
        autoReconnectItem.state = settings.autoReconnect ? .on : .off
```

- Ajouter la méthode :

```swift
    private func toggleLaunchAtLogin() {
        if let error = settings.setLaunchAtLogin(!settings.launchAtLogin) { model.showError(error) }
    }
```

- [ ] **Step 7 : Assembler dans `StatusItemController` et `AppDelegate`**

`Client/macos/StatusItemController.swift` : remplacer `init(model: HeadphonesModel) {` par
`init(model: HeadphonesModel, settings: AppSettings) {` et `HeadphonesMenu(model: model)` par
`HeadphonesMenu(model: model, settings: settings)`.

Réécrire `Client/macos/AppDelegate.swift` :

```swift
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = HeadphonesModel()
    private let settings = AppSettings()
    private let deviceWatcher = DeviceWatcher()
    private var statusItemController: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        model.settings = settings
        statusItemController = StatusItemController(model: model, settings: settings)

        deviceWatcher.onConnect = { [weak self] address, name in
            self?.model.headsetConnectedToMac(address: address, name: name)
        }
        deviceWatcher.onDisconnect = { [weak self] address in
            self?.model.headsetDisconnectedFromMac(address: address)
        }
        deviceWatcher.start()

        if settings.autoConnect { model.autoConnectOnLaunch() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.disconnect()
    }
}
```

- [ ] **Step 8 : Ajouter les clés à `Client/macos/fr.lproj/Localizable.strings`**

```
"SonyBridge Options" = "Options de SonyBridge";
"Launch at Login" = "Lancer à l’ouverture de session";
"Connect Automatically" = "Connexion automatique";
"Reconnect Automatically" = "Reconnexion automatique";
```

- [ ] **Step 9 : Tests et build**

Run : `make test && make`
Attendu : tout passe, `Localization: 50 keys, all translated`, puis `OK -> …`.

- [ ] **Step 10 : Vérifier avec l'utilisateur** (`make run DEBUG=1`)

1. **Connexion au lancement** : XM6 connecté à macOS, quitter puis relancer l'app → elle se connecte seule, sans
   clic (en-tête « Connecté · AAC »).
2. **Connexion auto** : éteindre le casque, puis le rallumer → environ 2 s après la connexion audio, l'app se
   connecte seule.
3. **Déconnexion manuelle** : « Déconnecter » → pas de reconnexion ; éteindre puis rallumer le casque → l'app
   se reconnecte.
4. **Reconnexion auto** : laisser le casque connecté sans audio jusqu'à ce que le canal de contrôle se coupe
   (plusieurs minutes) → l'app **ne plante pas** et se reconnecte ; vérifier les essais avec
   `grep -c '\[connect\] openRFCOMMChannelAsync' build/app.log`.
5. **Options** : décocher « Connexion automatique », quitter, relancer → l'option reste décochée et l'app ne
   se connecte pas seule.
6. **Lancement à l'ouverture de session** : `cp -R build/SonyBridge.app /Applications/`, lancer la copie de
   `/Applications`, cocher l'option → elle apparaît dans Réglages Système › Général › Ouverture ; fermer la
   session puis la rouvrir → l'icône revient seule. Si macOS demande une approbation, les Réglages s'ouvrent
   sur la bonne page.

- [ ] **Step 11 : Commit** (par l'utilisateur)

```bash
git add -A && git commit -m "feat(macos): auto-connect, auto-reconnect and launch at login (menu options)"
```

---

### Task 8: Expérimentations XM6 + écriture de l'égaliseur (spec §7)

Tâche **avec l'utilisateur et le casque**. On confirme d'abord chaque format sur le matériel, puis on active
l'écriture de l'égaliseur. Un menu « Debug » (compilé seulement avec `make run DEBUG=1`) permet d'envoyer une
trame brute ; les réponses du casque arrivent dans `build/app.log`. Ce menu n'est qu'un outil de diagnostic,
en anglais : ses textes ne sont pas traduits.

**Files:**
- Modify : `Client/macos/HeadphonesBridge.h/.mm` (`sendRawPayload:completion:`, `equalizerWritable`)
- Modify : `Client/macos/HeadphonesModel.swift` (`sendRaw(hex:)`), `Client/macos/HeadphonesMenu.swift` (menu Debug)
- Modify : `Client/ProtocolParsers.h/.cpp` (`buildCustomEqualizer`), `Client/Headphones.cpp`
  (`setEqualizerCustom`), `Client/tests/ProtocolParsersTests.cpp`
- Create : `docs/xm6-protocol-notes.md` (résultats des expériences)

**Interfaces:**
- Produces : `Buffer ProtocolParsers::buildCustomEqualizer(unsigned char manualPreset, bool hasClearBass, int clearBass, const std::vector<int>& bands)` ;
  `HeadphonesBridge.sendRawPayload(_:completion:)` ; `HeadphonesModel.sendRaw(hex:)` (seulement avec `DEBUG_PROTOCOL`).

- [ ] **Step 1 : Envoi brut dans le pont**

`Client/macos/HeadphonesBridge.h` :

```objc
// Diagnostics: sends a raw payload (e.g. 56 00) and waits for the ACK; replies are hex-dumped to the log when
// built with DEBUG_PROTOCOL. Only reachable from the Debug menu of `make run DEBUG=1` builds.
- (void)sendRawPayload:(NSData *)payload completion:(void (^)(BOOL ok, NSString * _Nullable error))completion;
```

`Client/macos/HeadphonesBridge.mm` :

```objc
- (void)sendRawPayload:(NSData *)payload completion:(void (^)(BOOL, NSString * _Nullable))completion {
    if (!_hp || !self.connected) { completion(NO, NSLocalizedString(@"Not connected.", nil)); return; }
    std::vector<char> bytes((const char *)payload.bytes, (const char *)payload.bytes + payload.length);
    BluetoothWrapper *bt = _bt.get();
    dispatch_async(_cmdQueue, ^{
        NSString *error = nil; BOOL ok = YES;
        try { bt->sendCommand(bytes); } catch (std::exception &exc) { ok = NO; error = @(exc.what()); }
        dispatch_async(dispatch_get_main_queue(), ^{ completion(ok, error); });
    });
}
```

- [ ] **Step 2 : Menu Debug**

`Client/macos/HeadphonesModel.swift`, dans la section « Actions » :

```swift
    #if DEBUG_PROTOCOL
    // Debug menu only: sends raw bytes like "56 00"; the replies are logged to build/app.log.
    func sendRaw(hex: String) {
        let bytes = hex.split(whereSeparator: { $0 == " " || $0 == "," }).compactMap { UInt8($0, radix: 16) }
        guard !bytes.isEmpty else { return }
        bridge.sendRawPayload(Data(bytes)) { [weak self] ok, error in self?.finish(ok, error) }
    }
    #endif
```

`Client/macos/HeadphonesMenu.swift` : dans `addAppSection()`, juste avant `menu.addItem(.separator())` qui
précède « Quitter », ajouter :

```swift
        #if DEBUG_PROTOCOL
        menu.addItem(ActionMenuItem("Debug: send frame…") { [weak self] in self?.promptRawFrame() })
        #endif
```

et la méthode :

```swift
    #if DEBUG_PROTOCOL
    // Diagnostics only (not localized): asks for a hex payload and sends it as-is.
    private func promptRawFrame() {
        let alert = NSAlert()
        alert.messageText = "Send raw payload (hex)"
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.placeholderString = "56 00"
        alert.accessoryView = field
        alert.addButton(withTitle: "Send")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn { model.sendRaw(hex: field.stringValue) }
    }
    #endif
```

Run : `make test && make run DEBUG=1` → le menu montre « Debug: send frame… ». Envoyer `56 00` → dans
`build/app.log`, une ligne `[recv] 3e 0c … 57 00 …`.

- [ ] **Step 3 : Expérience E1, les 2 octets de plus du canal `0x19`**

L'utilisateur passe par les trois modes **avec le bouton du casque**, en attendant 3 s entre chaque, puis :
`grep -E '\[recv\].* 6[79] 19' build/app.log | tail -6`.
Noter dans `docs/xm6-protocol-notes.md` la valeur des octets 8 et 9 pour chaque mode. Aucun changement de code
n'est prévu : ces octets ne servent qu'à documenter (par exemple une option de l'optimiseur NC, hors
périmètre).

- [ ] **Step 4 : Expérience E2, lecture de l'égaliseur**

L'utilisateur règle l'égaliseur dans l'app Sony (Sound Connect) sur son téléphone, puis envoie `56 00` depuis
« Debug: send frame… », pour chacun de ces réglages : « Désactivé », « Bass Boost » (Graves), « Bright »
(Brillant), puis « Manuel » avec **31 Hz au maximum, 16 kHz au minimum, le reste à 0**.
Pour chaque réglage : `grep '\[recv\].* 57 00' build/app.log | tail -1`. Noter l'identifiant de preset (octet 3)
et les 10 valeurs. Conclure :
- le décalage : avec 31 Hz au max, la 1ʳᵉ valeur doit valoir `0x14` (20) si la plage est −10…+10 (décalage 10),
  ou `0x0c` (12) si elle est −6…+6 (décalage 6) ;
- les identifiants de presets du XM6 (comparer avec `0x00, 0x10…0x17, 0xa0`).
Si l'app Sony ne peut pas se connecter pendant que le Mac est connecté, fermer SonyBridge pendant chaque
réglage, puis relancer l'app et relire.

- [ ] **Step 5 : Expérience E3, écriture d'un preset**

Avec l'identifiant de « Bass Boost » trouvé en E2 (noté `<id>`) : envoyer `58 00 <id> 00`. L'utilisateur doit
**entendre** plus de basses. Relire avec `56 00` : l'octet 3 de la réponse doit valoir `<id>`. Remettre ensuite
le preset d'origine de la même façon.

- [ ] **Step 6 : Expérience E4, écriture de l'égaliseur manuel 10 bandes**

Volume modéré. Envoyer `58 00 a0 0a 0d 0a 0a 0a 0a 0a 0a 0a 0a 0a` (31 Hz à +3 si le décalage est 10, le reste
à 0 ; adapter les valeurs si E2 a trouvé un autre décalage). Relire avec `56 00`. Attendu :
`57 00 a0 0a 0d 0a 0a 0a 0a 0a 0a 0a 0a 0a`. Si l'octet 3 de la réponse n'est pas `a0` (par exemple `a1` pour
un « Personnalisé 1 »), noter cet identifiant : c'est le preset « Manuel » du XM6.

- [ ] **Step 7 : Expérience E5, les autres écritures**

Depuis le menu : basculer DSEE, changer « Arrêt automatique », basculer Speak-to-Chat. Après chaque
changement, relire avec respectivement `e6 01`, `26 05`, `f6 0c` : la réponse (`e7 01 …`, `27 05 …`,
`f7 0c …`) doit refléter la nouvelle valeur.

- [ ] **Step 8 : Point de décision (avec l'utilisateur)**

Écrire les résultats E1 à E5 dans `docs/xm6-protocol-notes.md` (un tableau : trame envoyée, trame reçue,
conclusion). **Si E3 ou E4 contredisent les hypothèses** (aucun effet audible, ou une relecture différente de
ce qui a été envoyé) : **arrêter**, présenter les trames à l'utilisateur et replanifier l'écriture de
l'égaliseur. Les étapes 9 à 13 supposent que E2 à E4 ont confirmé les formats.

- [ ] **Step 9 : Test du constructeur de trame** — ajouter à `Client/tests/ProtocolParsersTests.cpp`, avant
le bloc `// --- Framing ---` :

```cpp
	// --- Custom equalizer write ---
	// 5 bands + Clear Bass (verified WH-CH720N format): 58 00 a0 06 <bass+10> <b1..b5 +10>
	CHECK(buildCustomEqualizer(0xa0, true, 3, { -2, -1, 0, 1, 2 }) == bytes({ 0x58, 0x00, 0xa0, 0x06, 13, 8, 9, 10, 11, 12 }));
	// 10 bands (WH-1000XM6, confirmed by experiment E4): 58 00 a0 0a <b1..b10 +10>
	CHECK(buildCustomEqualizer(0xa0, false, 0, { 3, 0, 0, 0, 0, 0, 0, 0, 0, -10 })
		== bytes({ 0x58, 0x00, 0xa0, 0x0a, 13, 10, 10, 10, 10, 10, 10, 10, 10, 0 }));
	// Values are clamped to -10..10.
	CHECK(buildCustomEqualizer(0xa0, false, 0, { 15, -15 }) == bytes({ 0x58, 0x00, 0xa0, 0x02, 20, 0 }));
```

Si E2 a trouvé un décalage différent de 10, ou E4 un autre identifiant « Manuel », adapter les octets attendus
de la 2ᵉ assertion aux trames réellement confirmées.
Run : `make test` → échec : `use of undeclared identifier 'buildCustomEqualizer'`.

- [ ] **Step 10 : Écrire le constructeur**

`Client/ProtocolParsers.h`, dans le namespace :

```cpp
	// "58 00 <manualPreset> <count> [<clearBass+10>] <bands+10...>", each value clamped to -10..10.
	Buffer buildCustomEqualizer(unsigned char manualPreset, bool hasClearBass, int clearBass, const std::vector<int>& bands);
```

`Client/ProtocolParsers.cpp`, dans le namespace :

```cpp
	Buffer buildCustomEqualizer(unsigned char manualPreset, bool hasClearBass, int clearBass, const std::vector<int>& bands)
	{
		auto encode = [](int v) { return (char)(unsigned char)(std::max(-10, std::min(10, v)) + 10); };
		Buffer cmd = { (char)V2Command::EQ_SET, 0x00, (char)manualPreset, 0x00 };
		if (hasClearBass) cmd.push_back(encode(clearBass));
		for (int band : bands) cmd.push_back(encode(band));
		cmd[3] = (char)(cmd.size() - 4);
		return cmd;
	}
```

Run : `make test` → `ProtocolParsersTests: all passed`.

- [ ] **Step 11 : Utiliser le constructeur et ouvrir l'écriture**

`Client/Headphones.cpp`, dans `Headphones::setEqualizerCustom`, remplacer la construction manuelle de `cmd` (le
lambda `clamp`, le `Buffer cmd = { … }` et la boucle `push_back`) et l'envoi par :

```cpp
	this->_conn.sendCommand(ProtocolParsers::buildCustomEqualizer(
		static_cast<unsigned char>(EQ_PRESET::MANUAL), this->_eqHasClearBass, clearBass, bands));
```

(garder la mise à jour de `_eqPreset`, `_eqClearBass` et `_eqBands` qui suit).

`Client/macos/HeadphonesBridge.mm`, remplacer l'implémentation de `equalizerWritable` et son commentaire par :

```objc
// Both layouts have a verified write format: 5 bands + Clear Bass (WH-CH720N) and 10 bands (WH-1000XM6,
// docs/xm6-protocol-notes.md). Nothing is writable before the first equalizer read.
- (BOOL)equalizerWritable { return self.supportsEqualizer && _hp && _hp->getEqualizerBandCount() > 0; }
```

Si E2 a montré que le XM6 utilise d'autres identifiants de presets, remplacer les codes de
`HeadphonesMenu.presets` par ceux trouvés, et retirer du tableau les presets que le XM6 n'a pas (avec leur
traduction s'ils ne servent plus).

- [ ] **Step 12 : Tests, build, vérification avec l'utilisateur**

Run : `make test && make run DEBUG=1`. Demander à l'utilisateur :
1. Dans « Égaliseur », les presets ne sont plus grisés, et la mention « bientôt disponible » a disparu.
2. Choisir « Graves » : le son change, et la coche suit.
3. Choisir « Manuel », puis faire glisser un curseur : le son change pendant le glissement, et la valeur
   reste après le relâchement.
4. Déconnecter puis reconnecter : l'égaliseur relu est celui qui a été réglé.

- [ ] **Step 13 : Commit** (par l'utilisateur)

```bash
git add -A && git commit -m "feat(xm6): equalizer writes (presets + 10-band manual) confirmed on hardware; debug frame sender"
```

---

### Task 9: README, vérification finale et CI

**Files:**
- Modify : `README.md`

- [ ] **Step 1 : Mettre le README à jour**

- Ligne d'accroche (en gras, sous la bannière) :
  `**An unofficial, open-source macOS menu bar app for Sony headphones — Noise Cancelling, Ambient Sound, EQ, DSEE and battery, without the phone.**`
- Section « ✨ Features » :
  - remplacer la ligne « 🎛️ **Equalizer** … » par
    `- 🎛️ **Equalizer** — presets *and* a **Manual mode** (10 bands on WH-1000XM6, 5 bands + Clear Bass on older models)`
  - remplacer la ligne « 🖼️ **Device hero image** … » par
    `- 📍 **Lives in the menu bar** — a native macOS menu; the icon shows the current mode`
  - remplacer la ligne « 🔌 **Auto-connect** … » par
    `- 🔌 **Auto-connect & auto-reconnect**, plus **Launch at Login** — each one can be turned off`
  - remplacer la ligne « 🌑 **Modern UI** … » par `- 🌍 **English & French**`
- Section « 🎧 Supported headphones » : si la tâche 8 a confirmé les formats, déplacer `WH-1000XM6` de la ligne
  « Expected » vers la ligne « Verified ».

- [ ] **Step 2 : Chercher les restes de l'ancienne app**

Run :
`grep -rnE 'xcodeproj|xcodebuild|ContentView|Main\.storyboard|HeadphonesUIFactory' --exclude-dir=.git --exclude-dir=build --exclude-dir=superpowers . || echo clean`
Attendu : `clean`. Sinon, corriger chaque occurrence.

- [ ] **Step 3 : Build de release**

Run : `make clean && make test && make release && lipo -archs build/SonyBridge.app/Contents/MacOS/SonyBridge`
Attendu : tout passe, `build/SonyBridge.zip` existe, et `lipo` affiche `x86_64 arm64`.

- [ ] **Step 4 : Checklist manuelle complète avec l'utilisateur** (spec §9), sur la version de release :

`open build/SonyBridge.app`, puis vérifier avec lui :
1. Chaque élément du menu (spec §4), casque connecté puis déconnecté.
2. Le bouton physique NC du casque, menu fermé puis menu ouvert.
3. La coupure pour inactivité, puis la reconnexion automatique ; « Déconnecter » n'entraîne pas de reconnexion.
4. Le lancement à l'ouverture de session (depuis `/Applications`).
5. La barre des menus en thème clair puis sombre : l'icône reste lisible.
6. Le Mac en anglais : `open build/SonyBridge.app --args -AppleLanguages '(en)'`, tout le menu en anglais.

- [ ] **Step 5 : Commit, puis CI** (par l'utilisateur)

```bash
git add -A && git commit -m "docs: README for the menu bar app"
```

L'utilisateur pousse sa branche et ouvre une PR vers `main` : le workflow « macOS » doit passer (`make test`
puis `make release`) et publier l'artefact `SonyBridge-macOS`.

