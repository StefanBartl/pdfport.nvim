# Konzept — PDF-Erstellung als öffentliche API

Status: **P0–P3 implementiert (2026-08-09)** — Gerüst + Bild-Producer
(`img2pdf`/`magick`) + Text/Markdown-Producer (`pandoc` mit
Engine-Auto-Erkennung) + HTML-Producer (`weasyprint`/`chromium`) +
Office-Producer (`soffice`) + Merge-Producer (`qpdf`/`pdftk`/`ghostscript`,
über `pdfport.merge()`), `pdfport.create()`/`can_create()`/`merge()` (inkl.
`text`/`bufnr`-Eingaben über `util/tmpfile.lua`), `:PdfPort
create`/`:PdfPort merge`/`:PdfPort producers`, Tests, Doku. Siehe
[docs/FEATURES/](../FEATURES/). **P2 (Aufrufer-Anbindung) ist jetzt
vollständig:** `filetree.nvim` (`util/pdf.create()` +
`features/system/pdf_create`), `images.nvim` (`convert.to_pdf`/`M.export`
routen asynchron über `pdfport.create()`, wenn verfügbar, sonst der
bisherige `magick`-Pfad unverändert) und `markdown.nvim` (`:Markdown export
pdf`, neues `markdown.commands.export`, exakt nach dem Muster von
`markdown.commands.image` für images.nvim) — jeweils dokumentiert im
eigenen Repo. Stand des Konzepts: 2026-08-07.

pdfport.nvim kann heute ausschließlich *lesen*: PDF → Text/Markdown
(`backends/`, `core/dispatcher.lua`) bzw. PDF-Seite → Bild (intern in
`renderers/terminal.lua`). Dieses Dokument beschreibt die Gegenrichtung —
**etwas → PDF** — und zwar so, dass sie primär als **API für andere Plugins**
taugt (`images.nvim`, `markdown.nvim`, `filetree.nvim`), nicht nur als
Benutzerkommando.

Leitgedanke: pdfport ist der eine Ort im Setup, der PDF-spezifisches Wissen
hält (welches Werkzeug kann was, wie ruft man es auf, was passiert unter
Windows). Alle anderen Plugins rufen an, kennen aber weder `pandoc` noch
`magick` noch eine Fallback-Kette.

---

## 1. Warum überhaupt in pdfport und nicht je Plugin

Der Ist-Zustand ist bereits eine dreifache Doppelung in Zeitlupe:

- `images.nvim` hat `images.convert.to_pdf` — ImageMagick, ein Bild, keine
  Optionen, synchrones `vim.system():wait()`.
- `markdown.nvim` hat keinen Export, das wäre der offensichtliche nächste
  Wunsch (`:Markdown export pdf`).
- `filetree.nvim` hat gar nichts, würde einen Export einer Auswahl aber
  natürlicherweise anbieten (mehrere Bilder → ein PDF).

Jedes Plugin einzeln bekäme sonst seine eigene Werkzeugerkennung, seine eigene
Fehlerbehandlung, seine eigene Windows-Eigenheit. Genau das ist der Fall, für
den pdfport schon eine Registry, einen Resolver, eine Fallback-Kette, eine
Fortschrittsanzeige und `platform.has()` besitzt — die Erstellung ist
strukturell dasselbe Problem wie die Extraktion, nur mit umgedrehtem Pfeil.

---

## 2. Werkzeuge — Erörterung der Alternativen

Wichtig vorweg: **es gibt kein Werkzeug, das alle Eingaben abdeckt.** `pandoc`
ist kein PDF-Erzeuger, sondern ein Konverter, der für PDF *immer* eine
externe Engine braucht. Deshalb wird das keine „wir nehmen pandoc"-Entscheidung,
sondern eine Kette pro Eingabeart.

### Bild → PDF

