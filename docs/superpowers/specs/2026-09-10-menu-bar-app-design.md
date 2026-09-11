# SonyBridge dans la barre des menus — spec de design

- **Date :** 2026-09-10
- **Statut :** validé en discussion, à relire avant le plan d'implémentation
- **Casque de référence :** WH-1000XM6 (firmware 3.1.5, protocole v2)

## 1. Objectif

Transformer SonyBridge, aujourd'hui une app à fenêtre, en **app de barre des menus** sobre, dans l'esprit
des menus système d'Apple (Bluetooth, Wi-Fi). L'app donne accès à toutes les fonctions déjà gérées, et
corrige ce qui est faux sur le WH-1000XM6.

## 2. Périmètre

**Inclus**
- Toutes les fonctions existantes, dans un menu natif : mode NC / Son ambiant / Désactivé, niveau ambiant,
  focalisation sur la voix, égaliseur (presets + manuel), DSEE, Speak-to-Chat, volume adaptatif, arrêt
  automatique, batterie, codec, firmware.
- Les corrections XM6 : relecture de l'état NC/Ambiant, égaliseur 10 bandes.
- Trois options activables : lancer à l'ouverture de session, connexion automatique, reconnexion automatique.
- Un build par script (`make`), sans Xcode, et la CI correspondante.
- Le français et l'anglais (mécanisme de traduction existant).

**Exclu** (projets séparés, plus tard)
- Les fonctions du XM6 encore inconnues du projet (multipoint, optimiseur NC, commandes tactiles…), qui
  demandent de la rétro-ingénierie.
- L'écoute des notifications que le casque envoie de lui-même : on garde la relecture périodique.
- La mise à jour des captures d'écran du README et du site (à refaire après l'implémentation).

## 3. Décisions

| Sujet | Décision | Raison |
|---|---|---|
| Forme de l'interface | Menu natif (maquette « B ») | Le plus proche des menus système d'Apple |
| Égaliseur manuel | Curseurs dans le sous-menu « Égaliseur », sous les presets (option « 1 ») | Tout reste dans le menu, sans fenêtre en plus |
| Technique | `NSStatusItem` + `NSMenu` (AppKit), vues SwiftUI (`NSHostingView`) pour les lignes riches | `MenuBarExtra` n'accepte pas de curseurs en style menu ; un popover serait un faux menu |
| Icône de la barre | Monochrome, une par mode, grisée si déconnecté | Mode visible d'un coup d'œil, style système |
| Build | Script + `Makefile`, suppression du `.xcodeproj` | Pas de Xcode sur la machine de dev ; une seule façon de compiler |
| Version minimale | macOS 13 (au lieu de 11) | `SMAppService` pour le lancement à l'ouverture de session |

## 4. Structure du menu

```
┌ WH-1000XM6                         68 % ▭      ← en-tête (vue SwiftUI)
│ Connecté · AAC                                  (ou « Connexion… » / « Non connecté »)
│ ⚠︎ <dernière erreur>                             ← seulement s'il y a une erreur
├──────────
│ Contrôle du son ambiant                         ← titre de section (inactif)
│ ◉ Réduction de bruit                            ← choix exclusifs
│ ◉ Son ambiant
│     ─────●───── 10                              ← curseur 1…20 (visible en Son ambiant)
│     Focalisation sur la voix          [  ]      ← interrupteur (visible en Son ambiant)
│ ◉ Désactivé
├──────────
│ Égaliseur                        Graves ›
│     ✓ Désactivé / Brillant / Dynamique / Doux / Détendu / Voix / Aigus / Graves / Parole / Manuel
│     ──────────
│     [10 curseurs verticaux]  ou  [5 curseurs + Clear Bass]   ← actifs si « Manuel »
│     Réinitialiser
│ DSEE                                  [  ]      ← chaque ligne n'apparaît que si le casque
│ Speak-to-Chat                         [  ]         gère la fonction
│ Volume adaptatif                      [  ]
│ Arrêt automatique           Quand retiré ›
│     ✓ Désactivé / 5 min / 30 min / 1 heure / 3 heures / Quand le casque est retiré
├──────────
│ À propos du casque                         ›    → Firmware, Codec, Protocole, Bluetooth (lignes d'info)
│ Options de SonyBridge                      ›    → ✓ Lancer à l'ouverture de session
│                                                    ✓ Connexion automatique
│                                                    ✓ Reconnexion automatique
│ Connecter… | Déconnecter
├──────────
└ Quitter SonyBridge                        ⌘Q
```

