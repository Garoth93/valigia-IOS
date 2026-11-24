# CLAUDE.md — regole di lavoro per questa repo

Repo di app iOS **native (Swift + SwiftUI)** personali, sviluppate senza Mac:
il codice viene scritto su Linux (Claude Code) e compilato **solo** su GitHub
Actions con runner macOS. Distribuzione: app su **TestFlight** (account Apple
a pagamento, firma automatica in CI); il `.ipa` non firmato per Sideloadly
resta come ripiego.

Stessa impostazione delle repo `Garoth93/tessere-IOS` (TestFlight, backup
iCloud) e `Garoth93/montagna-360` (Cresta), `Garoth93/ritorni-IOS`.

## Vincoli fissi

- Nativo vero: Swift/SwiftUI. Niente WebView, niente framework cross-platform,
  salvo richiesta esplicita dell'utente.
- Nessun `.xcodeproj` committato: il progetto è generato in CI da
  `apps/<app>/project.yml` con XcodeGen. `.gitignore` lo esclude.
- Mai committare segreti, chiavi API, certificati, profili di provisioning,
  Team ID reali.
- **PRIVACY (vincolo forte)**: mai committare dati personali dell'utente —
  backup, file dati, liste reali, foto — né nei test, né nei commenti, né nel
  README. I test usano solo dati **sintetici** generati nel codice
  (`Synthetic.swift`, nomi `... TEST`). I template di esempio
  (`SampleContent`) sono generici.
- Tutto locale: nessun server, nessun account. Unica rete: il backup
  automatico in iCloud Drive (container dell'utente, niente CloudKit).
- Firma solo in `testflight.yml` (automatica, chiave API App Store Connect).
  Mai certificati, profili o `.p8` nella repo; Team ID solo nei secrets.
  `build-ipa.yml` resta senza firma (`CODE_SIGNING_ALLOWED=NO`).
- Non modificare impostazioni della repo o secrets: spiegare all'utente cosa
  configurare.

## Struttura repo

```
apps/<NomeApp>/            un'app per cartella
  project.yml              spec XcodeGen (target, bundle id, deployment target)
  Sources/                 codice SwiftUI dell'app (solo strato UI + glue)
  Resources/               Assets.xcassets e altre risorse
  Shared/                  codice comune app + widget
  Widgets/                 estensione WidgetKit
  *.entitlements           entitlements (App Group) usati per la firma ad-hoc in CI
  Info.plist               GENERATO da XcodeGen (git-ignored)
packages/<NomePackage>/    Swift Package con la logica NON grafica
  Package.swift            tools-version 5.9, nessuna dipendenza da UIKit/SwiftUI
  Sources/<NomePackage>/   modelli, regole, persistenza (Foundation only)
  Tests/<NomePackage>Tests/ XCTest, eseguiti anche su Linux
.github/workflows/         CI (vedi sotto)
.github/actions/setup-xcode/ composite action: seleziona Xcode, installa XcodeGen, genera il progetto
```

| App     | Package logica | Bundle ID                               | Deployment target |
|---------|----------------|-----------------------------------------|-------------------|
| Valigia | ValigiaCore    | `com.garoth93.valigia` (+ `.widgets`)   | iOS 26.0 |

### Valigia

Prepara zaini, valigie, trolley, borse con liste a più livelli.

Modello (`Models.swift`, decodifica tollerante: campi mancanti = default):

- `Item`: albero senza limite di profondità (`children`), quantità ≥ 1,
  nota, emoji, peso unitario in grammi, tag, `attachments`, `owned`
  (false = da comprare), `isCollapsed`, `externalRef` (integrazione futura).
  Il vecchio `photoFile` (v1) si legge ancora e diventa il primo allegato;
  non viene più scritto (`encode(to:)` esplicito).
- `Attachment` (`Attachments.swift`): id, `kind` image/pdf/other, `fileName`
  salvato (`<uuid>.<ext>`), titolo, nome originale, `byteSize`, data. Le
  copie (template → viaggio, duplica ramo) hanno id nuovi ma **lo stesso
  file**; `ValigiaData.referencedFiles` / `releasedFiles(before:after:)`
  dicono quali file non sono più usati. `Trip.attachments` (documenti del
  viaggio, non copiati da "duplica viaggio"), `Trip.documents` (viaggio +
  voci con percorso), `attachmentsByteSize` (file condivisi contati una volta).
- `Luggage`: tipo, colore, `Dimensions` (cm e/o litri), peso massimo e a
  vuoto, `items`.
- `PackTemplate` (contenitore riusabile), `Trip` (contenitori copiati con
  id nuovi, `rounds`, `activeRoundID`), `CheckRound` (nome, tipo,
  `PackDirection` pack/unpack, `marks` = `ItemMark` per foglia con stato
  packed/notFound/leftBehind + luogo).
- `ValigiaData`: viaggi, template, `alwaysItems`, impostazioni.

Regole (tutte testate):

- Le spunte stanno solo sulle **foglie**; un genitore è calcolato
  (none/partial/done) e spuntarlo applica lo stato a tutte le foglie sotto.
- `ItemTree.swift`: find/path/insert/remove/move (niente cicli),
  `moveRow` per l'`onMove` della lista appiattita (la voce va prima della
  riga di destinazione, con lo stesso genitore), indent/outdent, duplicate
  (id nuovi), `rows()` rispetta `isCollapsed`.