| Werkzeug | Bewertung |
|---|---|
| **`img2pdf`** (Python) | **Erste Wahl.** Verlustfrei: bettet JPEG/PNG-Daten *unverändert* ein, statt sie neu zu kodieren. Winziges Paket, keine Systemabhängigkeit, kann mehrere Bilder → ein PDF, Seitengröße/Ränder als Argumente. Nachteil: braucht Python, nicht überall da. |
| **ImageMagick** (`magick a.png b.png out.pdf`) | **Zweite Wahl / pragmatischer Default.** In diesem Setup ohnehin vorausgesetzt (`images.nvim` baut auf `magick`, siehe dessen `convert.lua`), kann Mehrfachbild → mehrseitiges PDF nativ. Nachteil: rekomprimiert, PDFs werden größer und minimal schlechter. |
| `typst` / LaTeX mit `\includegraphics` | Overkill für „Bild rein, PDF raus", aber interessant, sobald Kopf-/Fußzeile, Titel oder Bildunterschriften dazukommen (Galerie-Export als kontaktbogenartiges Dokument). |
| Ghostscript | Kann kein Bild einlesen. Für *Zusammenführen/Komprimieren* fertiger PDFs relevant, nicht hier. |

### Markdown/Text → PDF

| Werkzeug | Bewertung |
|---|---|
| **`typst compile`** | **Erste Wahl für „ohne Ballast".** Eine einzelne Binärdatei (~30 MB), keine TeX-Distribution, Kompilierung in Millisekunden, gute Typografie ab Werk. Nachteil: Markdown ist nicht seine Eingabesprache — es braucht entweder pandoc davor oder eine kleine eigene Markdown→Typst-Vorlage. |
| **`pandoc --pdf-engine=…`** | **Erste Wahl für Korrektheit.** Beherrscht Markdown-Dialekte, Fußnoten, Zitate, Inhaltsverzeichnis, Vorlagen. Aber: braucht zwingend eine Engine. Reihenfolge der Engine-Suche: `tectonic` (lädt TeX-Pakete selbst nach, kein 4-GB-TeXLive) → `typst` (pandoc ≥ 3.1.11 kann `--pdf-engine=typst`) → `xelatex`/`lualatex`/`pdflatex` → `weasyprint`/`wkhtmltopdf` (HTML-Umweg, schlechtere Seitenumbrüche). |
| `mdview.nvim` + Browserdruck | Vorhanden im eigenen Ökosystem, aber der Weg führt über einen Browser-Tab und manuelles Drucken — nicht scriptbar. Verworfen. |
| `md-to-pdf`, `mdpdf` (npm) | Node-Abhängigkeit für etwas, das pandoc/typst besser können. Verworfen. |

### HTML → PDF

`weasyprint` (sauberes CSS-Paged-Media, Python) → `chromium --headless
--print-to-pdf` (überall vorhanden, aber gruselige Kommandozeile und
Ränder-Voreinstellungen) → `wkhtmltopdf` (unmaintained, alte WebKit-Engine,
nur als letztes Glied).

### Office → PDF

`soffice --headless --convert-to pdf --outdir <dir> <file>` deckt
docx/odt/xlsx/pptx in einem Aufruf ab. Schwergewichtig und langsam beim
ersten Start, aber die einzige realistische Option. Optional, ganz hinten.

### PDF → PDF (Zusammenführen, Phase 2)

`qpdf --empty --pages a.pdf b.pdf -- out.pdf` (klein, exakt, keine
Neukodierung) → `pdftk` → Ghostscript. Nicht Teil der ersten Ausbaustufe,
aber die API wird so geschnitten, dass es später ohne Bruch dazukommt.

### Fazit

Erste Ausbaustufe: **`img2pdf` → `magick`** für Bilder, **`pandoc` (+ Engine)
→ `typst`** für Text/Markdown. Alles andere sind zusätzliche Producer in
derselben Registry, kein Umbau.

---

## 3. Architektur

Bewusst spiegelbildlich zum vorhandenen Lesepfad, damit niemand zwei Muster
lernen muss:

```
                LESEN (heute)                    SCHREIBEN (neu)
  API           pdfport.open/extract             pdfport.create
  Koordination  core/dispatcher.lua              core/composer.lua
  Auswahl       core/resolver.lua                core/resolver.lua  (erweitert)
  Registry      registry.register_backend        registry.register_producer
  Implementierung backends/*.lua                 producers/*.lua
  Ausgabe       renderers/*.lua                  (Datei auf Platte)
```

Neue Dateien:

```
lua/pdfport/producers/init.lua      -- Lazy-Proxy-Registrierung, wie backends/init.lua
lua/pdfport/producers/img2pdf.lua
lua/pdfport/producers/magick.lua
lua/pdfport/producers/pandoc.lua
lua/pdfport/producers/typst.lua
lua/pdfport/producers/weasyprint.lua   -- Phase 2
lua/pdfport/producers/soffice.lua      -- Phase 2
lua/pdfport/core/composer.lua
lua/pdfport/util/tmpfile.lua        -- Puffer-/String-Eingaben materialisieren
```

Wiederverwendet ohne Änderung: `platform.has`, `util/notify`, die
Fortschrittsanzeige aus `dispatcher.lua` (wandert dafür in einen kleinen
gemeinsamen Helfer, statt kopiert zu werden), `lib.nvim.cross.uv.spawn_capture`.

**Kein Cache.** Der Lesepfad cached, weil dieselbe PDF wiederholt gelesen wird;
ein Export ist eine einmalige, explizite Aktion mit einem Zielpfad — dieselbe
Begründung, die in `images.convert` schon für `to_pdf` steht.

### Producer-Schnittstelle

```lua
---@alias PdfPort.InputKind "image"|"markdown"|"html"|"text"|"office"|"pdf"

---@class PdfPort.ProducerCapabilities
---@field batch boolean      # mehrere Eingaben → ein Dokument
---@field lossless boolean   # bettet Quelldaten unverändert ein
---@field styling boolean    # Seitengröße/Ränder/Vorlage werden beachtet
---@field toc boolean        # kann ein Inhaltsverzeichnis erzeugen
---@field remote boolean     # braucht Netz

---@class PdfPort.Producer
---@field id PdfPort.ProducerId
---@field name string
---@field accepts PdfPort.InputKind[]
---@field capabilities PdfPort.ProducerCapabilities
---@field available fun(): boolean
---@field create fun(req: PdfPort.InternalCreateOpts): PdfPort.CreateResult|nil
```

`create` folgt exakt der Konvention von `Backend.extract`: asynchrone Producer
geben `nil` zurück und rufen `req.__callback`, synchrone geben direkt ein
Ergebnis zurück — der Composer behandelt beides (siehe `dispatcher.lua:228`).

### Ergebnis

```lua
---@class PdfPort.CreateResult
---@field status "ok"|"error"|"partial"
---@field path string|nil        # erzeugte Datei
---@field producer PdfPort.ProducerId
---@field pages integer|nil
---@field error string|nil
```

---

## 4. Öffentliche API

Ein Einstiegspunkt, absichtlich in derselben Form wie `open`/`extract`
(Tabelle rein, `__callback` raus):

```lua
require("pdfport").create({
  -- Eingabe: genau eines von inputs / text / bufnr
  inputs  = { "/pfad/a.png", "/pfad/b.png" },  -- Dateien, Reihenfolge = Seitenreihenfolge
  -- text = "# Titel\n\nAbsatz",               -- Inhalt direkt
  -- bufnr = 0,                                -- Pufferinhalt

  from    = "image",          -- optional; sonst aus Endung/`filetype` erraten
  output  = "/pfad/out.pdf",  -- optional; Default: neben der ersten Eingabe, gleicher Stamm

  producer_id = nil,          -- optional; nil = Auto über die Kette
  on_conflict = "overwrite",  -- "overwrite" | "suffix" (out-1.pdf) | "error"

  opts = {                    -- alles optional, Producer ignorieren Unbekanntes
    page_size = "A4",
    margin    = "20mm",
    dpi       = 300,          -- nur Bildpfad
    fit       = "contain",    -- "contain" | "fill" | "native"
    title     = nil,
    toc       = false,        -- nur Textpfad
    template  = nil,          -- pandoc/typst-Vorlage
    timeout_ms = 60000,
  },

  __callback = function(res) ... end,  -- optional; ohne = Fire-and-forget mit notify
})
```