- La valeur courante (« Graves », « Quand retiré ») s'affiche à droite du titre du sous-menu.
- Casque déconnecté : le menu garde sa forme, les réglages sont désactivés (grisés), et l'en-tête affiche
  « Non connecté ». L'élément « Connecter… » essaie d'abord le casque Sony déjà connecté à macOS
  (comportement existant de `scanAndConnect`), sinon il ouvre le sélecteur Bluetooth de macOS.
- Valeurs par défaut des options : connexion auto **activée**, reconnexion auto **activée**, lancement à
  l'ouverture de session **désactivé** (Apple demande que l'utilisateur l'active lui-même).

## 5. Architecture

### 5.1 Type d'app

- `LSUIElement = YES` : pas d'icône dans le Dock, pas de fenêtre ni de menu d'app.
- `LSMinimumSystemVersion = 13.0`.
- Le bundle s'appelle `SonyBridge.app` (exécutable `SonyBridge`). L'identifiant
  `com.semvis123.SonyHeadphonesClient` est conservé, pour que macOS ne redemande pas l'autorisation
  Bluetooth.

### 5.2 Fichiers (`Client/macos/`)

| Fichier | Rôle | Dépend de |
|---|---|---|
| `main.swift` | Crée `NSApplication`, installe `AppDelegate`, lance la boucle | `AppDelegate` |
| `AppDelegate.swift` | Crée le modèle, les réglages et le contrôleur de barre ; démarre la connexion auto | tous les suivants |
| `StatusItemController.swift` | Possède le `NSStatusItem`, choisit l'icône selon l'état, attache le menu | `HeadphonesModel`, `HeadphonesMenu` |
| `HeadphonesMenu.swift` | Construit le `NSMenu` et le garde synchronisé avec le modèle (abonnement Combine) : états des choix, visibilité, valeurs à droite, actif/inactif | `HeadphonesModel`, `AppSettings`, `MenuRows` |
| `MenuRows/HeaderRow.swift` | En-tête : nom, état de connexion, codec, batterie (simple ou G/D/boîtier) | `HeadphonesModel` |
| `MenuRows/SliderRow.swift` | Curseur du niveau ambiant | `HeadphonesModel` |
| `MenuRows/ToggleRow.swift` | Ligne titre + interrupteur (focalisation, DSEE, Speak-to-Chat, volume adaptatif) | — (valeur + action en paramètres) |
| `MenuRows/EqualizerRow.swift` | Curseurs verticaux, 10 bandes ou 5 + Clear Bass selon le casque | `HeadphonesModel` |
| `HeadphonesModel.swift` | Existe déjà. État observable du casque et actions ; gagne la connexion/reconnexion auto et les relectures périodiques | `HeadphonesBridge`, `AppSettings`, `ReconnectPolicy`, `PollGuard` |
| `ReconnectPolicy.swift` | Logique pure : délai avant le prochain essai (3 s, 10 s, 30 s, puis 60 s) | — |
| `PollGuard.swift` | Logique pure : ignorer une relecture si l'utilisateur a changé ce réglage il y a moins de 3 s | — |
| `AppSettings.swift` | Les 3 options dans `UserDefaults` ; le lancement à l'ouverture passe par `SMAppService.mainApp` | — |
| `DeviceWatcher.swift` | Écoute les connexions Bluetooth (`IOBluetoothDevice.register(forConnectNotifications:)`) et signale qu'un casque Sony vient de se connecter | IOBluetooth |
| `HeadphonesBridge.h/.mm` | Existe déjà. Pont Obj-C++ ; s'adapte aux corrections XM6 (§7) | cœur C++ |
| `fr.lproj/`, `en.lproj/` | Traductions : textes du menu ajoutés, textes de l'ancienne fenêtre retirés | — |

**Supprimés :** `ContentView.swift`, `main.mm`, `AppDelegate.h/.mm`, `ViewController.h/.mm`, `Main.storyboard`,
`SonyHeadphonesClient.xcodeproj`, `exportOptions.plist`, et les images des casques dans `Assets.xcassets`
(elles ne sont plus affichées). L'icône de l'app est déplacée dans `Client/macos/Resources/AppIcon.iconset`,
d'où `iconutil` la compile directement.

### 5.3 Cœur C++ (`Client/`)

- Nouveau `ProtocolParsers.h/.cpp` : des fonctions pures qui transforment la réponse du casque en valeurs.
  - `parseNcAsmState(payload)` : gère les réponses `0x17` et `0x19`.
  - `parseEqualizer(payload)` : gère 5 bandes + Clear Bass, et 10 bandes.
  - `Headphones.cpp` les appelle, au lieu de décoder les octets lui-même.
