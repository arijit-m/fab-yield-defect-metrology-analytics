# Fab Yield & Defect Metrology Analytics Database

**A SQL Server data warehouse that models a semiconductor fab's manufacturing,
metrology, and final-test data — built so that analytical queries can trace a
yield loss back to the specific tool or chamber that caused it.**

> **Project status: Stages 1–3 complete; Stage 4 (GitHub packaging) remaining.**
> The 12-table schema is built and fully constrained (Stage 1); the database is
> populated with a large, internally-consistent synthetic dataset carrying a
> deliberately planted, subtle equipment excursion (Stage 2); and a five-part
> analysis layer *rediscovers that excursion from the data* — ruling out product
> and node, flagging the suspect tool, reading the contamination signature in the
> defect mix, quantifying a sub-sigma SPC shift, and finally isolating the exact
> chamber by commonality analysis, all without the answer ever appearing in a
> query (Stage 3). See the [Roadmap](#roadmap) for the stage-by-stage map.

---

## Why this project

In a semiconductor fab, yield — the fraction of dies on a wafer that pass final
test — is the number the whole operation is judged by. When yield drops, a yield
engineer has to answer one question fast: *which of the hundreds of tools and
chambers a wafer passed through is responsible?* Answering it means joining
final-test results back through the complete process history of every failing
wafer and finding what they share. That join is only possible if the underlying
data is modeled correctly in the first place.

This project builds that data model from the ground up in SQL Server, then writes
the analytical queries a yield engineer actually runs against it. The headline
query is **commonality analysis**: given a population of wafers, find the tool or
chamber whose wafers fail at a statistically higher rate than its peers — the
data-driven core of root-cause investigation on a real line.

It is the SQL/data-engineering half of a two-project portfolio. Its companion,
[**Wafer Map Defect Pattern Classification (WM-811K)**](https://github.com/arijit-m/Wafer-map-defect-classification),
takes the die-level pass/fail data this database produces and classifies the
*spatial pattern* of the failures with machine learning. The two projects meet
at one table — `bin_results`, whose `(die_x, die_y, bin)` shape is exactly what
the ML pipeline consumes — so the SQL side is the upstream data source and the ML
side is the downstream analysis. See [The bridge to the ML
project](#the-bridge-to-the-ml-project).

---

## A note on the data — synthetic by design

The data in this project is **generated, not collected from a real fab.** That is
a deliberate methodological choice, not a limitation, and the README is explicit
about it because a portfolio should never imply access to proprietary production
data it does not have.

The advantage of generating the data is **a known ground truth.** One specific
piece of equipment — etch tool `ETCH-02`, chamber `C` — is engineered to run
slightly worse than its peers, and the effect is planted *through the same join
paths a real excursion would follow*, never hard-coded onto a list of wafer IDs.
Because the answer is known in advance, the Stage 3 analysis can be **validated**:
a commonality query is only trustworthy if it re-finds the planted culprit
without being told where it is — which it does (see
[Analysis and results](#analysis-and-results-stage-3)). Real fab data never comes
with an answer key; synthetic data engineered this way does, which makes it the
better substrate for *demonstrating* that the analysis works.

The generation is also built to be **realistic where it counts**: the reference
catalog uses real tool vendors and a coherent process flow, the signal is subtle
enough to require aggregation to detect (not visible wafer-by-wafer), and the
same ~187 affected wafers show a *consistent* fingerprint across three
independent measurements — more defects, lower yield, and a metrology drift — the
way one physical root cause actually manifests.

*A note on exact figures: because per-row variation is randomized, the precise
numbers shift slightly on each reseed. All values quoted below are from one
representative run; the **shape** of every result (which group is worse, by
roughly how much) is stable across seeds.*

---

## The schema (Stage 1)

Twelve tables in five dependency layers — reference catalogs, production
hierarchy, equipment detail, event/fact tables, and leaf detail — wired together
by 13 foreign keys that enforce full referential integrity.

| Layer | Tables | Role |
|---|---|---|
| **Reference / lookup** | `tools`, `process_steps`, `defect_types`, `bin_codes` | Controlled vocabulary: the equipment, the process flow, defect classification, and test bins |
| **Production hierarchy** | `lots`, `wafers` | A lot is a batch of ~25 wafers on one product/node; each wafer traces to its lot. Product and technology node live here so yield can be sliced by them |
| **Equipment detail** | `chambers` | A tool can hold many chambers. Modeled separately because **the chamber, not the tool, is usually the true root cause** — a tool can look healthy while one chamber runs bad |
| **Event / fact** | `process_runs`, `defect_inspections`, `bin_results` | `process_runs` is the central fact table — one row per (wafer, step, tool, chamber, time). It is what makes commonality analysis possible. Inspections and die-level bin results are the other two event streams |
| **Leaf detail** | `metrology_measurements`, `defects` | The finest grain: individual metrology readings (CD, overlay, film thickness) per run, and individual classified defects per inspection |

### Schema design decisions

Each of these is the kind of choice a reviewer reading the DDL looks for:

- **Surrogate + natural keys on every table.** Every table has an auto-generated
  `INT IDENTITY` primary key *and* a `UNIQUE` constraint on its real-world
  business key (`tool_code`, `lot_number`, `wafer_scribe`). The surrogate gives
  clean, stable joins; the natural key guarantees the same real-world entity is
  never entered twice.

- **Composite natural keys where identity is relative to a parent.** A chamber
  "A" is not globally unique — nearly every multi-chamber tool has one — so
  `chambers` is unique on `(tool_id, chamber_code)`, not `chamber_code` alone.
  The same pattern recurs on `(lot_id, slot_no)` for wafers and
  `(wafer_id, die_x, die_y)` for die results.

- **Constraints encode domain rules, not just structure.** `CHECK` constraints
  reject a wafer slot outside 1–25 (a physical cassette holds 25), a negative
  defect count, and inconsistent spec limits. These make invalid data
  *impossible to insert*, which is stronger than validating in application code.

- **Referential integrity is the point, not a formality.** The 13 foreign keys
  are what make the commonality join trustworthy: because the database never
  allowed a wafer to point at a non-existent lot or a run at a non-existent
  chamber, every join in Stage 3 walks links that are guaranteed to be real.

**Schema summary:** 12 tables · 13 foreign keys · verified against
`sys.tables` / `sys.foreign_keys` on build.

---

## The seed data (Stage 2)

The database is populated in dependency order — parents before children, the same
order the tables were built — so every foreign key finds its target. The
reference catalogs are hand-written for realism; the high-volume transactional
data is **generated with set-based T-SQL**.

| Table | Rows | How |
|---|---|---|
| `tools` / `process_steps` / `defect_types` / `bin_codes` | 13 / 10 / 8 / 8 | Hand-written reference data (real vendors, a coherent 10-step flow) |
| `chambers` | 14 | `INSERT … SELECT`, looking up each parent tool's generated ID by business key |
| `lots` / `wafers` | 60 / 1,500 | Generated: 60 lots × 25 slots, product/node assigned deterministically by formula |
| `process_runs` | 15,000 | Generated: 1,500 wafers × 10 steps, each assigned an appropriate tool/chamber by round-robin |
| `defect_inspections` / `defects` | 1,500 / ≈6,300 | Generated: one inspection per wafer, expanded into individual classified defects |
| `bin_results` | 216,000 | Generated: 1,500 wafers × 144 dies (12×12), each sorted into a pass/fail bin |
| `metrology_measurements` | 6,000 | Generated: CD + overlay per metrology run, film thickness per deposition run |

### Generation techniques

- **Recursive CTEs for number series.** Row generation needs a sequence of
  integers (1…N). `GENERATE_SERIES` was the first choice but is not exposed on
  this SQL Server build, so a **recursive CTE** is used instead — pure standard
  T-SQL that works on any version regardless of compatibility level. (See
  [Honest engineering notes](#honest-engineering-notes).)

- **A reusable tally (numbers) table.** Expanding a count into rows — "this wafer
  has 5 defects" → 5 rows, "this wafer has 144 dies" → 144 rows — is done by
  joining a permanent `dbo.numbers` table and keeping `n <= count`. This is the
  standard set-based alternative to loops/cursors, built once and reused for
  defects, dies, and measurements.

- **Round-robin assignment via modulo.** Wafers are dealt evenly across tools and
  chambers with `wafer_id % (option count)` — the same principle as dealing cards
  in a cycle. The result is a near-perfectly even distribution (each of the 8
  etch chambers lands within ±1 of 375 runs), which matters: the bad chamber must
  look *ordinary* in the run history, because a real fab's logs don't know in
  advance which chamber is bad.

- **Set-based randomness.** Per-row variation uses
  `ABS(CHECKSUM(NEWID())) % k`, the standard T-SQL idiom for a random integer per
  row. Metrology readings sum two uniform draws to approximate a bell-shaped
  distribution, so the SPC control charts in Stage 3 read like real process data
  rather than uniform noise.

### The planted signal

The whole dataset is built around one engineered root cause: **`ETCH-02` chamber
`C`.** Roughly 187 of the 1,500 wafers pass through it (at both etch steps), and
those wafers carry a consistent but *subtle* fingerprint across three independent
measurements:

| Signal | Affected wafers (`ETCH-02/C`) | All other wafers | Where it's planted |
|---|---|---|---|
| Avg defects per wafer | ≈ 6.2 | ≈ 4.0 | `defect_inspections` (Stage 2.5) |
| Avg die yield | ≈ 84 % | ≈ 90 % | `bin_results` (Stage 2.6) |
| Avg CD (critical dimension) | ≈ 46.0 nm | ≈ 45.0 nm | `metrology_measurements` (Stage 2.7) |

Two design properties make this a genuine analysis problem rather than a rigged
reveal:

- **It is subtle, not obvious.** In every case the affected and unaffected groups
  *overlap*: a noisy good-chamber wafer can out-yield a lucky bad-chamber one.
  The effect exists only in the group **mean**, across all ~187 wafers —
  invisible wafer-by-wafer, detectable only by aggregation. That is exactly what
  a real yield excursion looks like, and what makes Stage 3's job non-trivial.

- **It is isolated and physically coherent.** The metrology drift appears in
  **CD only** — overlay and film thickness stay centered across both groups —
  which points at the etch chamber specifically rather than a systemic problem.
  And the defect types the bad chamber over-produces (particles, flakes) are the
  physically correct signature of a contaminated etch chamber. One root cause
  produces a coherent set of consequences — more defects, of the right type,
  depressing yield, with an isolated CD drift — rather than four unrelated
  anomalies.

---

## Analysis and results (Stage 3)

The analysis layer is the payoff, and it is built as a **progression**: each
query narrows the field, and only the last one names the culprit — the way a real
root-cause investigation actually unfolds. Two reusable views defined first
(`v_wafer_yield`, `v_wafer_defects`) give a single, DRY definition of "yield" and
"defect load" that every query below builds on.

**Throughout, the planted answer (`ETCH-02/C`) is never named in a filter until
the confirmation step — the analysis has to *find* it.**

### 1. Yield analysis — rule out product and node, flag the suspect tool

Die yield is sliced by lot, product, technology node, and tool (die-weighted:
`SUM(pass_dies) / SUM(total_dies)` per group, not an average of per-wafer
percentages).

- **Product and node are flat.** SoC-A17 89.48 %, GPU-B20 89.48 %, MEM-C10
  89.38 %; nodes 3nm/5nm/7nm land at 89.48 / 89.48 / 89.38. A ~0.1-point spread
  is noise. This is a **useful negative result**: the loss is *not*
  product-specific and *not* node-specific — ruled out before any equipment is
  examined.
- **One tool trails its peers.** By tool, `ETCH-02` sits at **88.09 %**, alone at
  the bottom, ~1.4 points below the other etchers and every non-etch tool
  (~88.6–89.5 %). This correctly points at ETCH-02 — but it *cannot yet name the
  chamber*, because ETCH-02's average blends its three chambers (A and B healthy,
  C bad), diluting the signal. That dilution is the tell that the problem is
  sub-tool.

### 2. Defect Pareto — read the failure mode from the defect mix

Defect types are ranked biggest-first with a running cumulative % (a windowed
`SUM() OVER (ORDER BY … ROWS UNBOUNDED PRECEDING)`).

- **Overall Pareto:** Particle leads at 24.6 % of all defects; the top three
  types (Particle, Bridge, Open) account for **54.5 %**, the top five for 77 %.
  The cumulative column closes at exactly 100.00 % — a built-in correctness
  check on the running total.
- **The mix is where the signal shows.** Split by group, the bad chamber does not
  just make *more* defects — it makes *different* ones. **Particle + Flake are
  ≈72 % of `ETCH-02/C`'s defects vs ≈24 % for every other wafer** (Particle 45.9
  vs 19.9 %; Flake 26.2 vs 4.1 %). Particles and flakes are the physical
  signature of a *contaminated etch chamber* (wall buildup, flaking), so the
  defect mix names the failure *mechanism* — contamination — before commonality
  analysis is even run.

### 3. SPC control charts — a sustained shift a point-check cannot catch

Control limits are set at mean ± 3σ for CD, overlay, and film thickness, computed
both overall and per-tool.

- **Zero individual points breach ±3σ** on any metric — and that is the correct,
  honest result. The planted CD drift (~1 nm) is *smaller* than the natural CD
  spread (σ ≈ 1.30 nm), so no single reading looks alarming. A subtle sustained
  shift is invisible to a point-outside-limits rule.
- **The group mean is the detector.** `ETCH-02/C`'s mean CD (45.98 nm) sits
  **0.65σ above** the overall center line (45.13 nm), while all other wafers sit
  at 45.01 nm. A two-thirds-sigma shift *sustained across a whole group* is a
  strong SPC signal even though no point is individually out of control — the
  concrete reason fabs pair ±3σ limits with run rules ("N consecutive points on
  one side of center").
- **Drift follows the wafers, not the instrument.** Grouping CD by the
  *measuring* tool surfaces only the metrology tools (CD-SEM, overlay tool), not
  ETCH-02 — because the drift is carried by the wafers' process history, not the
  tool that measured them. This is precisely *why* the next step joins back
  through `process_runs` to the **processing** chamber.

### 4. Commonality analysis — name the chamber (the headline)

Each wafer's yield is joined through `process_runs` to every chamber it passed
through, grouped by chamber, and ranked worst-first. **The query is not told about
`ETCH-02/C`; it rediscovers it.**

- **`ETCH-02/C` ranks #1 (worst), alone.** Its wafers average **84.08 %** yield.
  The next-worst chamber is already up at 88.56 % — a 4.5-point gap from #1 to
  #2 — and every other chamber, *including ETCH-02's own siblings A (90.05 %) and
  B (90.12 %)*, sits in the healthy ~90 % band. The isolation is the proof: it is
  **not the tool, it is chamber C specifically.**
- **Statistical confirmation:** `ETCH-02/C` at 84.08 % (187 wafers) vs all other
  etch chambers at 90.21 % (1,313 wafers) — a ~6.1-point separation in the means.
  The ranges overlap (bad reaches 90.97 %, others dip to 82.64 %), confirming the
  signal is honestly subtle per-wafer, yet the group means are decisively apart.

### 5. Defect-to-yield correlation — close the loop

Bucketing wafers by defect load shows yield **falling monotonically** as defects
rise: 0–3 defects → 90.04 %, 4–6 → 89.60 %, 7–9 → 84.22 %. Defects don't merely
co-occur with the bad chamber; they *track* yield loss.

The whole investigation then collapses into one summary grid:

| Group | Avg defects | Avg yield | Particle + Flake share |
|---|---|---|---|
| **`ETCH-02/C` (bad)** | 6.16 | 84.08 % | 72.0 % |
| All others | 3.95 | 90.21 % | 24.1 % |

One root cause, every arrow pointing the same way — more defects, of the
contamination type, depressing yield.

### The through-line

The signal was **invisible per-wafer** (overlapping ranges), **invisible to
product/node analysis** (flat), only **partially visible by tool** (ETCH-02
flagged but diluted), readable as a **shifted defect mix** (contamination),
present as a **0.65σ CD group-mean shift** no ±3σ check catches, and **invisible
to by-measuring-tool SPC** — yet it was **named unambiguously the moment wafers
were grouped by the chamber they shared.** That progression is the demonstration:
simpler analyses narrow the field; commonality analysis — enabled by the
`process_runs` fact table designed in Stage 1 — delivers the culprit.

---

## Honest engineering notes

Kept here rather than scrubbed out, because how a problem was diagnosed is itself
evidence of engineering judgment.

- **`GENERATE_SERIES` is a compatibility-level *and* build-availability trap.**
  The function requires database compatibility level ≥ 160, so the first fix was
  `ALTER DATABASE … SET COMPATIBILITY_LEVEL = 160`. It still failed — because on
  this particular SQL Server build the function is not exposed even at level 160.
  The distinction is worth stating precisely: **the server version, the database
  compatibility level, and a given build's exposed feature set are three
  different things.** The resolution was to stop depending on the function
  entirely and generate number series with recursive CTEs, which are portable
  across every version. Portability chosen over a newer convenience.

- **A point-check misses a subtle shift — by design.** The SPC stage returns
  *zero* points outside ±3σ, which is easy to misread as "no signal." It is the
  opposite: the planted shift is deliberately smaller than one sigma, so the
  correct detector is a group-mean comparison, not an individual-point rule. The
  analysis reports both and explains why the point-check is blind here — the same
  reason real fabs run Western-Electric-style run rules alongside limit checks.

- **Data-quality cross-checks are built into the schema and verified.** The
  schema stores each inspection's reported `defect_count` *and* the individual
  defect rows, specifically so the two can be reconciled: `SUM(defect_count)`
  must equal `COUNT(*)` over the `defects` table. After generation the two match
  exactly, which proves the count-to-rows expansion produced neither orphans nor
  duplicates. The die grid is checked the same way — every one of the 1,500
  wafers has exactly 144 dies, no more, no fewer.

- **Never hard-code a generated ID.** Because primary keys are `IDENTITY`-assigned
  and land in non-obvious order (wafer #2 is not slot 2 of lot 1 — it's slot 1 of
  lot 2), every child row looks up its parent by *business key*, never by a
  literal ID. This is the pattern that keeps the seed scripts correct even if IDs
  come out in a different order on a rebuild.

- **A single whole-stage verification script per stage.** Each stage ends with a
  re-runnable health check — Stage 1's confirms all 12 tables and 13 foreign keys
  against system metadata; Stage 2's confirms every row count *and* re-proves the
  planted signal in all three places it lands. Validating your own work in code,
  rather than trusting that a script "ran fine," is treated as part of the
  deliverable.

---

## The bridge to the ML project

`bin_results` is the deliberate handoff point between this project and its
companion ML project. Each row is one die: `(wafer_id, die_x, die_y,
bin_code_id)`. Aggregated per wafer, that is a spatial pass/fail map — precisely
the input format the
[Wafer Map Defect Pattern Classification](https://github.com/arijit-m/Wafer-map-defect-classification)
pipeline consumes to classify the *shape* of the failing region (Center, Donut,
Edge-Ring, Scratch, …) and map it to a likely process mechanism.

So the two projects form one pipeline: **this database is the system of record
that produces die-level test data; the ML project is the downstream spatial
analytics on top of it.** The edge-weighted, chamber-correlated failure structure
planted here in Stage 2.6 is what gives the downstream wafer maps real spatial
signal to work with.

---

## Methodology principles

- **Referential integrity first.** The schema is fully constrained before any
  data is loaded, so no analysis ever runs against a broken link.
- **Define it once.** "Yield" and "defect load" are defined a single time as
  views and reused by every analysis query, rather than re-derived per query.
- **Rule out before you rule in.** The analysis eliminates product and node
  before examining equipment, and distinguishes a tool-level shadow from the
  chamber-level root cause — negative results treated as results.
- **Choose the detector to match the signal.** A subtle sustained shift is
  surfaced with a group-mean comparison, not an individual-point control check;
  the analysis states *why* the point-check is blind rather than hiding the zero.
- **Verify against ground truth, not the editor.** System catalog views
  (`sys.tables`, `sys.foreign_keys`) are the source of truth for what exists,
  over any tooling cache. Every stage is confirmed against them.
- **Set-based, not procedural.** Generation, count-expansion, and analysis use
  joins, CTEs, window functions, and a tally table rather than loops or cursors.
- **Subtle signal, honestly labeled.** The planted excursion is small enough to
  require real analysis to find, and the synthetic nature of the data is stated
  up front rather than implied away.
- **Reproducibility.** Each stage is a standalone, re-runnable `.sql` file with a
  fixed run order; a whole-stage verification script confirms the result of each.

---

## Repository structure

```
.
├── sql/
│   ├── 00_verify_schema.sql              # whole-schema health check (12 tables, 13 FKs)
│   ├── 01_schema/                        # Stage 1: CREATE TABLE scripts, in dependency order
│   │   ├── 01_1_lookup_tables.sql        #   reference catalogs (no FKs)
│   │   ├── 01_2_lots_wafers.sql          #   production hierarchy (first FK)
│   │   ├── 01_3_chambers.sql             #   chambers under tools
│   │   ├── 01_4_event_tables.sql         #   process_runs, defect_inspections, bin_results
│   │   └── 01_5_detail_tables.sql        #   metrology_measurements, defects
│   ├── 02_seed_data/                     # Stage 2: seed data, in dependency order
│   │   ├── 02_1_lookups.sql              #   hand-written reference data
│   │   ├── 02_2_chambers.sql             #   look-up-parent-ID pattern
│   │   ├── 02_3_lots_wafers.sql          #   generated: 60 lots, 1,500 wafers
│   │   ├── 02_4_process_runs.sql         #   generated: 15,000 runs (bad chamber planted here)
│   │   ├── 02_5a_numbers.sql             #   reusable tally table
│   │   ├── 02_5b_defects.sql             #   generated: inspections + defects (signal)
│   │   ├── 02_6_bin_results.sql          #   generated: 216,000 dies (yield signal)
│   │   ├── 02_7_metrology.sql            #   generated: CD/overlay/film-thickness (CD drift)
│   │   └── 02_verify_seed.sql            #   whole-stage seed verification
│   └── 03_analysis_queries/              # Stage 3: analysis layer
│       ├── 03_1_foundation_views.sql          # v_wafer_yield, v_wafer_defects (reusable)
│       ├── 03_2_yield_analysis.sql            # yield by lot / product / node / tool
│       ├── 03_3_defect_pareto.sql             # ranked Pareto + defect-mix contrast
│       ├── 03_4_spc_control.sql               # ±3σ control limits + group-mean shift
│       ├── 03_5_commonality.sql               # commonality analysis — rediscovers ETCH-02/C
│       └── 03_6_defect_yield_correlation.sql  # defect load vs yield, full fingerprint
└── README.md
```

---

## Tech stack

Microsoft SQL Server 2025 (Express) · T-SQL · SQL Server Management Studio (SSMS)
· set-based generation (recursive CTEs, tally table, `CHECKSUM(NEWID())`
randomness, round-robin modulo assignment) · analytical SQL (views, CTEs, window
functions, `RANK()`, `STDEV()` for SPC) · schema and data verification against
system catalog views.

---

## Roadmap

- [x] **Stage 1** — 12-table schema: CREATE scripts in dependency order, surrogate
      + natural keys, CHECK/UNIQUE/FK constraints, whole-schema verification
      (12 tables, 13 foreign keys)
- [x] **Stage 2** — Seed data: hand-written reference catalogs, then large-scale
      set-based generation (60 lots → 1,500 wafers → 15,000 runs → 216,000 dies),
      with a subtle, physically-coherent equipment excursion planted at `ETCH-02/C`
      and verified across defects, yield, and metrology
- [x] **Stage 3** — Analysis layer: reusable yield/defect views, then yield
      analysis, defect Pareto with defect-mix contrast, SPC control charts,
      commonality analysis that re-identifies `ETCH-02/C` from the data alone, and
      defect-to-yield correlation closing the loop
- [ ] **Stage 4** — GitHub packaging: schema/ER diagram, query-result screenshots,
      and cross-links to the WM-811K ML project

---

*Author's note: I come to this from a process/fabrication background
(nanomaterials, nanofabrication, lithography, thin-film and defect metrology).
The schema and the analysis are framed the way a yield engineer would use them —
the goal throughout is not "a database that stores fab data" but "a database whose
queries point an investigation at the specific tool or chamber to go audit."*
