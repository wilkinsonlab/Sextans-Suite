# EJP/ERDERA: Shipped (SHACL) vs. Declared (documentation) — Drift Report

**Purpose:** Before moving on to the HealthDCAT-AP transition analysis, this establishes a shared starting point between you and your colleague: where does the metadata model we actually **ship** (the SHACL shapes in `ERDERA_Base/Schemas/`) diverge from what our own documentation **declares** it to be (`EJPRD v1 Metadata Model vs HealthDCAT-AP v7(EJP_to_HealthDCAT_R7).csv`, columns 1–5, rows 1–39)? Both sides describe the same EJP/ERDERA project — this is a documentation-drift audit, not a comparison between two different schemas.

- **Declared** = what the CSV documentation says the EJP/ERDERA model is (columns 1–5: source class, property/CURIE, label, ShEx cardinality, range). This documentation predates recent SHACL changes and is, in places, out of date.
- **Shipped** = what `ERDERA_Base/Schemas/*.shacl` actually enforces today, read together with the schema-inheritance wiring in `do_erdera_configuration.rb`.

Full row-by-row detail is in the companion file `EJP_ERDERA_Shipped_vs_Declared_comparison.csv` in this same folder.

---

## 1. Inheritance model (this is shipped correctly; the docs don't reflect it)

`do_erdera_configuration.rb` sets `parents: [Resource]` explicitly only for the three schemas created directly by that script — Biobank, Patient Registry, and Guideline. It does not (and should not) set a Resource parent for Distribution.

`dcat:Distribution` is not a subclass of `dcat:Resource` in DCAT/DCAT3 — only `dcat:Catalog`, `dcat:Dataset`, and `dcat:DataService` are. The shipped `distribution.shacl` reflects this correctly: it defines exactly four properties of its own (`dcat:accessURL`, `dct:format`, `dct:rights`, `dcat:byteSize`) and nothing else. The declared documentation, however, lists Distribution-level `dct:title`, `dct:description`, `dct:license`, `dct:hasVersion`, and `dct:publisher` as if Distribution inherited them from Resource — it doesn't, and shipped code is right not to enforce them there. **The documentation is stale on this point, not the implementation.**

Classes that *do* inherit Resource's properties in shipped code (directly or via the FDP base schema hierarchy): Dataset, DataService, Biobank, Patient Registry, Guideline, Catalog.

**Resource-level properties actually shipped** (apply to all of the above, folded into every comparison row below):

| Property | Shipped cardinality | Notes |
|---|---|---|
| dct:title | 1..1 | mandatory, exactly one |
| dct:description | 1..1 | mandatory, exactly one (code comment: "updated to mandatory") |
| dcat:landingPage | 0..1 | optional |
| dcat:theme | 1..* | mandatory, at least one |
| dcat:keyword | 1..* | mandatory, at least one |
| foaf:logo | 0..1 | optional |
| dcat:version | 0..1 | optional |
| dct:identifier | 0..1 | optional |
| dct:language | 1..1 | mandatory, exactly one |
| dct:license | 1..1 | mandatory, exactly one |
| dct:accessRights | 0..1 | optional |
| dct:publisher → OrgShape | 1..1 | mandatory, exactly one |
| dcat:contactPoint → AgentShape | 1..1 | mandatory, exactly one |
| odrl:hasPolicy | 0..1 | optional |
| dct:issued / dct:modified | 0..1 each | optional |

`OrgShape` (the `dct:publisher` target) additionally requires `foaf:name` (1..1), `dct:description` (1..1), and — notably — `dcat:landingPage` (1..1, **mandatory**). None of these sub-requirements appear in the declared documentation.

---

## 2. Summary of findings (36 declared rows checked against shipped code)

| Category | Count |
|---|---|
| MATCH — declared and shipped agree | 15 |
| Doc is stale — shipped is **stricter** than declared | 6 |
| Doc is stale — shipped is **looser** than declared | 4 |
| Doc is stale — predicate renamed in shipped code | 4 |
| Doc is stale — property declared but never shipped (or removed) | 6 |
| Doc is stale — assumes Resource inheritance Distribution correctly does not have | 5 |

(Some rows fall into more than one category, e.g. a predicate rename *and* a cardinality change.)

### 2a. Shipped is stricter than declared

The dominant pattern, recurring across Dataset, Organisation, and DataService:

| Class | Property | Declared | Shipped |
|---|---|---|---|
| dcat:Dataset | dct:description | 0..* | **1..1** |
| dcat:Dataset | dcat:keyword | 0..* | **1..*** |
| foaf:Organisation | dct:description | 0..* | **1..1** |
| dcat:DataService | dct:description | 0..* | **1..1** |