- Le reste du cœur (mise en trame, ACK, connexion RFCOMM) ne change pas.

## 6. Fonctionnement

### 6.1 Connexion automatique (option activée)

1. L'app retient l'adresse du dernier casque connecté (`UserDefaults`).
2. Au lancement : si ce casque est connecté à macOS, l'app ouvre le canal de contrôle. À défaut, elle prend le
   premier casque connecté dont le nom ressemble à un Sony (règle existante `SHCLooksLikeSonyHeadset`).
3. Ensuite, `DeviceWatcher` signale chaque connexion Bluetooth. Pour un casque Sony, l'app attend 2 s (le
   temps que l'audio s'établisse) puis ouvre le canal.

### 6.2 Reconnexion automatique (option activée)

- Si le canal se coupe alors que le casque est toujours connecté à macOS, l'app réessaie selon
  `ReconnectPolicy` : 3 s, 10 s, 30 s, puis toutes les 60 s.
- L'app arrête d'essayer quand le casque se déconnecte de macOS (la connexion auto prendra le relais).
- Après un clic sur **Déconnecter**, pas de reconnexion auto jusqu'au prochain branchement du casque ou au
  prochain clic sur « Connecter… ».

### 6.3 Relectures périodiques

- État NC/Ambiant : toutes les 2 s (suit le bouton physique du casque). Batterie : toutes les 60 s.
- Les minuteurs sont ajoutés en mode `RunLoop.Mode.common`, pour continuer à tourner **pendant que le menu
  est ouvert**. Le menu se met alors à jour en direct.

### 6.4 Commandes

- Une action met à jour l'affichage tout de suite, puis la commande part sur la file série existante, dans
  l'ordre des clics.
- `PollGuard` ignore les relectures d'un réglage pendant 3 s après que l'utilisateur l'a modifié : sans ça,
  l'affichage reviendrait brièvement en arrière.
- Les curseurs (niveau ambiant, égaliseur) envoient une commande quand on relâche, et au plus toutes les
  150 ms pendant le glissement, pour ne pas saturer la liaison.

### 6.5 Erreurs

- La dernière erreur s'affiche sur une ligne « ⚠︎ message » sous l'en-tête. Elle disparaît à la prochaine
  action réussie. Pas de fenêtre d'alerte.
- Les échecs de connexion automatique ne s'affichent pas (ils sont normaux quand le casque dort). Seuls les
  échecs d'une action de l'utilisateur s'affichent.

### 6.6 Icône

- Des images modèles (*template*) monochromes, que macOS colore selon la barre (clair ou sombre) : une par
  mode (réduction de bruit, son ambiant, désactivé), plus une version grisée quand le casque est déconnecté.
- On part de symboles SF (`SF Symbols`) ; les glyphes exacts sont montrés pour validation pendant
  l'implémentation.

## 7. Corrections WH-1000XM6

Constats tirés des trames réelles capturées le 2026-09-10 :

| Fonction | Trame reçue | Constat |
|---|---|---|
| État NC/ASM, demande `66 17` | `67 17 00 00 00 00 00` | Tout à zéro : ce canal n'est pas celui du XM6 |
| Changement de mode `68 17 01 01 01 00 0a` | accepté, puis notification `69 19 01 01 01 00 0a 00 00` | Le changement marche ; le vrai état arrive sur le canal `0x19`, avec 2 octets de plus |
| Égaliseur, demande `56 00` | `57 00 30 0a 0a 0a 05 05 06 06 06 06 06 06` | Preset `0x30` inconnu ; `0x0a` = 10 valeurs de bandes |
| Volume adaptatif, demande `f6 0a` | aucune réponse | Pas géré : la ligne est masquée |

**Correction de la relecture NC/Ambiant**
- À la connexion, l'app envoie `66 19`. Si la réponse fait au moins 7 octets, elle relit l'état par `0x19`.
  Sinon, elle garde `0x17` (anciens modèles).
- L'envoi des changements continue par `68 17`, dont le fonctionnement est vérifié sur le XM6.

**Correction de l'égaliseur**
- `parseEqualizer` lit l'octet de nombre de valeurs :
  - `0x06` → Clear Bass + 5 bandes (existant) ;
  - `0x0a` → 10 bandes, sans Clear Bass.
- Le sous-menu affiche les curseurs qui correspondent. Un preset inconnu est affiché « Personnalisé » ; aucun
  preset n'est coché.