- `DataOps.swift`: `ListRef` (bag di un viaggio / template / always),
  `createTrip` (copie indipendenti + voci "sempre presenti" nel primo
  contenitore, saltando i nomi già presenti), `saveAsTemplate`,
  `moveItem` tra liste (stesso viaggio = stessi id, spunte conservate),
  `pruneMarks` dopo ogni modifica.
- `Rounds.swift`: progress, toggle, setStatus, reset (giro o contenitore),
  complete/reopen, `summary` (mancanti/non trovate/lasciate con percorso).
- `FillState.swift`: `LuggageFillState` / `TripFillState` e
  `PackingEvents.diff` = **architettura per le animazioni di fase 2**.
- `Filtering.swift` (ricerca senza accenti, tag ereditati, solo mancanti,
  da comprare, con allegati, titoli degli allegati) + `ShoppingList`;
  `Stats.swift`; `Sharing.swift` (testo con 📎 titoli allegati, promemoria,
  `WidgetSnapshot`); `Backup.swift` (`BackupFile` JSON, decodifica dei vecchi
  backup v1 con file base64 in `photos`, `GearCatalogProvider` solo
  protocollo); `BackupArchive.swift` (backup **.zip**: `valigia-backup.json`
  + `Attachments/<file>`, con/senza allegati, `estimatedSize`, lettura anche
  dei vecchi `.json`); `MiniZip.swift` (da Diario Sonoro: STORE, CRC32,
  `ZipPath.isSafe` contro i percorsi `..`); `SampleContent`.

App:

