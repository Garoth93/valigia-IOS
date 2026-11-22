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
- **Voce**: nome, quantità, nota, foto (galleria o fotocamera), peso unitario
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
- **Condivisione** come testo (con spunte, solo mancanti o lista semplice).
- **Statistiche**: viaggi fatti, giorni in viaggio, voci dimenticate più
  spesso, peso medio per tipo di contenitore, template più usati.
- **Backup/ripristino JSON** (foto comprese).

## Installare l'app sull'iPhone

1. Pagina **Actions** della repo › workflow **build-ipa** › ultimo run verde
   (o **Run workflow**) › artifact `Valigia-unsigned-ipa`: estrai
   `Valigia-unsigned.ipa` (resta disponibile 30 giorni).
2. Sideloadly: collega l'iPhone, trascina il `.ipa`, inserisci l'Apple ID,
   **Start**. Sull'iPhone: Impostazioni › Generali › VPN e gestione
   dispositivo › Autorizza (serve anche la Modalità sviluppatore).
3. Al primo avvio trovi i template di esempio: crea un viaggio con **+ Viaggio**.

Limiti dell'account gratuito: la firma scade dopo 7 giorni (rifirma lo stesso
`.ipa`, i dati restano), massimo 3 app attive per Apple ID, app + widget usano
2 identificativi. In Impostazioni › Informazioni la riga "Dati condivisi con i
widget" dice se la firma ha incluso l'App Group: se è "Non disponibili" il
widget resta vuoto. Fai un **backup JSON** prima di reinstallare.

## Salvataggio

Un unico file `valigia-data.json` in Application Support, scritto in modo
atomico (mai mezzo file) con la copia precedente sempre tenuta come `.bak`: se
il file principale non si legge, l'app riparte dalla copia e mette da parte
quello rovinato. Scelto al posto di SwiftData perché tutta la logica (e la
persistenza) sta nel package `ValigiaCore`, testabile anche su Linux. Le foto
sono JPEG ridotti in Application Support/Photos.

## Animazioni (fase 2) — architettura già pronta

La valigia è una vista separata che riceve solo dati:

- `LuggageFillState` (package): avanzamento, `fillLevel` (sale riempiendo,
  scende svuotando), peso / peso massimo, `isClosed` (100% in partenza),
  `isEmptied` (100% al ritorno).
- `PackingEvent` (package, calcolati da `PackingEvents.diff`): voce
  spuntata/tolta (con direzione), voce segnalata, contenitore chiuso/svuotato,
  giro completato, giro di ritorno svuotato.
- Nell'app `PackingEventCenter` pubblica gli eventi (`lastBatch` osservabile e
  `stream()` asincrono); il protocollo `LuggageVisual` e `LuggageVisualView`
  scelgono la vista da Impostazioni (`Semplice` oggi; `Illustrata` e `3D`
  sono già nel modello, "in arrivo").

Per ora: icona del contenitore con anello di avanzamento e barre del peso.

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
