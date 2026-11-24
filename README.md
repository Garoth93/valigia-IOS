# Valigia — prepara zaino, valigie e borse (iOS)

App iOS nativa (Swift + SwiftUI, grafica Material 3 Expressive, colori
dinamici, tema chiaro/scuro) per preparare zaini, valigie, trolley e borse con
liste a più livelli, pesi, template e giri di controllo. Tutto resta sul
telefono: nessun server, nessun account.

Sviluppata senza Mac: compilata da GitHub Actions e installata sull'iPhone con
un account Apple gratuito tramite Sideloadly o SideStore (come le altre app
della serie: Ritorni, LTIDI, Home Alarm…).

## Come funziona

1. **Template** — un template è un contenitore con la sua lista ("Zaino
   scialpinismo", "Trolley weekend"…). Al primo avvio ce ne sono 5 di esempio,
   tutti modificabili o eliminabili. In **Template › Sempre presenti** metti le
   voci da copiare in ogni nuovo viaggio (documento, chiavi…).
2. **Viaggio** — nome, destinazione, date e i contenitori presi dai template.
   Ogni contenitore è una **copia indipendente**: nel viaggio togli e aggiungi
   voci senza toccare il template. Al contrario, un contenitore del viaggio si
   può **salvare come template**.
3. **Giri di controllo** — ogni viaggio ha più giri (Partenza, Ritorno e quanti
   ne vuoi: cambio albergo, spostamento…), ognuno con spunte indipendenti.
   *Riempi*: spunti quello che metti dentro. *Svuota* (il Ritorno, di default):
   spunti quello che tiri fuori a casa, così vedi se hai riportato tutto. Le
   spunte di un giro si azzerano quando vuoi, senza perdere gli altri giri.
4. **Fine giro** — cosa manca, con filtro *Mancanti / Non trovate / Lasciate*
   (con il posto in cui le hai lasciate), poi *Chiudi il giro*.

## Cosa c'è

- **Lista a più livelli** senza limite di profondità: espandi/comprimi,
  trascina per riordinare (pulsante ⇅) e per mettere una voce dentro un'altra,
  *Sposta in…* (anche in un altro contenitore o template), *Metti dentro la
  voce sopra* / *Porta fuori*, **duplica un ramo intero**.
- **Allegati** su voci e viaggi: più foto (galleria, fotocamera), PDF e file
  da File, **scanner documenti** (il biglietto di carta diventa un PDF).
  Anteprime in griglia, apertura a schermo intero (QuickLook: zoom, sfoglia,
  condividi, stampa), rinomina, riordina, elimina. Graffetta col numero nella
  lista e filtro *Con allegati*. Nel viaggio la sezione **Documenti** raccoglie
  quelli del viaggio (biglietti, prenotazioni…) e quelli delle voci con il
  percorso (es. *Zaino › Astuccio documenti › Passaporto*). I file sono
  protetti (leggibili solo a telefono sbloccato) e condivisi tra le copie di
  template e viaggi: un file si elimina solo quando nessuno lo usa più.
- **Voce**: nome, quantità, nota, allegati, peso unitario
  (g o kg), emoji, tag (`inverno`, `volo`, `solo bagaglio a mano`…), "ce l'ho
  già". Inserimento veloce dal campo in basso (`3 calze` o `calze x3`).
- **Pesi**: totale su ogni ramo, sul contenitore (+ peso a vuoto) e sul
  viaggio; indicatore *peso attuale / massimo*, ambra vicino al limite, rosso
  oltre.
- **Contenitori**: tipo (zaino, valigia, trolley, borsa, borsone, astuccio,
  marsupio…), colore (anche per il tema delle sue liste), dimensioni in cm o
  litri, peso massimo.
- **Stati della voce nel giro**: preparata / non trovata / lasciata (dove).
- **Ricerca** (anche nelle note e senza accenti), **filtri per tag** (ereditati
  dai rami), *Solo mancanti*, *Da comprare*, barre di avanzamento per
  contenitore e viaggio.
- **Controllo rapido**: spunte grandi, feedback tattile, solo mancanti.
- **Da comprare**: voci non ancora possedute da viaggi, template e "sempre
  presenti", in un'unica lista da spuntare o condividere.
- **Notifica** la sera prima della partenza (orario a scelta) con quanto manca.
- **Widget** Home e schermata di blocco con l'avanzamento del prossimo viaggio.
- **Condivisione** come testo (con spunte, solo mancanti o lista semplice),
  con i titoli degli allegati (📎).
- **Statistiche**: viaggi fatti, giorni in viaggio, voci dimenticate più
  spesso, peso medio per tipo di contenitore, template più usati.
- **Backup/ripristino .zip** (dati + cartella degli allegati, con o senza
  allegati e dimensione prevista); si ripristinano anche i vecchi backup .json.
- **Face ID facoltativo** per aprire e vedere in anteprima i documenti.
- **Backup automatico su iCloud Drive** (File › iCloud Drive › Backup ›
  Valigia, lo stesso contenitore di Tessere e Cresta): uno zip al giorno (gli
  ultimi 30) più l'ultimo, scritto dopo le modifiche, all'uscita e in
  background. Gli allegati entrano nel backup iCloud solo se li attivi
  (default spento). Ripristino da Impostazioni › iCloud e, al primo avvio su
  un iPhone nuovo, proposto da solo se in iCloud c'è un backup. Con
  l'installazione Sideloadly iCloud non è disponibile (usa il backup .zip).

## Installare l'app sull'iPhone

**TestFlight (consigliato).** A ogni push su `main` il workflow
**testflight** firma l'app e la carica su App Store Connect: dopo 5-30 minuti
la build compare nell'app TestFlight (gruppo di test interni). Ogni ~60 giorni
il workflow ricostruisce da solo l'ultima versione, così la build non scade
(TestFlight le fa scadere dopo 90 giorni). Si può lanciare anche a mano da
**Actions › testflight › Run workflow**.

Configurazione una tantum (fatta): App ID `com.garoth93.valigia` (App Groups +
iCloud) e `com.garoth93.valigia.widgets` (App Groups), App Group
`group.com.garoth93.valigia`, container `iCloud.com.garoth93.backup`, scheda
app su App Store Connect, secrets `APPLE_TEAM_ID`, `ASC_KEY_ID`,
`ASC_ISSUER_ID`, `ASC_KEY_P8`.

**Ripiego: Sideloadly.** Actions › **build-ipa** › artifact
`Valigia-unsigned-ipa`, poi Sideloadly con l'Apple ID gratuito (firma di 7
giorni, niente iCloud). In Impostazioni › Informazioni la riga "Dati condivisi
con i widget" dice se la firma ha incluso l'App Group.