Zusätzlich, weil beides in der Praxis sofort gebraucht wird:

```lua
require("pdfport").register_producer(p)            -- analog register_backend
require("pdfport").can_create("markdown")          -- boolean, für Soft-Deps der Aufrufer
require("pdfport").merge({ inputs, output, ... })  -- Phase 2, qpdf/Ghostscript
```

Und der Vollständigkeit halber die schon in [ROADMAP.md](../ROADMAP.md)
notierte Gegenrichtung `render_page(path, page, opts, cb)` (PDF-Seite → PNG):
gleiche Signaturform, gleiche Registry-Denkweise, sollte zusammen mit diesem
Konzept entworfen werden, damit `images.nvim` beide Richtungen einheitlich
anspricht.

### Kommandos

Im vorhandenen Ein-Verb-Komposer (`:PdfPort <sub>`), keine neuen Flachbefehle:

```
:PdfPort create              " aktueller Puffer → PDF daneben
:PdfPort create <datei…>     " eine oder mehrere Dateien → ein PDF
:PdfPort producers           " Diagnose, analog `:PdfPort backends`
```

Visuelle Auswahl im Dateibaum → ein PDF läuft über `util/batch.lua`, das die
Zeilen-für-Zeile-Auflösung schon kann.

### Konfiguration

```lua
require("pdfport").setup({
  create_opts = { page_size = "A4", margin = "20mm", dpi = 300, timeout_ms = 60000 },
  create_chain = {                       -- pro Eingabeart, wie fallback_chain
    image    = { "img2pdf", "magick" },
    markdown = { "pandoc", "typst" },
    html     = { "weasyprint", "chromium", "wkhtmltopdf" },
    office   = { "soffice" },
  },
  pdf_engine = "auto",                   -- pandoc: auto|tectonic|typst|xelatex|…
})
```

---

## 5. Anbindung der drei Aufrufer

Überall **Soft-Dependency über `pcall`**, wie im ganzen Ökosystem üblich: fehlt
pdfport, bleibt das bisherige Verhalten.

### `images.nvim` — erledigt (2026-08-09)

`images.convert.to_pdf` ist jetzt die dünne Weiche: ist pdfport da und meldet
`can_create("image")` einen Producer, geht der Export dorthin (asynchron,
verlustfrei über `img2pdf`, sonst `magick` — welcher Producer greift,
entscheidet pdfports eigene `create_chain`); sonst bleibt der bisherige
synchrone `magick`-Pfad wortgleich als Fallback stehen. Fast wortgleich zum
hier skizzierten Code umgesetzt, nur mit einem `on_done(ok, out_or_err)`
statt eines synchronen Rückgabewerts — der pdfport-Pfad ist async, der
magick-Pfad ruft `on_done` synchron auf, damit `images.export()` (der
öffentliche `:Image export`-Einstieg) beide Pfade einheitlich behandelt,
statt zwei Aufrufkonventionen zu unterscheiden:

```lua
function M.to_pdf(path, on_done)
  local ok, pdfport = pcall(require, "pdfport")
  if ok and pdfport.can_create("image") then
    pdfport.create({ inputs = { path }, from = "image", __callback = function(result)
      if on_done then on_done(result.status == "ok", result.path or result.error) end
    end })
    return nil, nil
  end
  -- … bisheriger magick-Pfad unverändert, ruft on_done synchron …
end
```

