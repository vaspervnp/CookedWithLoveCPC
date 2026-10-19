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
| Playfield | 160×168 (40 CRTC chars × 21 rows) | Κάνει scroll |
| HUD | 160×32 (4 rows) | Σταθερό: χρήματα, ώρα, παραγγελίες, ενεργός χαρακτήρας |

Ο διαχωρισμός playfield/HUD γίνεται με **CRTC vertical rupture** (δύο CRTC frames ανά VBL, συνολικά 312 γραμμές): το playfield διαβάζει από τη σελίδα `&C000`, το HUD από τη σελίδα `&8000`. Το HUD πιάνει μόνο 320 bytes σε κάθε 2K block της `&8000`· το υπόλοιπο της σελίδας μένει ελεύθερο για κώδικα/δεδομένα.

### 3.3 Scrolling (σχεδιασμένο από την αρχή για το ελάχιστο βήμα)

Κάθε πίστα είναι **4×4 οθόνες playfield** = 640×672 pixels.

| Άξονας | Στόχος | Τεχνική | Fallback |
|---|---|---|---|
| Οριζόντιος | **2 px (1 byte)** — το ελάχιστο σε Mode 0 χωρίς pre-shifted γραφικά | R12/R13 (βήμα 2 bytes = 4 px) + μετατόπιση μισού char με R3 (HSYNC) στα ενδιάμεσα βήματα | 4 px (μόνο R12/R13) |
| Κάθετος | **1 scanline** | R12/R13 για ολόκληρα rows (8 γραμμές) + fine offset μέσω ρύθμισης R9/R5 στα CRTC frames του rupture, με αντιστάθμιση στο frame του HUD ώστε το σύνολο να μένει 312 γραμμές | 8 γραμμές (1 char row) |

Σημειώσεις:
- Οι τεχνικές R3/R5/R9 διαφέρουν ανά τύπο CRTC (0/1/2/3/4). Ο κώδικας scroll απομονώνεται σε ένα module (`src/engine/scroll.asm`) με εναλλακτικές υλοποιήσεις και ανίχνευση τύπου CRTC στην εκκίνηση. Αν μια τεχνική δεν δουλεύει σε κάποιο CRTC, πέφτουμε στο fallback.
- Η μνήμη οθόνης "τυλίγει" ανά 1024 words σε κάθε 2K block, οπότε το scroll είναι συνεχές· σε κάθε βήμα σχεδιάζεται μόνο η νέα στήλη/γραμμή tiles που μπαίνει στην οθόνη.
- Με οριζόντιο βήμα 2 px, νέα στήλη 4 px χρειάζεται μόνο σε κάθε δεύτερο βήμα.
- Η κάμερα ακολουθεί τον ενεργό χαρακτήρα με dead-zone, ώστε να μη γίνεται scroll σε κάθε κίνηση.
- Πρώτο milestone είναι ένα **prototype scroll** που επικυρώνει τα παραπάνω στο Caprice32 (βλ. TODO.md, M1).

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
| `&0040–&3FFF` | Κύριος κώδικας engine, tables (mask, flip), stack |
| `&4000–&7FFF` | Παράθυρο banking (`&7FC4`–`&7FC7`): sprites, κείμενα, συνταγές, χάρτες |
| `&8000–&BFFF` | Σελίδα HUD (μόνο οι γραμμές του HUD) + game logic + buffers |
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
make run-en     # τρέχει στο Caprice32
```

Τι κάνει το Makefile (ενδεικτικά):

```bash
python3 tools/png2cpc.py ...                 # assets → build/*.bin
python3 tools/text2asm.py --lang en          # κείμενα → build/text_en.asm
rasm src/main.asm -DLANG_EN=1 -o build/cwl_en
iDSK build/cwl_en.dsk -n
iDSK build/cwl_en.dsk -i build/cwl_en.bin -t 1 -c <load> -e <exec>
```

Εκτέλεση:

```bash
caprice32.launcher build/cwl_en.dsk
```

Στον emulator: `RUN"CWL`.

## 9. Δοκιμές

- Κάθε milestone δοκιμάζεται στο Caprice32 (CPC 6128, CRTC type 0).
- Οι τεχνικές CRTC (scroll/rupture) πρέπει να δοκιμαστούν και σε άλλους τύπους CRTC (σε emulator που το υποστηρίζει ή σε πραγματικό μηχάνημα) πριν κλειδώσει ο engine.
- Debug build (`make DEBUG=1`): border colour timing για μέτρηση χρόνου CPU ανά routine.