**Points à déterminer par expérimentation** (étape 3 de la construction, avec l'utilisateur et le casque)
1. Le sens des 2 octets de plus de `0x19` : changer de mode avec le bouton du casque et lire les trames.
2. Le décalage des valeurs des bandes (hypothèse −10…+10 avec un décalage de 10, à confirmer) et les
   identifiants des presets du XM6 : comparer avec l'app Sony, puis envoyer un preset et relire.
3. Le format d'envoi de l'égaliseur manuel à 10 bandes (hypothèse `58 00 a0 0a <10 valeurs>`) : essai pas à
   pas, l'utilisateur à l'écoute.

**Règle de sécurité :** tant qu'un format n'est pas confirmé, la commande correspondante n'est **jamais**
envoyée au XM6. Les curseurs 10 bandes restent inactifs, avec la mention « bientôt disponible ».

## 8. Build et CI

- `scripts/build.sh` : compile le Swift (`swiftc`, avec l'en-tête de pont), le C++ et l'Obj-C++
  (`clang++`, C++17, ARC), fait l'édition de liens, assemble `build/SonyBridge.app` (plist, `.lproj`, icône
  via `iconutil`) et signe en ad hoc avec les entitlements existants.
  - Variables : `CONFIG=debug|release` ; `ARCHS="arm64 x86_64"` pour une app universelle (fusion avec `lipo`) ;
    `DEBUG_PROTOCOL=1` pour activer `SHC_DEBUG_PROTOCOL`.
- `Makefile` :
  - `make` : compile ;
  - `make run` : compile, relance l'app, et envoie les logs dans `build/app.log` ;
  - `make test` : lance les tests ;
  - `make release` : app universelle zippée ;
  - `make clean`.
- CI : `.github/workflows/build.yml` (sur `main` et les PR) exécute `make test` et `make release`, puis publie
  le zip comme artefact. `xcodebuild.yml` est supprimé.
- README : section « Build from source » réécrite (`make run`), description de l'app de barre des menus.

## 9. Tests

- **`make test`** compile et lance deux petits exécutables de test (assertions simples, sans XCTest, qui n'est
  pas disponible sans Xcode) :
  - `Client/tests/ProtocolParsersTests.cpp` : `parseNcAsmState` et `parseEqualizer` avec les trames réelles
    du XM6 (§7) et des trames des anciens formats (`0x17`, 5 bandes + Clear Bass) ; aller-retour mise en trame
    / décodage (`packageDataForBt` / `unpackBtMessage`), échappement et somme de contrôle.
  - `Client/tests/LogicTests.swift` : `ReconnectPolicy` (suite des délais, remise à zéro) et `PollGuard`
    (fenêtre de 3 s).
- **Checklist manuelle** avec le XM6 : chaque élément du menu, synchronisation avec le bouton physique, menu
  ouvert pendant un changement, coupure pour inactivité puis reconnexion, déconnexion manuelle (pas de
  reconnexion), lancement à l'ouverture de session, bascule clair/sombre de la barre, français et anglais.

## 10. Ordre de construction

1. **Base** : `scripts/build.sh` + `Makefile`, point d'entrée Swift, app d'agent, icône et menu minimal
   (en-tête + modes + Quitter), sur le cœur existant.
2. **Menu complet** : toutes les lignes de §4, avec les fonctions actuelles ; `ContentView.swift` supprimé.
3. **Corrections XM6** : `ProtocolParsers` + tests, relecture `0x19`, égaliseur 10 bandes, puis les
   expérimentations de §7.
4. **Options** : `AppSettings`, `DeviceWatcher`, connexion et reconnexion auto, lancement à l'ouverture de
   session.
5. **Nettoyage** : suppression du `.xcodeproj` et des fichiers morts, CI, README, traductions.

## 11. Risques

| Risque | Parade |
|---|---|
| Taille et surbrillance des vues SwiftUI dans un `NSMenu` | Taille fixée par ligne ; vérifié dès l'étape 1 avec le curseur |
| Minuteurs gelés pendant l'ouverture du menu | Mode `RunLoop.Mode.common` (§6.3) |
| La connexion bloque le fil principal quelques secondes (boucle d'attente existante dans `HeadphonesBridge`) | Acceptable en arrière-plan ; l'en-tête affiche « Connexion… » |
| Formats XM6 non confirmés | Règle de sécurité §7 ; fonctions désactivées tant qu'elles ne sont pas vérifiées |
| Autorisation Bluetooth redemandée | Identifiant de bundle conservé |
