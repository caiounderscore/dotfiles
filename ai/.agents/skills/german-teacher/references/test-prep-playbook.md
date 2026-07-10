# Test-prep playbook (Klassenarbeit / surprise test)

For when the learner has a near-term test that mirrors **DaF kompakt neu A2** Übungsbuch
exercises from specific Lektionen. Goal: maximize score on *that* test, not general fluency.

## Step 0 — Scope the test (ask first)
1. **Which Lektionen?** (e.g. "L9–L11"). If unknown, ask which units the class did most recently.
2. **When is it?** (today / tomorrow / in 2 days) → pick the schedule below.
3. **Format?** written only, or also speaking/listening? Any word list to memorize?
4. Pull the exact grammar for those units from `daf-kompakt-a2-map.md`.

## The loop (use for every grammar point)
**Diagnose → Mini-rule → Drill → Mock → Re-drill the misses → Log.**
- *Diagnose:* 3–5 quick items to find what's broken.
- *Mini-rule:* one compact rule/table in German (English gloss only if needed). No lectures.
- *Drill:* 8–12 items in the Übungsbuch formats. Correct each immediately.
- *Mock:* a timed mini-section that looks like the real test.
- *Re-drill:* redo only the error categories that failed.
- *Log:* append every miss to `~/.agents/state/language/german-mistakes-log.md` with its category.

## 2-day schedule (fits 45 min weekday / 90 min Saturday rhythm)

**Day 1 — diagnose + drill the high-yield points (≈ 60–90 min, split if needed)**
1. (10 min) Full diagnostic: 2 items per grammar point in the units → rank weakest.
2. (35 min) Drill the **top 3 weakest** points, loop above. Prioritize the endings cluster
   (article/adjective/possessive) and Dativ/Akkusativ — highest point value, your known gaps.
3. (15 min) Vocabulary + Redemittel for the units' themes (Wohnung, Feste, Gesundheit…).
4. (10 min) Update the log; note the 3 categories to attack tomorrow.

**Day 2 — mock test + targeted repair (≈ 45–60 min)**
1. (5 min) Warm-up from yesterday's log.
2. (25 min) **Full mock test** (blueprint below), timed, no help. Then grade together.
3. (15 min) Repair only the failed categories with fresh drills.
4. (10 min) Speaking/writing rehearsal if the test has it; final log update + a 5-line cheat recap.

**Same-day / <24 h crunch (≈ 45 min):** skip wide diagnosis. Go straight to the endings cluster
+ Dativ/Akkusativ + the units' two signature structures (e.g. *weil/dass*, Präteritum), then one
short mock. Better to master 3 things than half-learn 8.

## Mock-test blueprint (mirror the Übungsbuch)
Build ~6 blocks, scaled to the units. Keep instructions in German. Example shape:

1. **Tabelle ergänzen** — decline an article+adjective+noun across Nom/Akk/Dat (5 rows).
2. **Ergänzen Sie** — gap-fill a 8–10-line dialogue: article/adjective/possessive endings.
3. **Wechselpräpositionen** — 6 items, choose Akk (Wohin?) vs Dat (Wo?) and the right form.
4. **Schreiben Sie Sätze mit *weil/dass*** — combine 5 clause pairs (verb to the end).
5. **Präteritum / Konjunktiv II / Passiv** (whichever the units cover) — 6 transform items.
6. **Kurzer Text** — write 5–6 sentences on a unit theme using 3 required structures.

Grade out of a clear total, report a %, and list the **error categories** that cost points.

## Exercise templates by grammar point (generate variants from these)

**Adjektivendung (the money-maker)** — vary article type + case:
- *Ich kaufe ein___ schick___ Anzug.* → *einen schicken Anzug* (Akk, ein-).
- *Sie trägt ___ schwarz___ Barett.* → *ein schwarzes Barett* (Akk neut., ein-).
- *Ich helfe d___ neu___ Student.* → *dem neuen Studenten* (Dat + n-Deklination!).
Mini-rule: ein-words signal gender/case in the *adjective*; der-words don't (adjective takes -e/-en).

**Dativ vs. Akkusativ (Wechselpräpositionen)** — "Wohin? → Akk / Wo? → Dat":
- *Ich hänge das Bild an ___ Wand.* (Wohin → *die* Wand, Akk).
- *Das Bild hängt an ___ Wand.* (Wo → *der* Wand, Dat).

**Personalpronomen / Dativergänzung + word order (L9)** — Dat before Akk when both are nouns;
pronoun before noun: *Ich schenke meinem Bruder das Buch.* / *Ich schenke es ihm.*

**Possessivpronomen (L10)** — decline by the *possessed* noun's gender/case:
- *Das ist ___ (ich) Wohnung.* → *meine*. *Ich wohne in ___ (ich) Wohnung.* → *meiner*.

**weil / dass (L11)** — verb to the end:
- *Ich lerne Deutsch. Ich will in Deutschland studieren.* → *…, weil ich in Deutschland studieren will.*

**Reflexivpronomen Akk/Dat (L11)** — *Ich wasche mich.* (Akk) vs *Ich wasche mir die Hände.* (Dat).

**Präteritum (L12)** — table: *machen→machte, gehen→ging, bringen→brachte, können→konnte.*
Drill regular -te, strong vowel change, mixed, and modals.

**Komparativ/Superlativ (L10/L18)** — *billig–billiger–am billigsten*; irregulars
*gut–besser–am besten, viel–mehr–am meisten, hoch–höher, groß–größer, gern–lieber–am liebsten.*

**Konjunktiv II höflich (L16)** — *Könnten Sie…? Ich hätte gern… Ich würde gern… Dürfte ich…?*

**Relativsätze (L16)** — *Der Mann, **der** dort steht…* / *…, **den** ich kenne* / *…, **dem** ich helfe.*

**Passiv (L17)** — *Man baut das Haus.* → *Das Haus **wird gebaut**.* / Prät.: *…**wurde gebaut**.*

## Spelling watchlist (recurring slips — quiz these)
Zürich, arbeiten, schicken, Studenten, Geburtstag, möchten, Wohnung, Gesundheit, Ausbildung.

## Test-day micro-checklist (give to the learner)
- Read each instruction fully; underline the case asked (Wohin vs Wo).
- Endings: first find **gender + case**, then pick the ending. Don't guess by feel.
- Subordinate clause? Send the verb to the end. Modal? Infinitive at the end.
- Leave 3 min to re-check endings and the spelling watchlist words.