The shipped `sh:minCount 1` on `dct:description` (code comment: `# updated to mandatory`) was a deliberate hardening at some point after the documentation was last written — it's a real, intentional change, but the docs never caught up. Worth noting: this also happens to exceed HealthDCAT-AP R7's own requirement (`1..*`), which is good news for the upcoming transition, but the docs should say so explicitly rather than describe the old, looser rule.

### 2b. Shipped is looser than declared (opposite direction — flag for review)

| Class | Property | Declared | Shipped |
|---|---|---|---|
| dcat:DataService | dcat:endpointURL | **1** (mandatory) | 0..1 (optional) |
| dcat:DataService | dcat:servesDataset | **1** (mandatory) | 0..1 (`sh:minCount 0` explicit) |
| dcat:Dataset / Distribution / DataService | dct:hasVersion → dcat:version | **1** (mandatory) | 0..1 (optional) |

Unlike §2a, it's not obvious these were deliberate relaxations — they could equally be a drift or an oversight when the shapes were last edited. Worth confirming with whoever last touched `data-service.shacl` before assuming either the doc or the code is "right."

### 2c. Predicate renamed in shipped code (doc still shows the old name)

| Class | Declared predicate | Shipped predicate | Cardinality also changed? |
|---|---|---|---|
| Dataset/Distribution/DataService | `dct:hasVersion` | `dcat:version` | Yes — tightened 0..1 → 1 going from shipped to declared, i.e. shipped is looser (DCAT2→DCAT3 migration; conveniently this also matches where HealthDCAT-AP R7 is headed) |
| foaf:Organisation | `dct:title` | `foaf:name` | No (1..1 both) |

### 2d. Declared but never shipped (or shipped and later removed)

| Class | Declared property | Declared cardinality |
|---|---|---|
| dcat:Dataset | `sio:SIO_000001` (Related EJP resource) | 1 |
| foaf:Organisation | `dct:spatial` (location) | 0..* |
| foaf:Organisation | `foaf:page` (closest shipped analogue: mandatory `dcat:landingPage`, different predicate/semantics) | 1 |
| dcat:Distribution | `dcat:downloadURL` | choice with accessURL |
| dcat:Distribution | `dcat:mediaType` (referenced only as a UI list column, not SHACL-validated) | 0..* |
| dcat:Distribution | `dct:isPartOf` | 0..* |
| dcat:DataService | `dct:conformsTo` (exists only in a commented-out block of `resource.shacl` — considered, then shelved) | 1 |

### 2e. Distribution's accessURL/downloadURL: shipped behavior changed, doc wasn't updated

The declared docs describe `accessURL`/`downloadURL` as **alternatives** ("choice with"). Shipped `distribution.shacl` drops `downloadURL` entirely and makes `accessURL` unconditionally mandatory (`sh:minCount 1`, unbounded max). This is a real behavior change from what's documented, not just a cardinality tweak — confirm it's intended before writing it up as current behavior.

---

## 3. Not in scope here, but relevant context

Several `dataset.shacl` additions (`healthdcatap:healthCategory`, `dct:spatial`, `dpv:hasPersonalData`, `healthdcatap:healthTheme`, each with a fixed `sh:hasValue`) already implement HealthDCAT-AP R7 "ADD" rows that appear later in the same source CSV (beyond row 39). These aren't declared anywhere in the EJP-RD-labeled columns being audited here, but they're good forward coverage to flag once you get to the HealthDCAT-AP transition work.

---

## 4. Recommendations — before the HealthDCAT-AP transition work starts

1. **Update the declared documentation** for every MATCH-adjacent stale row (§2a, §2c, §2e) — these are cases where shipped code is intentional and correct, and the doc just needs to catch up.
2. **Confirm intent** on §2b (the "shipped is looser" cases) with whoever last edited `data-service.shacl` — decide whether to tighten the shipped code to match the doc, or update the doc to match a deliberate relaxation.
3. **Resolve the §2d list** — for each declared-but-unshipped property, decide: was it deliberately dropped (update the doc to remove it) or should it still be implemented (add it to the shape)? `sio:SIO_000001` and `dct:conformsTo` look like the two most likely candidates for "still wanted."
4. **Add an explicit code comment** on `distribution.shacl` noting that it intentionally does not inherit Resource (per DCAT/DCAT3), so a future maintainer doesn't "fix" this by adding a Resource parent.
5. Once the doc is brought current, re-run this same audit against the HealthDCAT-AP R7 columns — you'll then be diffing shipped-and-accurate-doc against the actual target, instead of doing it through a stale intermediate.

---

*Report generated 2026-09-24 by comparing `EJPRD v1 Metadata Model vs HealthDCAT-AP v7(EJP_to_HealthDCAT_R7).csv` (rows 1–39, cols 1–5, "Declared") against `ERDERA_Base/Schemas/*.shacl` and `ERDERA_Base/do_erdera_configuration.rb` ("Shipped").*