**Nicht umgesetzt** (bewusst außerhalb dieses Umfangs): `:Image gallery` /
eine Mehrfachauswahl → **ein** mehrseitiges PDF statt n Einzeldateien. Bliebe
ein sinnvoller Folgeschritt, ist aber ein neues UI-/Auswahl-Feature in
images.nvim selbst, keine reine Anbindung.

### `markdown.nvim` — erledigt (2026-08-09)

`:Markdown export pdf` — neues `markdown.commands.export`, exakt nach dem
Muster von `markdown.commands.image` (der bestehenden images.nvim-Anbindung):
ein unveränderter Puffer mit Datei auf der Platte exportiert die Datei direkt
(`from = "markdown"`); ein ungespeicherter/neuer Puffer exportiert stattdessen
den Pufferinhalt (`bufnr = 0`, `from = "markdown"`, `output` explizit gesetzt
— pdfport materialisiert selbst über `util/tmpfile.lua`). Das Plugin kennt
weder pandoc noch eine Engine; die Enttäuschung „nichts installiert"
formuliert pdfport, nicht markdown.nvim (`can_create("markdown")` gated die
Subcommand-Ausführung vorab). Gated über `config.feature_enabled("export")`,
wie jedes andere `:Markdown`-Subcommand.

### `filetree.nvim` — erledigt (2026-08-09)

`util/pdf.lua` war bereits „der eine Ort, an dem filetree mit pdfport
spricht" und bekam `M.create(paths, opts)`. Ziel-Ermittlung wie bei
`trash`/`copy_move` (markierte Knoten, sonst aktueller Knoten; ein
Ordner-Knoten expandiert zu seinen direkten Kind-Dateien, nicht rekursiv) im
neuen Feature `features/system/pdf_create` (Taste `gP`), das immer über
`filetree.util.confirm` (= `lib.nvim.ui.kit.confirm`) nachfragt, bevor
irgendetwas geschrieben wird. Eine PDF pro Eingabedatei (kein Merge einer
Mehrfachauswahl in eine gemeinsame PDF — bei gemischten Dateitypen in einem
Ordner ergäbe das ohnehin keinen Sinn).

> **Bereits gefixt (2026-08-07):** `filetree/util/pdf.lua`s `M.has_pdfport()`
> und `M.open()` riefen schon vor diesem Durchgang korrekt `require("pdfport")`
> auf, nicht `require("pdfport_nvim")` — der Bug aus der persönlichen Roadmap
> bestand zu diesem Zeitpunkt bereits nicht mehr.

---

## 6. Fallstricke, vorab entschieden

- **Nie eine Shell-Zeichenkette, immer eine Argumenttabelle.** Der
  `cmd /c start`-`&`-Bug (2026-07-25, fünf Repos) ist genau daran entstanden.
  Alle Producer spawnen über `spawn_capture` mit `argv`-Tabelle.
- **ImageMagick unter Windows**: `magick` ist der Aufruf, `convert.exe`
  kollidiert mit Windows' eigenem `convert`. `platform.has("magick")`, nie
  `convert`.
- **Zielpfad-Konflikt** ist eine bewusste Entscheidung des Aufrufers
  (`on_conflict`), keine stille Überschreibung im Kern. Default für die
  Kommandos: `suffix`; für den API-Aufruf: was der Aufrufer setzt,
  `overwrite` als Default, weil `images.convert.to_pdf` sich heute schon so
  verhält.
- **Puffer ohne Datei / `text`-Eingabe** landen über `util/tmpfile.lua` in
  `stdpath("cache")/pdfport.nvim/tmp` und werden nach dem Lauf gelöscht —
  auch im Fehlerfall (`vim.schedule` + `pcall`).
- **Relative Bildpfade in Markdown** brechen, wenn im Temp-Verzeichnis
  kompiliert wird. pandoc/typst deshalb mit `--resource-path` bzw. `--root`
  auf das Verzeichnis der Quelldatei aufrufen.
