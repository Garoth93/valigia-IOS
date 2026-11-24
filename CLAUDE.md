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
- Tutto locale: nessun server, nessun account, nessuna chiamata di rete.
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
  nota, emoji, peso unitario in grammi, tag, foto (`photoFile`), `owned`
  (false = da comprare), `isCollapsed`, `externalRef` (integrazione futura).
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
  da comprare) + `ShoppingList`; `Stats.swift`; `Sharing.swift`
  (testo, promemoria, `WidgetSnapshot`); `Backup.swift` (backup con foto
  base64, `GearCatalogProvider` solo protocollo); `SampleContent`.

App:

- Persistenza: `valigia-data.json` in Application Support (`DataWriter`
  actor, salvataggio differito 0,6 s, `.bak` della versione precedente,
  revisioni per non sovrascrivere dati nuovi con vecchi; file illeggibile
  messo da parte e ripristino dal `.bak`). Foto in `Photos/` (orfane
  rimosse all'avvio).
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
| `testflight.yml` | manuale, push su `main`, ogni ~60 giorni (1° dei mesi dispari) | archive firmato + export App Store + upload su TestFlight (vedi sotto). |

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