- Persistenza: `valigia-data.json` in Application Support (`DataWriter`
  actor, salvataggio differito 0,6 s, `.bak` della versione precedente,
  revisioni per non sovrascrivere dati nuovi con vecchi; file illeggibile
  messo da parte e ripristino dal `.bak`). Allegati in `Attachments/`
  (`AttachmentStore`, `.completeFileProtection`): i file rilasciati da una
  modifica si cancellano solo dopo il salvataggio riuscito, gli orfani
  all'avvio; `Photos/` della v1 migrata all'avvio. UI: `AttachmentsEditor`
  (griglia, galleria multipla, fotocamera, scanner VisionKit → PDF, File,
  rinomina/riordina/elimina), anteprime `QLThumbnailGenerator`, apertura con
  `QLPreviewController` (`AttachmentPreview`, titoli dell'utente),
  `TripDocumentsView`.
- Privacy documenti: `ValigiaSettings.lockDocuments` → `DocumentLock`
  (Face ID / codice una volta per sessione, si richiude in background):
  `AttachmentPreview.open` chiede lo sblocco, `AttachmentThumb` mostra solo
  l'icona finché è bloccato. Disattivarlo richiede l'autenticazione.
- `AppModel.update` è l'unico punto di modifica: salva, pubblica gli eventi
  (`PackingEventCenter`, haptics), aggiorna widget snapshot e notifiche.
- Schermate: Viaggi (prossimo viaggio, altri, passati, archiviati), dettaglio
  viaggio (giri, avanzamento, contenitori), `LuggageView` (albero, filtri,
  swipe, menu, riordino, inserimento veloce) usata per viaggi, template e
  "sempre presenti", controllo rapido, fine giro, template, da comprare,
  statistiche (Swift Charts), impostazioni.
- Visual del contenitore (`LuggageVisual`, scelto in Impostazioni):
  `SimpleLuggageVisual` ovunque; `ThreeDLuggageVisual` (RealityKit,
  `LuggageScene` generata da codice: scatola aperta, contenuto che sale,
  coperchio con cerniera, pacchi che entrano/escono, rotazione col dito,
  rispetta Riduci movimento) solo nell'intestazione di `LuggageView` dei
  viaggi (`allowsLarge`). L'illustrata SwiftUI è ancora "in arrivo".
- Widget `NextTripWidget` (small/medium + blocco), tocco →
  `valigia://trip/<uuid>`. App Group `group.com.garoth93.valigia`.

### Backup iCloud Drive (procedura riusabile per le altre app)

Un solo container **condiviso** da tutte le app: `iCloud.com.garoth93.backup`,
una sottocartella per app. In File appare come *iCloud Drive › Backup › <App>*.

Una volta (developer.apple.com): Identifiers › iCloud Containers ›
`iCloud.com.garoth93.backup`. Per ogni app: App ID dell'app (non del widget) ›
iCloud (CloudKit/iCloud Documents) › *Configure* › spuntare il container.

Nella repo, per ogni app:

- `<App>.entitlements` (solo app, mai il widget):
  `com.apple.developer.icloud-container-identifiers` e
  `com.apple.developer.ubiquity-container-identifiers` = il container,
  `com.apple.developer.icloud-services` = `CloudDocuments`;
- `<App>.sideload.entitlements` = gli stessi senza iCloud: `build-ipa.yml` lo
  preferisce per la firma ad-hoc (l'account gratuito non ha iCloud);
- `project.yml`: `SystemCapabilities` `com.apple.iCloud` sul target app;
  Info.plist `NSUbiquitousContainers` › `iCloud.com.garoth93.backup` con
  `NSUbiquitousContainerIsDocumentScopePublic: true`,
  `NSUbiquitousContainerName: Backup` (uguale in tutte le app),
  `NSUbiquitousContainerSupportedFolderLevels: Any`; per il backup in
  background `UIBackgroundModes: [fetch]` + `BGTaskSchedulerPermittedIdentifiers`;
- file in `<container>/Documents/<App>/`: in Valigia `Valigia-backup-yyyy-MM-dd.zip`
  (uno al giorno, ultimi 30) + `Valigia-backup-latest.zip`, scritti con
  `BackupArchive` (gli allegati solo se `cloudIncludeAttachments`, default
  **spento**: possono esserci documenti d'identità). Logica pura (nomi, pulizia, impronta del contenuto per non
  riscrivere se nulla è cambiato) nel package (`CloudBackup.swift`: `CloudBackupPlan`, `isEffectivelyEmpty`, `BackupArchive.peek`),
  I/O nell'app (`CloudBackupService.swift`): `url(forUbiquityContainerIdentifier:)`
  sempre fuori dal main thread, scritture/letture con `NSFileCoordinator`,
  file non scaricati = segnaposto `.<nome>.icloud` (`startDownloadingUbiquitousItem`).
- Quando: dopo le modifiche (8 s di attesa), all'uscita in background,
  `BGAppRefreshTask` ogni ~6 h. Un'app vuota (`isEffectivelyEmpty`: nessun viaggio, solo template di esempio
  intatti, nessun allegato) non sovrascrive mai i backup.
- Ripristino: Impostazioni › Ripristina da iCloud, e guidato al primo avvio
  se l'app è vuota e in iCloud c'è un backup (chiesto una volta sola,
  `CloudRestoreView` con anteprima: viaggi, template, allegati inclusi).
- BGTask: `com.garoth93.valigia.backup`.

## Convenzioni di codice

- Swift 5 language mode (`SWIFT_VERSION: 5.0` nel project.yml), tools-version
  5.9 nei package, in modo che Linux (`swift:6.0`) e Xcode 26 compilino lo
  stesso codice. Il package dichiara `.iOS(.v17)` come minimo: è solo il suo
  minimo, l'app può avere un target più alto.
- Logica, modelli e persistenza nel package: tipi `struct` value-type,
  `Codable`, `Equatable`, `Sendable`, senza `import SwiftUI`/`UIKit`.
  Tutto ciò che è testabile va lì e ha un test. Le integrazioni esterne
  (es. `GearCatalogProvider`) stanno dietro protocolli del package; le
  implementazioni finte esistono **solo nei test**. Nell'app non c'è nessun
  "genera dati di prova".
- Nell'app: `@Observable` (framework Observation) + `@MainActor`, iniettato
  con `.environment(...)` e letto con `@Environment(Tipo.self)`; stringhe UI
  e permessi (Info.plist) in italiano. Target iOS 26.0: si possono usare le
  API SwiftUI di iOS 26 senza `#available`.
- Grafica Material 3 (tema da `MaterialScheme` con seme scelto dall'utente
  in `Palette.seeds`, default blu oceano; dentro un contenitore il tema può
  seguire il suo colore con `.seedTheme(_:)`), forme arrotondate, `IconBadge`/`M3Card`/`PillButton`.
- Nessuna dipendenza esterna salvo necessità motivata.
- Commit piccoli e descrittivi; niente identificatori di modello AI nei commit.

## Xcode e runner

- Runner: `macos-26`. Xcode fissato con `XCODE_VERSION: "26.6"` (SDK iOS 26.5)
  (env in ogni workflow) e selezionato con `xcode-select`. Se GitHub ritira la
  versione, la composite action fallisce elencando le Xcode disponibili:
  aggiornare il valore in tutti i workflow e qui.
- Toolchain Linux per i test: immagine Docker `swift:6.0-noble`.
- XcodeGen e xcbeautify installati con Homebrew a ogni run.

## CI (GitHub Actions)

| Workflow | Trigger | Cosa fa |
|----------|---------|---------|
| `build-simulator.yml` | push su ogni branch, PR, manuale | `xcodebuild build` per iOS Simulator, senza firma. Serve a vedere gli errori di compilazione. |
| `build-ipa.yml` | push su `main` e `claude/**`, manuale | build Release per dispositivo con `CODE_SIGNING_ALLOWED=NO`, firma ad-hoc con gli `.entitlements` dell'app e del widget, impacchetta `Payload/<App>.app` in `<App>-unsigned.ipa` e lo carica come artifact (30 giorni). |
| `test-linux.yml` | push su ogni branch, PR, manuale | `swift test` su ogni package in `packages/`. |
| `testflight.yml` | manuale, push su `main` e `claude/**`, ogni ~60 giorni (1° dei mesi dispari) | archive firmato + export App Store + upload su TestFlight (vedi sotto). |

Nota: `build-ipa.yml` firma ad-hoc l'app con `<App>.sideload.entitlements`
se esiste (senza iCloud, che l'account gratuito non può firmare).

### TestFlight (procedura riusabile per le altre app)

Una volta per account (developer.apple.com / App Store Connect):

1. App Store Connect › Utenti e accessi › Integrazioni › **chiave API** con
   ruolo **Admin** (serve per creare certificati e profili e per la firma
   cloud della distribuzione). Secrets della repo: `ASC_KEY_ID`,
   `ASC_ISSUER_ID`, `ASC_KEY_P8` (testo del `.p8`, anche in base64),
   `APPLE_TEAM_ID`.
2. Per ogni app: scheda dell'app su App Store Connect con lo stesso bundle id
   del `project.yml`. Gli App ID (app + `.widgets`) e i profili li
   crea/aggiorna xcodebuild con `-allowProvisioningUpdates`, **ma l'API non
   può assegnare App Group e container iCloud**: su developer.apple.com ›
   Identifiers › ogni App ID (app **e** widget) › App Groups › *Configure* ›
   spuntare `group.com.garoth93.<app>` (per l'app anche iCloud › *Configure* ›
   il container). Altrimenti l'archive fallisce con "Provisioning profile …
   doesn't match the entitlements file's value for …application-groups".
   Lo step "App ID capabilities" del workflow stampa le capability attive.

Nella repo:

- copiare `.github/workflows/testflight.yml` e `scripts/asc_revoke_certs.py`,
  cambiare `APP:` nell'env del workflow;
- `project.yml`: firma vuota (la imposta il workflow da riga di comando:
  `CODE_SIGN_STYLE=Automatic`, `CODE_SIGN_IDENTITY="Apple Development"`,
  `DEVELOPMENT_TEAM`), `ITSAppUsesNonExemptEncryption: false` nell'Info.plist,
  icona 1024 senza trasparenza, `MARKETING_VERSION` da alzare a mano per le
  nuove versioni; se l'app è solo verticale serve `UIRequiresFullScreen: true`
  (altrimenti l'upload è rifiutato con l'errore 90474 sulle orientazioni);
- build number = `github.run_number` del workflow (sempre crescente).

Come funziona: `xcodebuild archive` con firma automatica (crea al volo un
certificato di sviluppo sul runner, poi revocato dallo step finale per non
accumularli), `-exportArchive` con `method=app-store-connect`,
`destination=upload` (firma di distribuzione gestita nel cloud da Apple e
upload diretto). La build compare in TestFlight dopo 5-30 minuti di
elaborazione. TestFlight fa scadere le build dopo 90 giorni: la schedulazione
ogni due mesi le rinnova (gira sul branch di default della repo).
Log di archive/export nell'artifact `testflight-logs`.



### Come leggere i log di CI

Con gli strumenti GitHub MCP disponibili a Claude Code: `actions_list` con
`list_workflow_runs` per trovare il run, `list_workflow_jobs` per i job,
`get_job_logs` con `failed_only=true` e `return_content=true` per i log dei
job falliti. I log raw di `xcodebuild` sono anche caricati come artifact
`xcodebuild-*-log-<App>`. Gli errori Swift compaiono come annotazioni
`::error file=...` grazie a `xcbeautify --renderer github-actions`.

## Regole di lavoro (per Claude)

1. Dopo **ogni push** controllare l'esito della CI e correggere da soli gli
   errori di compilazione fino a build verde. Mai dichiarare "funziona" se la
   CI non è verde: riportare l'esito reale con il link al run.
2. Non si può vedere l'interfaccia: nelle scelte grafiche ambigue usare il
   comportamento standard e dire all'utente cosa verificare sul telefono.
3. Commit piccoli e descrittivi. Mai segreti, mai dati personali.
4. I test del package si possono eseguire in locale con Docker:
   `docker run --rm -v "$PWD":/src -w /src swift:6.0-noble swift test --package-path packages/ValigiaCore`
   (avviare `dockerd` se non è attivo). L'app SwiftUI si compila solo in CI.