## Salvataggio

In locale un unico file `valigia-data.json` in Application Support, scritto in modo
atomico (mai mezzo file) con la copia precedente sempre tenuta come `.bak`: se
il file principale non si legge, l'app riparte dalla copia e mette da parte
quello rovinato. Scelto al posto di SwiftData perché tutta la logica (e la
persistenza) sta nel package `ValigiaCore`, testabile anche su Linux. Gli
allegati sono file in Application Support/Attachments (le foto della prima
versione vengono spostate lì e diventano il primo allegato della voce).

## Valigia 3D e animazioni

In **Impostazioni › Controllo › Valigia** scegli come vedere il contenitore:

- **Semplice**: icona con anello di avanzamento (default).
- **3D**: in cima alla lista di ogni contenitore di un viaggio compare una
  valigia 3D generata da codice (RealityKit, nessun modello esterno). La ruoti
  col dito (doppio tocco per raddrizzarla); le voci spuntate ci volano dentro
  (o escono nei giri «Svuota»), il contenuto sale con il riempimento e diventa
  rosso oltre il peso massimo, a 100% il coperchio si chiude e la cerniera
  scorre. Con «Riduci movimento» niente pacchi in volo e coperchio senza
  animazione. Nelle schede (dettaglio viaggio) resta l'icona semplice, così è
  attiva una sola vista 3D alla volta.
- **Illustrata** (SwiftUI, fase successiva): in arrivo.

Architettura: la valigia è una vista separata che riceve solo dati.

- `LuggageFillState` (package): avanzamento, `fillLevel` (sale riempiendo,
  scende svuotando), peso / peso massimo, `isClosed`, `isEmptied`.
- `PackingEvent` (package, da `PackingEvents.diff`): voce spuntata/tolta,
  segnalata, contenitore chiuso/svuotato, giro completato, giro di ritorno
  svuotato; `motion` dice se la voce entra o esce.
- Nell'app `PackingEventCenter` pubblica gli eventi (`lastBatch` osservabile
  e `stream()` asincrono); il protocollo `LuggageVisual` e
  `LuggageVisualView` scelgono la vista da Impostazioni.

## Integrazione con altre app (attrezzatura)

Solo protocollo, non implementato: `GearCatalogProvider` (in `Backup.swift`
del package) con `GearItem`, `ExternalRef` sulle voci e
`applyGearUpdates(_:)` per aggiornare nome/peso delle voci collegate.

## Privacy

I dati restano sul telefono. Nella repo non ci sono dati personali: i test
usano solo dati sintetici e `.gitignore` esclude backup, file dati e foto.

## Struttura

```
apps/Valigia/           app SwiftUI (project.yml per XcodeGen)
  Sources/              schermate, modello, servizi (notifiche, foto, haptics)
  Shared/               tema Material 3, indicatori di avanzamento, dati per i widget
  Widgets/              estensione WidgetKit
packages/ValigiaCore/   logica non grafica, testata con `swift test` anche su Linux
.github/workflows/      build-simulator, build-ipa, test-linux
CLAUDE.md               convenzioni e regole di lavoro per Claude Code
```