- **Timeouts**: Erstellung darf lange dauern (LaTeX-Erstlauf, soffice-Start),
  Default deshalb 60 s statt der 30 s des Lesepfads.
- **Fortschritt** kommt geschenkt, sobald der Composer denselben
  `start_progress`-Helfer nutzt wie der Dispatcher — der wandert dafür aus
  `dispatcher.lua` in ein gemeinsames Modul.

---

## 7. Ausbaustufen

1. ~~**P0 — Gerüst + Bilder.**~~ **Erledigt (2026-08-09).** `@types`-Erweiterung,
   `registry.register_producer`, `core/composer.lua`, `producers/img2pdf.lua` +
   `producers/magick.lua`, `pdfport.create`/`can_create`, `:PdfPort create`,
   `:PdfPort producers`, `health.lua`-Abschnitt, Tests (`TESTS/producer_spec.lua`).
   Die API ist jetzt nutzbar (`opts.inputs` = Dateipfade; `text`/`bufnr`-Eingaben
   bleiben P1). Noch offen: die eigentliche Anbindung in `images.nvim` selbst (P2).
2. ~~**P1 — Text.**~~ **Erledigt (2026-08-09), reduzierter Zuschnitt.**
   `producers/pandoc.lua` mit interner Engine-Auto-Erkennung (tectonic →
   typst → xelatex → lualatex → pdflatex, via `--pdf-engine`), `from =
   "markdown"|"text"`, `util/tmpfile.lua` (`opts.text`/`opts.bufnr` in
   `pdfport.create()`, mit Pflicht-`from`+`output`, Cleanup nach dem
   Ergebnis-Callback). Kein separater `producers/typst.lua` — laut Abschnitt
   2 braucht typst als direkte Markdown-Quelle ohnehin pandoc davor oder
   eine eigene Vorlage, deckt sich also mit pandocs `--pdf-engine=typst`
   statt ein zweiter Top-Level-Producer zu sein. `:Markdown export pdf`
   selbst ist weiterhin P2 (Aufrufer-Anbindung).
3. ~~**P2 — Aufrufer anbinden.**~~ **Erledigt (2026-08-09), alle drei.**
   filetree-Bugfix (`pdfport_nvim`) bereits gefixt vorgefunden. `filetree.nvim`:
   `util/pdf.create()` + Feature `pdf_create` (Marks/aktueller Node/Ordner,
   Bestätigung über `lib.nvim.ui.kit`). `images.nvim`: `convert.to_pdf`/
   `M.export` routen asynchron über `pdfport.create()`, wenn verfügbar (sonst
   unverändert `magick`). `markdown.nvim`: `:Markdown export pdf`
   (`markdown.commands.export`, exakt nach dem `commands.image`-Muster). Alle
   drei dokumentiert im jeweils eigenen Repo. Nicht umgesetzt: `:Image
   gallery`/Mehrfachauswahl → ein gemeinsames mehrseitiges PDF — eigenes
   UI-Feature in images.nvim, keine reine Anbindung, siehe Abschnitt 5.
4. ~~**P3 — Breite.**~~ **Erledigt (2026-08-09).** `weasyprint`/`chromium`
   (HTML), `soffice` (Office), `pdfport.merge()` über
   `qpdf`/`pdftk`/`ghostscript` (registriert als normale "pdf"-Producer,
   `merge()` ist ein dünner Wrapper um `composer.create({ from = "pdf" })`).

## 8. Tests

Nach dem Muster von `TESTS/registry_spec.lua`/`resolver_spec.lua`, headless und
ohne Framework: ein **Stub-Producer**, der keine externe Binärdatei braucht,
deckt Registrierung, Ketten-Auflösung pro `InputKind`, `on_conflict`, den
synchronen *und* den `__callback`-Rückgabeweg sowie den Fehlerfall „kein
Producer verfügbar" ab. Die echten Producer bleiben in CI ungetestet — dieselbe
Linie wie bei den Extraktions-Backends.
