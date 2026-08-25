# Menu inspection findings (§5 — inspect before you build)

*What 16 real drink menus actually look like, transcribed into `Tooling/Fixtures/`. This is
the R1 lever: the parser and `BeverageKnowledge` get designed against **this**, not against
remembered menu formatting. Two findings here change the Phase 2 model and the Phase 5
parser — flagged **⚠ DESIGN CHANGE**.*

Sample: 16 photos spanning clean digital menus (Bluegill, Rullo's, Beach House), photographed
laminated cards at an angle (El Perrito, Selections From the Bar), a dense sports-bar menu
with a standard-serving table, a handwritten "rough draft," and a low-contrast 1940s menu.

---

## Finding 1 — Price is written ~8 different ways (core R1 risk)

Across the sample, a "price" appears as:

| Form | Seen on | Example |
|---|---|---|
| `$` + integer | Bluegill | `Sunset Tea $8`, `The Best Margarita $13` |
| bare trailing integer | El Perrito, colored beer lists | `The Top Dawg        8` |
| dot-leader + integer | Selections From the Bar | `The Queen Mother ... 12` |
| `•` / `-` + integer | Beach House | `bushwacker ... - 12` |
| decimal (no `$`) | Beach House bottles | `miller lite - 4.25` |
| `$` + decimal (cents) | sports bar | `$7.39`, `$6.99` |
| price **in words** | Selections "ON DRAUGHT" | `20 oz for nine dollars` |
| price on the **section header**, not the item | Rullo's | `Elixirs \| $14` then unpriced items |

**Implication for the price regex (Phase 5):** match, in priority order, `\$?\d{1,3}\.\d{2}`
→ `\$\d{1,3}` → a bare `\b\d{1,3}\b` in a *price position* (end of line, or after `...`/`•`/`|`).
**Reject** integers that are really something else: followed by `%`, `oz`, `ABV`, `mL`; inside
`()`; or a 4-digit year. Price-in-words is a rare edge case → send to `needsPrice`.

### ⚠ DESIGN CHANGE A — the parser must track section state
Rullo's prices its cocktails only on the category header (`Elixirs | $14`, `Back to Basics |
$10`). A purely line-by-line parser reads every Rullo's cocktail as priceless and dumps the
whole menu into `needsPrice` — a total miss on a clean menu. So `MenuParser` needs a running
**section** that can supply (a) a default/header price items inherit, and (b) the beverage
category (next finding). Architecturally: the parser is a small state machine over lines
(`enter section` / `item` / `description`), not a `map` over independent lines. This is still
pure and fixture-testable; it just isn't stateless.

---

## Finding 2 — ABV and size ARE printed often enough that `.read` really fires

The provenance design (§11) assumed most ABV/size would be `.estimated`. True for cocktails —
but beer and wine menus print real numbers constantly:

- **ABV printed:** Thirsty Duck (`4.2%ABV` … `8.2%ABV` on every tap), Rullo's (`(4.7%)`),
  Selections on-draught (`6.4%`), Beach House (`5.8%`). Regex: `(\d+(?:\.\d+)?)\s*%\s*ABV?`
  and `\((\d+(?:\.\d+)?)%\)`.
- **Size printed:** wine "by the glass" + oz pours (`$9 GLASS`, `9 oz pour`), `20 oz` / `10 oz`
  drafts, `1 oz` spirit / `3 oz` wine in a sangria build.

This is good news — it means `ABVEstimator`/`SizeEstimator` return `.read` on a real slice of
lines, and the honesty UI (§11) will show a healthy mix rather than "everything's a guess."
Keep the fixtures with printed ABV (Thirsty Duck, Rullo's) as the `.read`-path tests.

---

## Finding 3 — Category taxonomy → seeds `BeverageKnowledge`

Section headers seen, grouped into the categories the estimator will map to a typical
ABV + pour:

| Category (→ `BeverageCategory`) | Header phrasings seen | Typical ABV / pour (seed) |
|---|---|---|
| `.draftBeer` | ON TAP, ON DRAUGHT, DRAFT BEER, Draft Selections | ~5% / 16 oz |
| `.bottledBeer` | BOTTLES/CANS, TALL BOY CANS, Bottled Beer, Imports, Domestic Beer | ~5% / 12 oz |
| `.wineGlass` | WINE, REDS, WHITES, Rosé, By the Glass | ~12% / 5 oz |
| `.cocktail` | COCKTAILS, Specialty, Original Cocktails, Elixirs, Signature | ~ mixed / ~standard serving |
| `.frozenCocktail` | Frozen Cocktails, Frozen Margaritas | ~ mixed / larger serving |
| `.martini` | Martinis, Old-Fashioneds | spirit-forward / smaller serving |
| `.shot` | SHOTS | ~40% / 1.5 oz |
| `.seltzer` | Seltzers, Canned Cocktails, Hard Seltzer | ~5% / 12 oz |
| `.nonAlcoholic` | Non-Alcoholic, Mocktails, Booze Free Fun, N/A | 0% |

Cocktails are the soft spot (R2): a `.cocktail` ABV is a whole-drink guess that varies wildly.
The seed is a defensible default, visibly flagged and one-tap correctable — not a promise.

### ⚠ DESIGN CHANGE B — `.nonAlcoholic` is a first-class category that gets excluded
Every third menu has a priced non-alcoholic section (Mocktails $7, Non-Stop Pop $3.29, Phony
Negroni). These have a real price, so the price invariant doesn't stop them — but ranking a $7
mocktail as "0 standard drinks per dollar" pollutes the list. So `.nonAlcoholic` is an explicit
`BeverageCategory` case, and the enrichment step drops those items **before** ranking (they're
not "couldn't read a price" — they're "not alcohol"). Worth a dedicated bucket + test.

---

## Finding 4 — Description lines would flood `needsPrice` if untreated

Under most cocktails sits an ingredient line with no price (`Sauza blanco, Cointreau, fresh
lime juice…`). Naively, every one of those is a priceless line → `needsPrice` noise that
buries the real read failures. **Heuristic (Phase 5):** a priceless line immediately following
a priced item — especially lowercase, comma-listy, no leading title case — is a *description*
of that item, not a new drink. Attach it; don't bucket it. The honest `needsPrice` count then
means what it should (§11 "report loss honestly").

---

## Finding 5 — Multi-price items (glass/bottle, size tiers)

`$9 GLASS / $32 BOTTLE`, `Red | $11 / $40`, `Boston Size $7.39 / Pitcher $18.99`,
`4 for 18 / 6 for 28`. **v1 rule:** take the single-serving / by-the-glass (smallest) price as
the canonical `PricedDrink`; note the simplification. Splitting into multiple `DrinkOption`s is
a post-v1 nicety (goes on the cut-first list, not the critical path).

---

## Finding 6 — OCR will be messy (R1, unchanged but confirmed)

Watermarks over text (Selections From the Bar), glare and steep angles (El Perrito, held
menus), handwriting ("rough draft 5/14"), and a low-contrast vintage menu. Confirms the R1
mitigation: OCR is *assist*, the manual add/edit path is non-negotiable, and a partial read
must still be useful.

---

## What this changes, concretely

- **Phase 2 (CoreModel):** add `.nonAlcoholic` to `BeverageCategory` (Change B); nothing else
  in the spine changes — `DrinkOption`/`PricedDrink`/`Provenance` still hold.
- **Phase 3 (Contracts):** `BeverageKnowledge` seed table uses the Finding-3 categories.
- **Phase 5 (Parser):** section-state machine (Change A), the Finding-1 price regex, the
  Finding-4 description heuristic, Finding-5 multi-price rule, and the `.nonAlcoholic` drop.
- **Fixtures now carry the hard cases** (header-priced Rullo's, word-priced draught, printed
  ABV, non-alcoholic sections) so Phase 5 is proven against them, not against easy menus.
