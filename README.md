# Cooked with Love — Restaurant Simulator για Amstrad CPC

Top-down restaurant simulator για Amstrad CPC 6128, σε **Mode 0** με hardware scrolling.
Ο παίκτης διευθύνει ένα εστιατόριο με τρεις χαρακτήρες:

| Χαρακτήρας | EN | GR | Ρόλος | Δυσκολία |
|---|---|---|---|---|
| Σερβιτόρος | Bill | Βασίλης | Υποδοχή, παραγγελίες, σερβίρισμα, ταμείο | Easy+ |
| Μαγείρισσα | Liberty | Ελευθερία | Μαγείρεμα συνταγών | Medium+ |
| Υπεύθυνη αποθήκης | Blossom | Ανθή | Απόθεμα υλικών, παραλαβές | Hard |

Οι συνταγές προέρχονται από το κανάλι [Cooked with Love](https://www.youtube.com/@CookedwithLove) και το site [cookedwithlove.gr](https://www.cookedwithlove.gr/).

Ο σχεδιασμός και τα milestones βρίσκονται στο [TODO.md](TODO.md).

---

## 1. Εργαλεία

| Εργαλείο | Χρήση |
|---|---|
| **RASM** (v3.2.x) | Z80 assembler, built-in crunchers (ZX0/LZ4/aPLib κ.λπ.), απευθείας εγγραφή σε DSK |
| **iDSK** (v0.20) | Δημιουργία/διαχείριση εικόνων δισκέτας `.dsk` |
| **Caprice32** (snap, `caprice32.launcher`) | Emulator για δοκιμές |
| **Blender** (μέσω Blender MCP) | 3D μοντέλα → orthographic renders για sprites και έπιπλα |
| **Aseprite** (μέσω Aseprite MCP) | Pixel-art καθάρισμα, indexed palette, animation, tilesets |
| **Python 3** | Εργαλεία μετατροπής (PNG → CPC, χάρτες, κείμενα) στον φάκελο `tools/` |

## 2. Πλατφόρμα-στόχος

- **Amstrad CPC 6128** (128K). Τα extra 64K (banks `&C4`–`&C7`) χρησιμοποιούνται για sprites, κείμενα, συνταγές και χάρτες.
- Δισκέτα 3" σε format DATA (178K ανά πλευρά).
- Δύο ξεχωριστές δισκέτες: **English** (`cwl_en.dsk`) και **Ελληνικά** (`cwl_gr.dsk`). Ο κώδικας είναι κοινός· αλλάζουν μόνο τα δεδομένα κειμένου και η γραμματοσειρά, ώστε κάθε γλώσσα να έχει όλο τον διαθέσιμο χώρο για κείμενο.
- Ο firmware χρησιμοποιείται μόνο κατά τη φόρτωση· μετά το παιχνίδι παίρνει τον έλεγχο (δικός του interrupt handler στο `&0038`).

## 3. Γραφικά

### 3.1 Mode 0
- 160×200 pixels, 16 χρώματα από τα 27 της CPC palette.
- 1 byte = 2 pixels. Τα pixels είναι **φαρδιά (aspect 2:1)** — όλα τα assets σχεδιάζονται/αποδίδονται με pixel aspect 2:1.
- Κωδικοποίηση byte (p0 = αριστερό pixel, p1 = δεξί):

  ```
  bit:  7     6     5     4     3     2     1     0
        p0.0  p1.0  p0.2  p1.2  p0.1  p1.1  p0.3  p1.3
  ```

- Ενιαία palette 16 χρωμάτων για όλο το παιχνίδι (με πιθανή αλλαγή palette με raster interrupt στο HUD). Το **χρώμα 0 είναι διάφανο** στα sprites.

### 3.2 Οθόνη
| Περιοχή | Μέγεθος | Σημείωση |
|---|---|---|
| HUD (πάνω) | 160×32 (4 rows) | Σταθερό: χρήματα, ώρα, παραγγελίες, ενεργός χαρακτήρας |
| Playfield | 160×168 (40 CRTC chars × 21 rows) | Κάνει scroll |

Ο διαχωρισμός HUD/playfield γίνεται με **CRTC vertical ruptures**: τρία CRTC frames ανά VBL, συνολικά 312 γραμμές, ώστε για το monitor να είναι κανονικό frame ([src/engine/crtc.asm](src/engine/crtc.asm)). Το **R9 είναι πάντα 7**. Το fine vertical scroll γίνεται μόνο με το **R5 (vertical total adjust)**: οι γραμμές R5 στο τέλος ενός frame δείχνουν τα πρώτα rasters του row που ακολουθεί.

| Frame | Γραμμές* | Rows | Περιεχόμενο |
|---|---|---|---|
| B | 0–111 | 14 | Το row 0 δείχνει μαύρη μνήμη και μετά το R6=1 σβήνει το display. VSYNC στο row 7 |
| H | 112–151-fy | 4 + R5=8-fy | HUD (σελίδα `&8000`). Οι γραμμές R5 δείχνουν τα rasters fy..7 της πάνω γραμμής του playfield, από ένα buffer 40 words αμέσως μετά το HUD |
| A | 152-fy–311 | 20 + R5=fy | Playfield rows cy+1..cy+20 (ring στο `&C000`). Οι γραμμές R5 δείχνουν τα rasters 0..fy-1 του row cy+21 |

\* σε σχέση με την αρχή του B.

**Καμία εγγραφή στον CRTC δεν χρειάζεται χρονισμό ακριβείας**: κάθε εγγραφή έχει περιθώριο τουλάχιστον ενός row. Χρησιμοποιούνται τα interrupts των 300 Hz:
- **I5 (γραμμή 6):** σταθερές του B.
- **I0 (58, VSYNC):** απόφαση commit, R3 και R12/R13 του H, R6=127.
- **I1 (110):** commit, R4/R5 του H, R12/R13 του A.
- **I2 (162):** R4/R5/R7 του A.
- **I3 (214):** R6=1.
- **I4 (266):** R12/R13 του B (μαύρη περιοχή).

Το R6 δεν γίνεται ποτέ 0, γιατί στον CRTC 1 αυτό σβήνει αμέσως την οθόνη.

> Η πρώτη υλοποίηση άλλαζε το R9 μέσα στο frame (rows του 1 scanline). Δούλευε σε Caprice32 και CPCEC, αλλά στο Retro Virtual Machine η εικόνα πηδούσε πάνω-κάτω. Ο σχεδιασμός με R5 αποφεύγει εντελώς αυτή την περιοχή όπου διαφέρουν οι CRTC.

### 3.3 Scrolling (ελάχιστο βήμα: 2 px × 1 γραμμή) — υλοποιημένο στο M1

Κάθε πίστα είναι **4×4 οθόνες playfield** = 640×672 pixels (χάρτης 80×84 tiles των 8×8). Θέση scroll: `sx` σε βήματα 2 px (0–240) και `sy` σε γραμμές (0–504).

| Άξονας | Βήμα | Τεχνική | Fallback |
|---|---|---|---|
| Οριζόντιος | **2 px (1 byte)**: το ελάχιστο σε Mode 0 χωρίς pre-shifted γραφικά | `cx = (sx+1)>>1` μέσω R12/R13 (βήμα 4 px). Στις μονές θέσεις R3=&85 αντί για &86 (HSYNC 1 char στενότερο), που μετακινεί την εικόνα 2 px δεξιά. Το HUD (και το buffer) έχει δεύτερο σετ μετατοπισμένο κατά 1 byte, ώστε το HUD να μένει ακίνητο. | 4 px (`FINE_X=0`) |
| Κάθετος | **1 scanline** | `cy = sy>>3` μέσω R12/R13 (βήμα 8 γραμμών). Το `fy = sy&7` μοιράζεται στο R5 του H (8-fy) και του A (fy). Σύνολο πάντα 168 γραμμές, με σταθερή θέση του παραθύρου. | 8 γραμμές (`FINE_Y=0`) |

Λεπτομέρειες ([src/engine/scroll.asm](src/engine/scroll.asm)):
- **Ring οθόνης:** το char (X,Y) του χάρτη βρίσκεται στο word `(Y*40+X) & 1023` κάθε 2K block, οπότε το παράθυρο είναι πάντα συνεχές από το `cy*40+cx`. Σε κάθε βήμα ζωγραφίζεται μόνο η νέα στήλη (22 chars) ή γραμμή (40 chars). Το ring δεν αλλάζει ποτέ για το fine scroll.
- **Buffer πάνω γραμμής:** τα rasters fy..7 της γραμμής cy αντιγράφονται (≤640 bytes) μετά το HUD κάθε σετ.
- **Συγχρονισμός με τη δέσμη** (`scroll_update`): μνήμη οθόνης που φαίνεται αλλάζει μόνο όταν δεν τη διαβάζει ο CRTC.
  - Οι νέες γραμμές του χάρτη ζωγραφίζονται αμέσως, γιατί είναι έξω από το ορατό παράθυρο.
  - Το buffer αντιγράφεται μετά το I2, όταν το H έχει ήδη εμφανιστεί.
  - Η νέα στήλη ζωγραφίζεται από πάνω προς τα κάτω μετά το I4, πάντα πίσω από τη δέσμη, και ενημερώνεται το αντίστοιχο κομμάτι του buffer.
  - Το commit γίνεται στο I0/I1, πριν ξαναεμφανιστεί το H.
- **Γνωστά θέματα:**
  - Στις μονές θέσεις X ολόκληρη η εικόνα (και οι άκρες) μετακινείται 2 px, οπότε οι πλευρικές άκρες «τρεμοπαίζουν» κατά 2 px.
  - Το R3 trick βασίζεται στην αντίδραση του monitor και θέλει δοκιμή σε πραγματικό CPC/CTM.
  - Η νέα στήλη πρέπει να τελειώσει πριν από το I0 (~γραμμή 370). Αν αργήσει, για 1 frame φαίνεται glitch στην άκρη.
- Η κάμερα θα ακολουθεί τον ενεργό χαρακτήρα με dead-zone.

### 3.4 Tiles και χάρτες
- Tile: 8×8 pixels (4 bytes × 8 γραμμές = 32 bytes). Ταιριάζει ακριβώς με 2 CRTC chars πλάτος και 1 row ύψος.
- Metatile: 16×16 pixels (2×2 tiles) για τον σχεδιασμό χαρτών.
- Χάρτης πίστας: 40×42 metatiles = 1680 bytes (πριν τη συμπίεση).
- Κάθε tile έχει attributes: εμπόδιο, περιοχή (εστιατόριο/κουζίνα/αποθήκη), αντικείμενο αλληλεπίδρασης (τραπέζι, καρέκλα, φούρνος, ράφι...), κλειδωμένη περιοχή επέκτασης.

### 3.5 Sprites
- Χαρακτήρες: **32×48 pixels** = 16 bytes × 48 γραμμές = **768 bytes ανά frame**.
- Masked με lookup table 256 bytes (το χρώμα 0 είναι διάφανο) — δεν αποθηκεύεται ξεχωριστή μάσκα.
- Θέσεις X σε βήματα 2 px (byte-aligned) → δεν χρειάζονται pre-shifted εκδοχές.
- Κατευθύνσεις: πάνω, κάτω, πλάγια. Το αντίθετο πλάγιο προκύπτει με runtime flip (table αντιστροφής pixels μέσα στο byte + αντίστροφη σειρά bytes).
- Ενδεικτικά frames ανά χαρακτήρα: 3 κατευθύνσεις × (idle + 4 walk) + ειδικά (δίσκος, μαγείρεμα, κουτί) ≈ 20 frames ≈ 15K πριν τη συμπίεση. Αποθήκευση σε extra banks.
- Πελάτες: ίδιο μέγεθος, λιγότερα frames, παραλλαγές με palette swap/αλλαγή κεφαλιού. Όταν κάθονται, "σφραγίζονται" στο background και δεν ξανασχεδιάζονται κάθε frame.
- Κόστος: ~8–9 ms masked draw + ~4 ms restore ανά κινούμενο sprite. Στόχος **12.5 fps (κάθε 4 VBL)** για 4–6 κινούμενα sprites ταυτόχρονα, με dirty rectangles και restore από τον tile χάρτη.
- Σχεδίαση με beam racing (single buffer), ταξινόμηση sprites κατά Y για σωστό βάθος.

## 4. Χάρτης μνήμης (αρχικός)

| Διεύθυνση | Περιεχόμενο |
|---|---|
| `&0000–&003F` | RST / interrupt vector (`&0038`) |
| `&0040–&00FF` | Stack |
| `&0100–&3FFF` | Κύριος κώδικας engine (load/exec `&0100`), tables (mask, flip) |
| `&4000–&7FFF` | Παράθυρο banking (`&7FC4`–`&7FC7`): sprites, κείμενα, συνταγές, χάρτες |
| `&8000–&BFFF` | Σελίδα HUD: σε κάθε 2K block τα words 0–199 (HUD + buffer, σετ 0), 200–239 (μαύρα, για το B) και 512–711 (σετ 1 για R3 phase 1). Τα υπόλοιπα ~1K ανά block είναι ελεύθερα για δεδομένα |
| `&C000–&FFFF` | Οθόνη playfield (scroll) |

Ο χάρτης θα αναθεωρηθεί μετά το M1 και θα κρατηθεί ενημερωμένος εδώ.

## 5. Κείμενα και γλώσσες

- Πηγή κειμένων: `data/text/strings.tsv` (UTF-8, στήλες `id`, `en`, `gr`).
- `tools/text2asm.py` παράγει `build/text_en.asm` / `build/text_gr.asm` με κωδικοποίηση της γραμματοσειράς του παιχνιδιού και συμπίεση.
- Γραμματοσειρές: 8×8 (4 bytes/χαρακτήρας σε Mode 0, 20 στήλες) για διαλόγους, και πιο στενή 6×8 για το HUD. Η ελληνική γραμματοσειρά περιλαμβάνει πεζά, κεφαλαία και τονισμένα.
- Ο κώδικας αναφέρεται στα κείμενα μόνο με id· η γλώσσα επιλέγεται στο build (`LANG=EN|GR`).

## 6. Pipeline assets

```
Blender (MCP)            Aseprite (MCP)                 tools/                    RASM
3D μοντέλο ──render──▶  καθάρισμα pixel-art  ──PNG──▶  png2cpc.py  ──.bin──▶  INCBIN / crunch
ortho, 32×48,           indexed, CPC palette,          maps2asm.py
pixel aspect 2:1,       animation tags                 text2asm.py
flat/toon shading
```

1. **Blender**: orthographic κάμερα από πάνω (με ελαφριά κλίση ώστε να φαίνονται πρόσωπα/μπροστινή πλευρά επίπλων), resolution στο τελικό μέγεθος, `pixel_aspect_x = 2`, χωρίς anti-aliasing, flat/toon shading. Αρχεία στο `assets/blender/`.
2. **Aseprite**: indexed mode με την palette του παιχνιδιού, pixel ratio 2:1, καθάρισμα, animation με tags (`walk_down`, `idle_side`, …), tilesets ως tilemap layers. Αρχεία `.aseprite` στο `assets/aseprite/`, exports σε `assets/export/`.
3. **tools/png2cpc.py**: indexed PNG → Mode 0 bytes (sprites, tiles, γραμματοσειρές), έλεγχος ότι χρησιμοποιούνται μόνο χρώματα της palette.
4. **tools/maps2asm.py**: χάρτες (Aseprite tilemap ή Tiled) → metatile maps + attributes.
5. Η συμπίεση γίνεται από τον RASM (ZX0) κατά το build.

## 7. Δομή φακέλων

```
assets/
  blender/        .blend αρχεία
  aseprite/       .aseprite πηγές
  export/         PNG exports (generated)
data/
  palette.txt     η palette του παιχνιδιού
  maps/           χάρτες πιστών
  recipes/        συνταγές (yaml/tsv): υλικά, βήματα, χρόνοι, τιμές
  text/           strings.tsv
src/
  main.asm
  engine/         crtc, scroll, sprites, tiles, input, interrupts, banking
  game/           customers, waiter, cook, storage, recipes, economy, ai
  ui/             hud, menus, text
tools/            Python εργαλεία μετατροπής
build/            generated (δεν μπαίνει στο git)
```

## 8. Build & Run

```bash
make            # χτίζει και τις δύο δισκέτες
make en         # build/cwl_en.dsk
make gr         # build/cwl_gr.dsk
make run-en     # τρέχει στο Caprice32 (RUN"CWL αυτόματα)
make shot-en    # headless run + screenshot στο ~/snap/caprice32/current/screenshots/
make DEBUG=1    # debug build
```

Βήματα του Makefile:

1. `tools/palette.py` — `data/palette.txt` → `build/palette.asm` (hardware colours) και `assets/palette/cwl.gpl` (palette για Aseprite).
2. `rasm src/main.asm -Isrc -Ibuild -DLANG_EN=1` (ή `-DLANG_GR=1`) → `build/cwl_en.bin` + symbols.
3. `iDSK` → νέα δισκέτα με το `CWL.BIN` (binary, load/exec `&0100`).

Μετατροπή εικόνας:

```bash
python3 tools/png2cpc.py sprite.png sprite.bin                 # sprite, γραμμή-γραμμή
python3 tools/png2cpc.py tiles.png tiles.bin --layout tiles    # 8x8 tiles, 32 bytes το καθένα
```

Το PNG πρέπει να έχει μόνο χρώματα της palette (το διάφανο γίνεται pen 0)· διαφορετικά το εργαλείο σταματά και δείχνει τα λάθος χρώματα. Με `--halve` δέχεται εικόνα με τετράγωνα pixels σε διπλό πλάτος.

## 9. Δοκιμές

- Κάθε milestone δοκιμάζεται στο **CPCEC** (ακριβής προσομοίωση, CRTC 0–4), στο Caprice32 και από τον χρήστη στο **Retro Virtual Machine**.
- **CPCEC headless:** χτισμένο τοπικά από [cpcitor/cpcec](https://github.com/cpcitor/cpcec) στο `~/tools/cpcec`, με μικρό patch για screenshots ανά frame (μεταβλητές περιβάλλοντος `CPCEC_SHOTS`, `CPCEC_PREFIX`, `CPCEC_EXIT`). Το `tools/cpcecshot.sh` το οδηγεί και το `tools/cpcectest.sh` τρέχει όλη τη σουίτα: στατικές θέσεις, και bounce πάνω-κάτω / αριστερά-δεξιά με έλεγχο κάθε frame, για όλους τους τύπους CRTC.
- **Αυτόματος έλεγχος scroll:** test builds με `EXTRA="-DTEST_X=<sx> -DTEST_Y=<sy>"` (στατική θέση), `-DTEST_PATH=1|2` (σταδιακή κίνηση από την πάνω-αριστερή / κάτω-δεξιά γωνία). Το `tools/cpcshot.sh` βγάζει screenshot και το `tools/scrollcheck.py` το συγκρίνει pixel-pixel με την αναμενόμενη εικόνα (playfield, HUD και border).

  ```bash
  make en EXTRA="-DTEST_X=77 -DTEST_Y=250"
  tools/cpcshot.sh build/cwl_en.dsk build/shot.png
  python3 tools/scrollcheck.py build/shot.png 77 250
  ```

  Ολόκληρη η σουίτα (στατικές θέσεις, όλα τα fy, σταδιακή κίνηση και προς τις δύο κατευθύνσεις, fallbacks): `tools/scrolltest.sh`.

- `-DTEST_PATH=3` κάνει συνεχές bounce μεταξύ (0,0) και (TEST_X, TEST_Y), για δοκιμές σε άλλους emulators ή σε πραγματικό CPC.
- Το R3 trick πρέπει να δοκιμαστεί σε πραγματικό CPC/monitor. Για περιπτώσεις που δεν δουλεύει υπάρχουν τα fallbacks `FINE_X=0` / `FINE_Y=0`.
- Debug build (`make DEBUG=1`): το border γίνεται λευκό όσο δουλεύει ο main loop, για μέτρηση του χρόνου CPU.
