# Targeting in Upsilon Battle — Investigation Notes

Compiled 2026-09-03, updated same day with a follow-up round. Basis for the upcoming round of
targeting unit tests (range, zone, triggers/hooks) and for a serialization-hazard pass on the same
surface.

**⚠️ Headline finding from the follow-up round**: AoE skills have a confirmed **production bug**,
not just a documentation gap — the live webhook path that feeds the frontend drops all but one
target's damage/heal feedback for any multi-target skill, due to a version-keyed dedup cache
collision. See §7.5.

## 0. How this document came to be, and how to read it

**Round 1** dispatched eight investigation angles as background sub-agents. Four completed and left
full, code-grounded notes (§§1–3, 5). A fifth (buff/debuff) was killed by an infrastructure rate
limit but had already written a substantially complete report before dying — it is included in full
(§5) and should be treated as reliable, though it never got a self-review pass. Three angles (ATD
feedback, zone-geometry deep-dive, wire/serialization) were lost entirely to the same rate-limit
wave with zero output. Rather than relaunch agents immediately, that first pass compiled everything
gathered so far and did targeted direct verification (live ATD tool queries, direct reads of the
pattern/zone parser code, direct reads of the frontend targeting code) to close as much of those
three gaps as was reasonable to do inline.

**Round 2** (this update) dispatched four fresh, narrowly-scoped agents at exactly the voids Round 1
identified: obstacle/cell-type handling in targeting (§11), elevation/Z-axis mechanics (§12),
line-of-sight (§13), and the AoE multi-target wire representation (folded into §7, since it was a
sub-question of the wire section). All four completed cleanly and are integrated in full below —
this closes essentially every gap Round 1 flagged, and surfaces one confirmed production bug (§7.5)
and one confirmed skill-balance inconsistency (§13, "balance corollary") along the way.

**Every section below is marked with a status banner** so you know what's fully investigated, what's
been directly-but-not-exhaustively verified, and what (if anything) is still open.

Per the original brief: issues under `/issues` are leads, not ground truth. Every issue cited below
was cross-checked against current code by either a sub-agent or this session directly; where a
claim turned out to be stale (ISS-142's seed-data description), that's flagged explicitly rather
than repeated as fact.

**Status legend:** 🟢 fully investigated · 🟡 partially verified, real gaps remain · 🔴 not
investigated, only secondary/incidental coverage.

---

## 1. Range & distance 🟢

Source: `notes_core_targeting.md` (agent "Skill targeting resolution core"), cross-checked directly
in this session.

- `property.Range` is an `IntCounterProperty` — a **band**, not a scalar: `GetValue()` (min) and
  `GetMaxValue()` (max). Default when absent: `value=1, max=1` (`def/skill.go` `DefaultRange()`).
- Skill range check (`skill_validation.go:99`, **2D Manhattan, Z ignored**):
  ```go
  dist := tools.Abs(user.Position.X-target.X) + tools.Abs(user.Position.Y-target.Y)
  if dist > rng.GetMaxValue() || dist < rng.GetValue() {
      return false, msg.ReplyWithError("Target is not in range", "skill.target.range")
  }
  ```
  Both bounds inclusive. No rounding issues (all-int Manhattan).
- Basic-attack range check (`attack_checks.go:80-84`) is a **different formula**:
  ```go
  distance2D := tools.Abs(ent.Position.X-target.Position.X) + tools.Abs(ent.Position.Y-target.Position.Y)
  zDiff := tools.Abs(ent.Position.Z - target.Position.Z)
  // effectiveRange < distance2D || zDiff > (effectiveRange+1)
  ```
  Attacks add a **separate vertical constraint** (Δz ≤ range+1, documented in
  `rule_combat_range_validation.atom.md` as "reflecting their ability to jump/reach, default jump
  is 2"); skills have **no vertical constraint at all**. This is a genuine, undocumented semantic
  divergence between the two combat paths, not just duplicated code.
- A shared, correct 3D-Manhattan helper already exists (`position.Position.Distance()` in
  `upsilonmapdata`, and `tools.Distance`/`tools.Distance3D`) but **neither targeting path calls
  it** — both hand-roll their own inline formula independently.
- Line-of-sight (`TargetingMechanics: Anywhere | "Line of Sight"`) is read but **both branches are
  no-ops** server-side (`skill_validation.go:118-121`, bare comment `// only okay.`) — LOS is a
  defined, selectable enum value with **zero server-side enforcement**. (The frontend *does*
  enforce a client-side LOS check on its range preview — see §7 — which the server does not
  validate; a client could preview a LOS-restricted highlight that the server would still accept
  through an obstacle.)

### Range-check rejection table (skill path)
| Condition | Error | Key |
|---|---|---|
| `dist > MaxRange \|\| dist < MinRange` | "Target is not in range" | `skill.target.range` |
| zone pattern fully off-grid after range passes | "Target is not in grid" | `skill.target.outofgrid` |

### Magic numbers in the range/attack path
`attack.go:74` `tools.Max(1,...)` min-damage floor · `attack_checks.go:84` hardcoded `+1` reach
allowance · `def/skill.go:130` default Range hardcoded to `[1,1]` when absent.

---

## 2. Zone / AoE geometry 🟢 (Round 1 partial + Round 2 closed the remaining gaps — see §11/§12)

Primary source: `notes_core_targeting.md`, supplemented by a direct read of
`upsilontypes/property/def/skill.go` (`ZoneProperty.Set`) and
`upsilonmapdata/grid/position/pattern/pattern.go` in Round 1, and now fully closed by the dedicated
obstacle (§11) and elevation (§12) investigations in Round 2 — read those two sections alongside
this one for the complete picture; §2.4 below is Round 1's original gap list, kept for the record,
with each item now resolved and cross-referenced.

### 2.1 Shape grammar (string-parsed, `ZoneProperty.Set`, `def/skill.go:188-228`)
```go
switch name {
case "Single":     bh.ZonePattern = pattern.Single()
case "Neighbours": bh.ZonePattern = pattern.Neighbours()
case "Circle":     bh.ZonePattern = pattern.Circle(parseN())
case "Square":     n := parseN(); bh.ZonePattern = pattern.Square(n, n, n)
case "Line":       bh.ZonePattern = pattern.Line(parseN())
default:           panic(fmt.Sprintf("ZoneProperty.Set: unknown zone pattern %q ...", s))
}
```
- Accepted wire forms: `"Single"`, `"Neighbours"`, `"Circle:N"`, `"Square:N"`, `"Line:N"` (N a
  positive int).
- `parseN()` panics (not error-returns) on a missing `:N` suffix, or on `N` that fails
  `strconv.Atoi` or is `<= 0`. This runs inside `Property.Set`, reachable directly from
  admin-authored skill-template JSON (`AdminSkillTemplateRequest`) via `setSkillPropValue` — a
  malformed Zone string is a crash-early panic on that request handler, not a structured
  `400`-style validation error. Worth an explicit unit/negative test per malformed form:
  `"Circle"` (no `:N`), `"Circle:0"`, `"Circle:-1"`, `"Circle:abc"`, `"Hexagon:3"`.
- `Square:N` can only ever be a **symmetric cube** — `pattern.Square(width,length,height)` supports
  asymmetric extents, but the string grammar has no way to reach that; the wire vocabulary is
  strictly narrower than the underlying `Pattern` primitive.

### 2.2 Concrete shapes (3D, `upsilonmapdata/grid/position/pattern/pattern.go`), exact point counts computed directly this session
| Pattern | Formula | Points | Shape |
|---|---|---|---|
| `Single()` | origin only | 1 | — |
| `Circle(1)` | Euclidean `x²+y²+z²≤1` | **7** | origin + 6 face-adjacent (3D "plus"/octahedron cross — diagonals excluded even though `Δ=√2>1` isn't literally checked, it falls out of the inequality) |
| `Circle(2)` | Euclidean `≤4` | **33** | — |
| `Circle(3)` | Euclidean `≤9` | **123** | — |
| `Square(1,1,1)` = `Neighbours()` | solid cube, half-extent 1 | **27** | full 3×3×3 cube incl. origin — **not** a diamond/cross despite the name |
| `Square(2,2,2)` | solid cube, half-extent 2 | **125** | full 5×5×5 cube |
| `Line(N)` | `{(0,0,0)…(N-1,0,0)}` | N | **hardcoded to the +X axis only, from origin inclusive** — never rotated toward the caster→target vector |

Key implication for test design: `Circle:N` (AoE containment) is **Euclidean**, while the range gate
that decided "can this skill reach here" is **Manhattan** — a target can be legally in-range by the
Manhattan range check yet its own `Circle:1` AoE only actually reaches the 7-point cross above, not
a Manhattan diamond of the same radius. `Square:N`/`Neighbours` is a solid cube (includes corners at
full Chebyshev distance N, e.g. `Neighbours()` includes `(1,1,1)` at Manhattan distance 3) — a much
larger AoE than "adjacent" intuitively suggests. `Line:N` never aims — a "Line:3" fireball always
draws a line east of the caster regardless of where the target was clicked; this reads as an actual
gap for any AoE skill that's meant to fire *at* something, not a documented design choice (no atom
or comment claims this is intentional).

### 2.3 Anchoring, selection, and team/self filtering
- Zone is centered on **the target tile submitted by the player**, not the caster and not
  re-derived from the target entity's position separately:
  ```go
  selectedZone := ctx.Grid.SelectPositionsByPattern(target, zone.ZonePattern)
  ```
- `SelectPositionsByPattern` (`upsilonmapdata/grid/pathfinding.go`) applies the pattern at that
  origin, then filters to cells that actually exist in the grid (`g.Contains(p)`) — this is the
  entire mechanism behind `skill.target.outofgrid` (an **empty** selection, not a partial one — a
  zone straddling the edge silently loses the off-board cells rather than rejecting the whole cast;
  only a *fully* off-grid pattern origin fails).
- `TargetTypeEntity` applies **no team filter** — every entity in every selected cell is added,
  including the caster itself if the caster's own tile is inside the zone.
- `TargetTypeFriendOnly` also does **not** exclude the caster (same-team check matches the caster
  trivially); `TargetTypeEnemyOnly` structurally can never self-hit (different-team check).
- No AoE falloff by distance from the AoE's own center exists anywhere in
  `effectapplicator.applyDamagingEffect`/`applyHealingEffect` — every hit target in the resolved
  set takes identical computed damage/heal.
- A **separate, near-duplicate 2D pattern library** (`pattern_2d.go`, `Pattern2D`) exists and is
  used exclusively by AI pathfinding/surface-snapping (`SelectPositionsByPattern2D`) — confirmed
  never called from the skill/attack targeting path.

### 2.4 Round 1's original open questions — now resolved (kept for the record)
- ~~Obstacle-cell handling inside `SelectPositionsByPattern`~~ — **Resolved definitively in §11**:
  `SelectPositionsByPattern` has zero cell-type awareness at all (only grid-bounds `Contains`), and
  — more surprisingly — `checkSkillTarget`'s entire `TargetType` switch never reads `Cell.Type`
  either, so a `TargetTypeTile` skill CAN legally be cast directly onto a Water/Obstacle cell today,
  unlike attack and move which both explicitly reject non-Ground/Dirt cells. See §11.3 for the full
  trace and the exact missing-check comparison table.
- ~~No test currently exercises `Circle:N`/`Square:N`/`Line:N`~~ — still true, now doubly confirmed:
  §11.6 independently reconfirms zero AoE-shape tests exist beyond `"Neighbours"`, and §12
  additionally confirms `pattern.Circle`/`Square`/`Line` themselves have **zero unit tests at any
  level** (`pattern_test.go` only tests an unrelated pathfinding helper). The exact point-count
  table above (§2.2) is ready-made assertion data for closing this.
- `Pattern.Contains`/`ContainsAny`/`ContainsAll` — still not traced to a targeting call site; low
  priority, not revisited in Round 2 since neither obstacle nor elevation investigation surfaced a
  live caller.
- **New, Round-2-only finding not anticipated by this list**: Zone/AoE resolution is fully 3D and
  **has no vertical constraint of any kind** — a `Circle:2` AoE can sweep 2 full Z-levels regardless
  of the fact that the range check that positioned it never looked at Z at all. This is the single
  most test-worthy geometry gap in the whole investigation; see §12.3 for the full walkthrough.

---

## 3. TargetType, validation chain & rejection tables 🟢

Source: `notes_core_targeting.md`.

### 3.1 Resolution chain (skill path)
`UseSkill` → `preSkillChecks` (existence/controller/turn/skill-exists/already-acted, **and a full
bypass of all target checks for Passive/Reaction/Counter skills** — no target set is ever computed
for those behaviors) → `checkSkillTarget` (range → zone selection → `TargetType` switch, populates
`targetedTiles`/`targetedEntities`) → `checkSkillCost` (cooldown/HP/MP/SP/Movement) →
`checkReposition` (if applicable) → `applyDirectSkillEffect` →
`effectapplicator.ApplyDirectEffect`.

**Note the order**: target-set resolution happens *before* cost checking. This matters for §8's ATD
drift finding — `mech_skill_validation.atom.md` documents the opposite order.

### 3.2 `def.TargetTypes` enum (6 values, `def/skill.go:247-256`)
```go
TargetTypeEntity, TargetTypeFriendOnly, TargetTypeEnemyOnly,
TargetTypeTile, TargetTypeEntityOrTile, TargetTypeSelf
```
`TargetTypeTile` silently **skips occupied cells** rather than erroring per-cell — only the
aggregate "nothing selected" check can catch a fully-blocked tile-only zone.
`TargetTypeEntityOrTile` (the 6th value) has **zero test coverage anywhere** (confirmed in §9).

### 3.3 Full rejection table
| # | Path | Condition | Error key |
|---|---|---|---|
|1| pre | entity not found | `entity.notfound` |
|2| pre | controller mismatch | `entity.controller.mismatch` |
|3| pre | not entity's turn | `entity.turn.mismatch` |
|4| pre | skill not on entity | `skill.notfound` |
|5| pre | already acted | `entity.alreadyacted` |
| — | pre | Passive/Reaction/Counter | target checks **bypassed entirely** |
|6| target | out of range | `skill.target.range` |
|7| target | zone fully off-grid | `skill.target.outofgrid` |
|8| target | `Self` type, not on own tile | `skill.target.self` |
|9| target | resolved target set empty | `skill.target.none` |
|10| cost | on cooldown | `skill.cooldown` |
|11-14| cost | insufficient HP/MP/SP/Movement | `skill.cost.{hp,mp,sp,mvt}` |
|15-18| reposition | no direction / off-grid / bad terrain / blocked | `skill.reposition.*` |

Basic-attack path has its own 10-entry table (A1–A10, see `notes_core_targeting.md` §5) including a
**duplicated** `entity.attack.noentity` check present both in `preAttackChecks` and again inline in
`Attack()` — dead-but-harmless redundancy in a synchronous, non-interleaved call path.

### 3.4 Dead entities in the target set
No explicit "is alive" filter exists in `checkSkillTarget` — it's structurally impossible for a
dead entity to appear because `RemoveEntity` deletes it from both `gs.Entities` and the grid cell
the instant HP≤0 is detected. This is implicit, not a tested invariant — see §9 gap #7
(dead-entity-targeting is untested) and note the interaction with §4's finding that `RemoveEntity`
never fires `OnDeath`.

---

## 4. Trigger / hook system: current state and groundwork for onHit/onDodge/etc. 🟢

Source: `notes_triggers.md` (agent "Trigger/hook system state").

### 4.1 The five declared trigger types — two are dead code
```go
TriggerOnEnter, TriggerOnExit, TriggerOnStep, TriggerOnTurn, TriggerOnDeath
```
All positional/cell-based. **`OnStep` and `OnDeath` are declared, validated, and documented, but
never dispatched anywhere in production code**:
- `Move()` fires `OnExit` (origin) and `OnEnter` (destination) only — it does not loop over
  intermediate path cells, so `OnStep` never fires despite `req.Path` containing every traversed
  tile.
- `RemoveEntity()` never calls `ProcessPositionalEffects` at all, so `OnDeath` never fires when an
  entity dies.

So the framing "we currently only have positional hooks like onStep" is not quite accurate — OnStep
is *defined* but *not wired*. Only OnEnter, OnExit, and OnTurn are actually live, from exactly 4
call sites: `move.go:48` (OnExit), `move.go:67` (OnEnter), `beginingofturn.go:53` (OnTurn),
`reposition.go:171` (OnEnter only — reposition/dash explicitly skips intermediate tiles and OnExit,
a documented fly-over divergence from `Move()`).

### 4.2 Dispatch mechanism
Single function, `ProcessPositionalEffects` → `processSinglePositionalEffect` (plain string
comparison against every effect on the cell, not a switch/registry) → `applyPositionalEffect` →
`effectapplicator.ApplyDirectEffect`. No registry, no observer list, no event bus. Fully synchronous
Go calls, no goroutines (consistent with CODING_RULE §2's ban on ad-hoc goroutines/tickers).

### 4.3 Target model — a poor precedent for onHit
Positional effects have **no target list**: the affected set is hardcoded to
`[]entity.Entity{target}` where `target` is whichever entity the calling rule function happens to be
processing (mover, or turn-holder). There is no multi-target positional trigger and no separate
"owner" vs "triggering entity" role split beyond `effect.CasterID` (used only for
cleanup/credit-attribution, never read by `applyPositionalEffect` itself). **OnHit inherently needs
two independently-owned roles** (attacker's own "on hit inflicted" vs defender's own "on hit
received") — a shape the positional-effect model has never had to support, since a cell trigger's
"affected set = 1, hardcoded to the acting entity" collapses attacker/defender into one slot. This
exact gap is ISS-149's design question 1: *no precedent anywhere in the codebase for an
entity-attached triggered effect.*

### 4.4 Where a combat-outcome hook would actually insert — exact line numbers
**Melee (`attack.go`) has no hit/accuracy/dodge test at all — it always hits.** Candidate insertion
points, in order:
1. `attack.go:74` — `computedDamage := tools.Max(1, ...)` — **this line IS the entire hit
   resolution**; there is no gate to hook before it exists yet.
2. `attack.go:124-127` — HP write (`foeHP.SetI(...)`, `AdjustPropertyCValue`) — candidate
   OnHit(inflicted/received) point.
3. `attack.go:142-145` — `if foeHP.I() <= 0 { RemoveEntity }` — candidate OnKill/OnDeath point,
   duplicated independently (not shared code) with the skill tunnel's own death check at
   `skill.go:118-198`.

**Skill/effect tunnel (`effectapplicator.go:86-96`) is the only hit test in the engine today**:
```go
accuracy := ent.GetPropertyI(property.Accuracy).I()
for _, target := range targetedEntities {
    dodge := target.GetPropertyI(property.Dodge).I()   // target's dodge, not caster's — ISS-145 regression guard
    if tools.RandomInt(0, 100) < accuracy-dodge {
        damageTargets = append(damageTargets, target)
    } else {
        // else branch: logs "dodged" — but this fires on ANY miss, not just an evasive dodge
    }
}
```
**This single comparison conflates "attacker missed" and "defender dodged" into one Boolean roll —
there is no way today to distinguish OnMiss from OnDodge**, which is exactly ISS-149's blocker #1.
`Parry` is a fully-declared, constructible skill property with **zero read sites in combat**
(ISS-148) — its intended semantics per the user (captured in ISS-148, 2026-08-30) are "an off
chance to take a hit but suffer no damage beyond the floor of 1... effects that trigger on hit would
still apply under a parry" — i.e. parry is a *hit* that still fires OnHit, not a dodge variant.

`BeginingOfTurn` (`beginingofturn.go`) already fires `OnTurn` post-stun-resolution — the closest
existing precedent for an entity-attached `OnTurnStart` hook, should that be wanted later.

### 4.5 Re-entrancy — none exists, and none is guarded against
Grepped for `depth`/`MaxRecursion`/`EventQueue`/`Publish(`/`Subscribe(` across the engine: zero
matches. Every dispatch is a plain, directly-recursive-capable synchronous call stack with **no
circuit breaker**. This is not currently exploitable only because no existing effect type calls back
into trigger dispatch (positional effects only ever call `ApplyDirectEffect`, which deals
damage/heal but never re-enters `Move`/trigger dispatch). **An OnHit hook that itself deals damage
(a thorns/reflect effect) would call straight back into the same attack-resolution path it fired
from, with no depth limit.** ISS-149 design question 4 calls this out explicitly as *mandatory, not
optional* design work — any implementation plan needs a recursion guard before a damage-dealing
OnHit hook ships.

### 4.6 Write-isolation constraint on any future hook
The `rule_entity_property_write_isolation` atom's invariant (base-state delta writes only, never a
composed-value write-back) is transversal — it explicitly already covers "any future buff source"
and any read-modify-write on a buffable property, so a new hook type gets no carve-out. Any onHit
implementation that mutates state (a thorns counter-hit, a triggered debuff) must use the
`AdjustPropertyCValue`/`RepsertPropertyValue` base-delta pattern like every other write in the
engine. This is orthogonal to §4.5's re-entrancy concern — one governs *how* a write is shaped, the
other *whether* a write can trigger another write transitively.

### 4.7 Tracked issues (already scoped, both Open, both independently corroborated by this investigation)
- **ISS-149** (`combat_outcome_trigger_family`, 2026-08-30) — 6 explicit open design questions:
  attachment model, a `Perspective` field (self/attacker/defender), fire order when both sides carry
  a trigger, the mandatory recursion guard, scope (skill-tunnel-only vs melee too), and how to split
  the conflated accuracy/dodge roll. Recommended sequencing: settle design questions → split the hit
  test → decide melee's hit-test scope → introduce the entity-attached trigger model with
  Perspective + recursion guard → implement Parry on top.
- **ISS-148** (`parry_declared_but_unimplemented`) — blocked on ISS-149; Parry's damage floor
  (`tools.Max(1,...)`, same floor already used in `attack.go:74`) can be wired once the on-hit
  family exists.
- **ISS-154** (Regen Aura passive zone) / **ISS-155** (Shield Bash `OnReceivedHit` reaction) — both
  blocked on the *same* missing trigger vocabulary, plus a **separate**, already-confirmed gap: the
  Passive/Reaction/Counter behavior bypass in `preSkillChecks` (§3.1) means these skill behaviors
  never get a target set computed for them today at all — a second blocker independent of the
  trigger-family design, worth keeping visible so it isn't rediscovered as a surprise once ISS-149
  lands.

---

## 5. Buff/debuff effects on targeting 🟢 (agent run interrupted by rate limit after finishing its findings — content below is complete and code-grounded, but never got a final self-review pass)

Source: `notes_buffs_targeting.md` (agent "Buff/debuff effects on targeting"), cross-checked in this
session directly against the `mechanic_item_buff_application` and `mechanic_buff_attribution_accessor`
ATD atoms (§8), which independently corroborate several of this section's findings.

### 5.1 Two disjoint "effect" concepts — don't conflate them
- **(A) `effectapplicator`** — direct/instantaneous, writes straight to base state
  (`AdjustPropertyCValue`/`RepsertPropertyValue`), handles HP/Shield/Poison/Stun only, **never
  touches AttackRange/Movement/Zone**.
- **(B) `entity.Buffs` / `property.TemporaryProperties`** — the actual duration-based buff system,
  created via `RegisterBuff`, called from **exactly 2 production sites**, both in
  `upsilonapi/bridge`: `bridge_start.go:243` (`applyItemAsBuff`) and `bridge_resurrect.go:205`
  (`restoreEntityBuffs`). **No skill/effect code path ever calls `RegisterBuff`.** The only buff
  source today is equipped items, always `Forever: true`. This is confirmed independently by the
  `mechanic_item_buff_application` atom (§8.4), which describes exactly this item-projection flow
  and nothing else.

### 5.2 The exact buffable whitelist (8 keys)
`Attack, Defense, AttackRange, Movement, JumpHeight, HP, SP, MP` — pinned by
`TestBuffability_ExactlyEightEntityAttributesAreItemGrantable`
(`upsilontypes/property/def/registry_buffability_test.go`). Explicitly excluded: Shield/Poison/Stun
(ISS-147 regression guard) and flags like TeamID/IsDying/HasMoved ("letting an item grant them would
be an exploit," per the agent's reading of the registry comments).

**Zone is `ScopeSkill`-only in the registry — structurally not buffable.** `getBasePropertyOrDefault`
panics if asked to resolve a non-entity-scoped key on an Entity. A raw `ZoneProperty` *is* stuffed
into `buff.Properties[Zone]` at `bridge_start.go:222-226`, but only for **display purposes** — it
bypasses `RegisterBuff`'s lack of write validation, is read back only by `output.go:convertBuffToItem`
for API display, and is **never consumed by any targeting code**.

### 5.3 The crux finding: base vs. effective reads diverge between the two combat paths
- **Basic attack** (`attack_checks.go:74-95`) reads `ent.GetPropertyI(property.AttackRange)` — the
  **effective/buffed** accessor. Correctly wired.
- **Skill cast range/zone** (`skill_validation.go:91-109`) reads `sk.GetProperty(property.Range)`
  off the **Skill** type, which has **no buff composition mechanism whatsoever** — `Skill` has no
  `Buffs` field, and `Skill.GetProperty` only scans its own Targeting/Costs/Effect maps.
- **Net effect: an item-granted `+3 AttackRange` buff changes basic-attack legality but has zero
  effect on any skill's cast range or AoE zone.** This is a structural gap (a missing mechanism),
  not a misuse of the same key — and **no ATD atom reconciles this inconsistency** (confirmed in
  §8: neither `mechanic_item_buff_application` nor `rule_entity_property_write_isolation` mentions
  it, and no atom governs "which targeting-relevant keys does an entity buff actually reach").
- AI behavior code (`baseline.go` + 5 `micro/*.go` files) all correctly reads effective/buffed
  `AttackRange` — consistent with the attack path, meaning **AI decisions and basic-attack legality
  agree with each other, and skill-cast legality is the outlier.**

### 5.4 Stacking, duration, and a confirmed-dead tick
- Stacking is `Composition`-enum-driven: `CompositionAdd` (Int/IntCounter — pure unbounded
  addition, no cap/floor) for the 6 numeric buffable keys, `CompositionAnd` for bools,
  `CompositionReplace` for Zone (moot — never consumed). No floor/cap exists in the composition
  layer itself for a negative AttackRange; the only protection is incidental
  (`tools.Max(attackerRange.I(), weaponRange.I())` at the one consuming call site in the attack
  path).
- **`Entity.BuffTickDown()` is dead code in production** — `EndOfTurn` ticks Poison, restores
  Movement, resets HasActed/HasMoved, and calls `SkillCooldownTickDown()`, but never
  `BuffTickDown()`. Only exercised in isolation by `entity_test.go:TestBuffGetRemovedAfterTime`.
  This is currently inert only because the sole real buff source (items) is always `Forever:true` —
  it would matter immediately for any future duration-limited skill-cast buff. **This finding is
  independently confirmed by the `mechanic_buff_attribution_accessor` atom itself**, which states
  outright: "Buff-scoped `Duration` can neither tick down (`Entity.BuffTickDown` is never called in
  production...) nor reach a client" — i.e. the ATD documentation already knows about and
  self-reports this gap.
- No mid-resolution buff-expiry race exists — targeting resolution is synchronous/single-threaded
  (no goroutines), so a buff cannot tick down mid-check.

### 5.5 Serialization
HP/MaxHP/Movement/MaxMovement/Attack/Defense all serialize as **effective** (post-buff) values in
`output.go`. **`AttackRange` is not serialized to the client at all** — zero hits anywhere in
`output.go`/`upsilonapi/api/*.go` — so a client cannot learn an entity's (buffed or base) attack
range from the entity payload, buffed or not. Raw `Buffs` are separately serialized via
`extractEntityBuffsAndItems` as delta blocks, never composed into an "effective X" field. The
`mechanic_buff_attribution_accessor` atom independently confirms the adjacent gap: "the wire `Buff`
DTO carries no `duration` field."

### 5.6 Zone/area growth from a buff — confirmed absent at every layer
No registry scope, no read path, no test. What building it would require (per the agent's analysis,
not yet designed): either (a) give `Skill` its own buff-composition mechanism (currently zero
capability), or (b) add a new `ScopeEntity` numeric key (e.g. `AreaBonus`) composed onto
`zone.ZonePattern` before `SelectPositionsByPattern` is called in `checkSkillTarget` — and note
`ZoneProperty.ApplyBuff` today is whole-pattern-**replace**, not additive, so true "radius growth"
needs either a new `Composition` kind or a separate numeric key plus a new "effective pattern"
resolver. `pattern.Pattern` (`[]position.Position`) has **no arithmetic composition method** at all
today — this is new mechanism, not a config change.

### 5.7 Summary table — the crux verdict
| Check | Reads buffed value? | Why |
|---|---|---|
| Basic attack range (`attack_checks.go:75`) | **Yes** | effective accessor, correctly wired |
| Skill cast range (`skill_validation.go:95`) | **No** | different key, no Skill buff mechanism |
| Skill AoE/zone (`skill_validation.go:94,111`) | **No** | Zone is Skill-scope-only; entity Zone buffs are display-only and never consulted |
| AI targeting decisions | **Yes** | consistent with the attack path |

---

## 6. Data model & property-key space 🟢

Source: `notes_data_model.md` (agent "Targeting data model and property keys").

### 6.1 Targeting-vocabulary keys (Skill scope)
| Key | Kind | Composition | Default |
|---|---|---|---|
| `Behavior` | String | None | `Direct` |
| `Range` | IntCounter | Add | value=1, max=1 |
| `Zone` | Zone | Replace | `Single()` |
| `TargetNumber` | Int | Add | 0 ("all in zone") |
| `Accuracy` | Int | Add | 100 |
| `Dodge` | Int | Add | 0 |
| `Parry` | Int | Add | 0 |
| `TargetType` | String | None | `Entity` |
| `TargetingMechanics` | String | None | `Anywhere` |
| `RepositionSubject` | String | None | `Self` |
| `RepositionDistance` | Int | Add | 0 |
| `TriggerType` | String | None | `OnEnter` |
| `RemoveOnTrigger` | Bool | And | true |
| `TriggerCount` | Int | Add | 1 (0=unlimited) |

`Accuracy`/`Dodge` are dual-scope (`Skill|Entity`); `Parry` is Skill-only. `property.SkillTargetingProperties`
is the canonical map key set, separate from `SkillEffectProperties`/`SkillCostProperties`.

### 6.2 Typed, not a generic bag
At the `property.Property` interface level, everything is typed: `entity.Properties
map[string]property.Property`, `Skill.Targeting/Costs map[string]property.Property`,
`effect.Effect.Properties []property.Property` — concrete structs (`DefaultIntProperty`,
`DefaultStringProperty`, `ZoneProperty`, ...) implementing `Property`, keyed by name. The *generic*
bag lives one layer out at the wire boundary (`api.PropertyMap = map[string]PropertyDTO`) — see §7.

### 6.3 Bad-cast surfaces
`DefaultIntProperty.Set(p interface{})` does an unchecked `d.value = p.(int)` — panics on a bad
cast (crash-early, consistent with CODING_RULE §3), guarded at the DTO-ingestion call site
(`setSkillPropValue` type-asserts first) but not guarded for any other caller of `.Set(interface{})`.
`ZoneProperty.Set` similarly only checks `p.(string)`, then panics downstream on parse failure —
covered in §2.1.

---

## 7. Targeting across the wire 🟢 (Round 1 partial + Round 2 fully resolved the central open question — see §7.5)

Primary source: `notes_data_model.md` §5 (serialization), supplemented by direct reads in Round 1 of
`upsilonbattleui/src/composables/useActionDispatch.js` and
`upsilonbattle/battlearena/ruler/gamestate/gamestate.go`, and closed out in Round 2 by a dedicated
trace of the AoE multi-target wire representation (§7.5) — the single biggest finding of this whole
document.

### 7.1 The wire DTO layer (`upsilonapi/api/{input,output}.go`)
```go
type PropertyDTO struct {
    Value  *int     `json:"value,omitempty"`
    FValue *float64 `json:"fvalue,omitempty"`
    Max    *int     `json:"max,omitempty"`
    BValue *bool    `json:"bvalue,omitempty"`
    SValue *string  `json:"svalue,omitempty"`
}
```
`convertProperty` switches on the property's runtime `Get()` type: `int`→`Value`,
`float64`→`FValue`, `bool`→`BValue`, `string`→`SValue`, unknown→stringify into `SValue` (silent
fallback). `IntCounterProperty` additionally populates `Max`. **Enums (`TargetType`,
`TargetingMechanics`, `TriggerType`, `Behavior`, `RepositionSubject`) are `DefaultStringProperty` →
serialize under `.svalue`, as strings, not ints** — correct on the server side, but see §7.3 for
what the client actually reads.

`property.Property`/`entity.Entity` are **never directly `json.Marshal`'d** — confirmed via grep for
`MarshalJSON`/`json:"` in `upsilontypes/property`/`upsilontypes/entity` (zero hits). The DTO layer
in `upsilonapi/api` does the crossing exclusively.

Zone/Effect are **special-cased out of the generic PropertyMap**: `convertPropertyMap` filters out
`property.Effect`/`property.Zone` before generic conversion. Zone is instead lifted to a **top-level**
`EquippedSkill.Zone *string` field, populated with only `zp.PatternType` (the raw string, e.g.
`"Circle:3"`) — **the resolved offset list is never serialized**; the receiver must re-derive
offsets by re-parsing the pattern string client-side (which the client does not currently do — see
§7.3).

### 7.2 `upsilonserializer` — a version tag, not a codec
`upsilonserializer/gamestate_version.go` contains only `CurrentSerializerVersion = 1`, stamped into
`BoardState.SerializerVersion` and checked on resurrection requests. **No binary/versioned property
encoding exists anywhere** — confirmed via grep for `gob\.`/`GobEncode` across `upsilontypes` and
`upsilonserializer` (zero hits outside unrelated JSON tags). There is no gamestate snapshot codec to
audit beyond this version guard; the entire wire representation of a gamestate is the same
`upsilonapi/api` JSON DTO layer as everything else. `gamestate.GameState` itself (confirmed directly
this session, `gamestate.go:15-34`) carries `Grid`, `Entities`, `Controllers`, `Version`/`TurnIndex`/
`ActionIndex`, `PositionalEffects map[position.Position][]uuid.UUID`, `Effects
map[uuid.UUID]effect.Effect` — none of this Go struct is itself the wire shape; `output.go` builds
a separate DTO tree from it per-request.

### 7.3 Confirmed, directly-verified client/server divergence (not just cited from an issue)
Read `useActionDispatch.js` directly in this session:
```js
const range = skill.targeting?.Range?.value ?? 1;              // line 145 — CORRECT: Range is IntCounter, serializes under .value
...
const targetType = skill.targeting?.TargetType?.value ?? 'Entity';   // line 174 — WRONG: TargetType is String, serializes under .svalue, so this is ALWAYS undefined
```
This **directly confirms ISS-158's core claim**: `TargetType` is read from the wrong DTO field and
silently falls back to the hardcoded `'Entity'` default on every skill, regardless of its real
`TargetType`. `Range` reads correctly (unlike what a shallow reading of the issue might suggest —
`IntCounterProperty` genuinely does serialize under `.value`/`.max`, so this one field is fine). No
read of `skill.targeting.Zone` exists anywhere in this file — consistent with §7.1's finding that
Zone never lives at that path on the wire in the first place.

The client's own range-preview math (`calculateSkillRange`, lines 140-160) **independently
reimplements 2D Manhattan** and matches the server formula exactly:
```js
if (Math.abs(dx) + Math.abs(dy) > range) continue;
```
— but it *also* unconditionally excludes `(dx,dy)=(0,0)` (never highlights the caster's own tile)
and applies a client-side `hasLOS(...)` line-of-sight filter and an obstacle filter that the
**server does not enforce at all** for skill targeting (§1: `TargetingMechanicsLOS` is a server-side
no-op; full LOS investigation, including the surprising finding that this client filter is applied
**unconditionally to every skill** regardless of its declared `TargetingMechanics`, is in §13). Two
concrete, directly-confirmed divergences worth turning into tests:
1. A skill with `MinRange=0` (self-targetable band) can legally target the caster's own tile
   server-side, but the client's range-preview loop can never highlight it — a UX-only bug, not a
   security one, but worth a note if any future skill wants an explicit self-in-band case.
2. The client enforces LOS on its preview; the server enforces none. A target behind an obstacle
   that the client would never let you click could, if reached by any other path (a saved/replayed
   action, a future non-UI client), still be accepted server-side — this is the actual security-
   relevant edge of ISS-158's broader "the two layers don't agree" finding, and is worth an explicit
   server-side regression test (client trust should never be the enforcement boundary — consistent
   with CODING_RULE §4's "no defaulting to save the day" / strict contract stance).

### 7.4 What Round 1 left open, and how Round 2 closed it
Round 1 flagged three open questions here: the exact `ArenaActionRequest`/`ActionFeedback`
multi-target shape, the obstacle-in-AoE wire behavior, and a client/server LOS-algorithm comparison.
The first is now fully resolved (§7.5, below — and it's worse than "open," it's broken). The second
is now answered from the internal-resolution side in §11 (obstacles cannot produce a phantom
wire entry today, because `ActionResult` is always built from a real `targetedEntities` member — see
§7.5's own §6 for the narrow wire-layer confirmation of this). The third is closed in §13 (there is
no server LOS implementation to compare against; the client algorithm is fully documented there).

### 7.5 AoE multi-target wire representation — the central open question, now resolved: **a confirmed production bug**

Source: dedicated Round 2 agent, cross-checking `communication.md` against
`upsilonbattle/battlearena/ruler/rulermethods/rulermethods.go`, `upsilonbattle/battlearena/ruler/rules/skill.go`,
`upsilonbattle/battlearena/ruler/ruler_actions.go`, and the full `upsilonapi` conversion/webhook layer.

**There are two independent wire paths for an AoE skill's result, and they diverge sharply:**

1. **Synchronous HTTP reply** to `POST /arena/{id}/action` (`upsilonapi/handler/handler.go:70-99`,
   `mapActionReplyToApi`) — **correct**. It converts the engine's full
   `rulermethods.ControllerUseSkillReply.Results []rulermethods.ActionResult` (one entry per hit
   entity, built by the two `append` loops in `skill.go`'s `applyDirectSkillEffect`, lines 118-198)
   into a same-length `[]api.ActionResult` and returns `gin.H{"attacker": ..., "results": results}`.
   For a 2-target AoE this genuinely is a 2-element array. (Note this reply is a bare `gin.H`, not
   an `api.ActionFeedback` — no `type`/`actor_id` fields — so it doesn't literally match the
   `ActionFeedback` schema `communication.md` documents, even though the underlying data is right.)
2. **Asynchronous webhook** (`ArenaEvent` → `POST /api/webhook/upsilon`, built in
   `upsilonapi/bridge/http_controller.go`'s `forwardToWebhook`) — **this is the path that actually
   feeds the hub → SSE → the shipped frontend's `gameState.action` field** — and it is broken for
   multi-target skills in two compounding ways.

**`communication.md` (lines 636-651) documents the contract correctly**: `ActionFeedback.results` is
explicitly typed `Array<ActionResult>`, and `ActionFeedback.target_id` is annotated
`(Legacy/Primary target)` — the doc authors clearly intended `results` to be the authoritative
multi-target field. The engine's internal reply type matches this exactly
(`ControllerUseSkillReply.Results []ActionResult`, confirmed structurally: both the damage loop
(`for _, res := range dds`) and the heal/status loop append into the same slice). **The contract and
the engine agree. The bug is entirely in `upsilonapi`'s two different conversions of that same data.**

**Why the webhook path breaks, exactly** — `upsilonbattle/battlearena/ruler/ruler_actions.go`'s
`controllerUseSkill`:
```go
reply, damaged, affected := rules.UseSkill(r.GameState, ctx.Msg, req)
ctx.Reply(reply)                                    // full N-entry Results — but nobody reads this reply over the notification path

for _, d := range damaged {
    foectrl.NotifyActor(message.Create(nil, d, nil))   // one ControllerAttacked broadcast PER damaged entity
}
for _, d := range affected {
    targetctrl.NotifyActor(message.Create(nil, d, nil))  // one ControllerSkillUsed broadcast PER affected entity
}
```
So an N-target AoE fires N separate `NotifyActor` calls, each independently reaching
`forwardToWebhook`. Two things go wrong from there:

1. **Each webhook is hardcoded to a single-element `Results` slice.** `http_controller.go:147-174`,
   both the `ControllerAttacked` and `ControllerSkillUsed` branches build `Results: []api.ActionResult{{...one entry from d.Entity...}}` — there's no loop; structurally it can never carry more
   than one target even if called once per cast.
2. **A version-keyed dedup cache then drops all but (at most) one of the N webhooks anyway.** All N
   `ControllerAttacked` structs from one skill cast share the *same* `Version` (incremented once,
   before either loop, in `applyDirectSkillEffect`). `forwardToWebhook` gates sending through
   `Get().TrySendWebhook(hc.MatchID, version, eventName)` (`bridge_action.go:77-95`), keyed on
   `(matchID, version, eventType)` — since every per-target notification from this cast shares that
   exact key, **only the first one to arrive wins; the rest silently return early and never send a
   webhook at all.** For a 3-target AoE nova: 3 `NotifyActor` calls fire, but at most 1 webhook
   carrying any `results` data is actually delivered. The other 2 targets' damage shows up only in
   the *next* `BoardState` HP snapshot, with zero attribution back to the skill that caused it.

A correctly-shaped converter, `bridge.HTTPController.mapResults` (`http_controller.go:106-123`),
already exists with exactly the right signature to fix this — **it has zero call sites anywhere in
the repo.** It reads like scaffolding for a fix that was started and never wired in.

**Credits have the same aggregation problem, compounding it further.** `effectapplicator.go`'s
`applyDamagingEffect`/`applyHealingEffect` compute one **lump-sum** `CreditAward` per skill use
(`Source: "damage"`, amount summed across every hit target — not one award per target/kill), and
`skill.go` then copies that *same* aggregate credits slice onto **every** `ActionResult` in the
results array. A client naively summing `results[i].credits[j].amount` across the array would
double- or triple-count. This holds on both wire paths, since both originate from the same
`res.CreditAwards`.

**The shipped frontend corroborates the gap rather than working around it.** `upsilonbattleui`
never reads `.results` anywhere (grepped the whole `src` tree). The one consumer of action feedback,
`TacticalActionReport.vue`, has **no `'skill'` branch at all** in its type switch (only
`attack`/`move`/`pass` — any skill use, AoE or not, renders nothing there), and even its `'attack'`
branch reads flat fields (`action.damage`, `action.prev_hp`, `action.new_hp`) that don't exist on
the current `ActionFeedback` shape — those numbers only live nested at `results[0].damage` etc.,
suggesting this component predates the `results` array being introduced and was never updated. The
`ThreeGrid.vue` "hit flash" heuristic is similarly singular (`targetedEntityId`, not a list) and
matches via an HP-value heuristic against the same nonexistent flat field. `gameState.action` is
sourced directly from the webhook-relayed SSE event (`useBattleChannel.js`), confirming the frontend
is wired to the broken path, never the correct synchronous one.

| Wire path | Trigger | N-target support? | Reachable by shipped UI? |
|---|---|---|---|
| Sync `/action` HTTP reply | `POST /arena/{id}/action` | **Yes** — full N-entry array | No — frontend never reads this response body |
| Webhook `ActionFeedback` | `forwardToWebhook` → SSE | **No** — hardcoded 1-element slice, and version-dedup typically drops even that to ≤1 of N notifications | **Yes** — this is what the UI actually consumes, via nonexistent flat fields |
| `HTTPController.mapResults` | (unused) | Would be correct if called | Dead code, zero call sites |

**Bottom line**: today, a client cannot reliably learn about more than one target of an AoE skill —
not because the data doesn't exist (it's computed correctly, twice), but because the one wire path
that reaches the frontend both structurally truncates it to one entry *and* usually drops even that
one entry to a race in a dedup cache. This is worth filing as its own issue independent of this
document (out of scope to file here per the read-only investigation brief, but flagged prominently
given severity) — it directly blocks writing any meaningful AoE-result *serialization* test until
either `mapResults` is wired in or the dedup key is scoped per-target rather than per-version. Worth
noting: `upsilonapi/docs/api_go_action_feedback.atom.md` already carries a "KNOWN ISSUES" section
that anticipates part of this — this investigation sharpens and confirms it with a full code trace
rather than discovering it fresh (see §8.9).

---

## 8. ATD documentation feedback 🟢 (Round 1: done directly via live `atd` MCP tool queries in lieu of the failed documentalist agent. Round 2 added two more confirmed drifts — §8.9.)

### 8.1 Project health snapshot (`atd_stats`, `upsilonbattle` project)
84 atoms total, 55 MECHANIC / 11 RULE / 9 MODULE / 4 ENTITY / 2 REQUIREMENT / 1 each
CONTRACT/VISION/SPECIFICATION. 45 STABLE / 33 DRAFT / 4 REVIEW / 1 SPECIFIED / 1 OBSOLETE.
Coverage ratio ≈0.49, 13 orphaned-STABLE atoms (none in the targeting family — see §8.6). CONTRACT
(`contract_battle_contract`) and VISION (`vision_battle_vision`) are both present, both STABLE,
satisfying the one-per-project rule.

### 8.2 What exists for targeting, and its status
| Atom | Status | Layer | Covers |
|---|---|---|---|
| `mech_skill_validation` | **STABLE** | IMPLEMENTATION | Full skill precondition list incl. range/target-type, as an ordered checklist |
| `rule_combat_range_validation` | **STABLE** | ARCHITECTURE | Basic-attack range formula only (correctly scoped — does not claim to cover skills) |
| `rule_entity_property_write_isolation` | REVIEW | ARCHITECTURE | Base-vs-composed read/write invariant, transversal — the strongest atom in this family |
| `mech_trigger_system` | DRAFT | IMPLEMENTATION | Positional trigger semantics (OnEnter/Exit/Step/Turn/Death) |
| `mech_positional_effects` | DRAFT | IMPLEMENTATION | Cell-attached effect storage/lifecycle, incl. a "Zone Entity Pattern" |
| `mechanic_item_buff_application` | DRAFT | IMPLEMENTATION | Item→buff projection at battle init |
| `mechanic_buff_attribution_accessor` | DRAFT | IMPLEMENTATION | Read-only buff-origin accessor (not yet built — file "not yet created" per its own interface section) |
| `module_skill_sandbox` | DRAFT | ARCHITECTURE | The new `battletest` fluent harness — **accurate, no drift found** |
| `mechanic_backstab_detection_algorithm` | (Round 2) | — | Documents an LOS prerequisite for backstab and falsely claims it's tested — see §8.9 |
| `mech_constructed_obstacle` | (Round 2) | — | Documents a "Barrier" obstacle type that "blocks LoS" — see §8.9 |
| `api_go_action_feedback` (upsilonapi) | (Round 2) | — | Already carries a partial "KNOWN ISSUES" note anticipating the AoE-wire bug — see §7.5, §8.9 |

### 8.3 Confirmed drift #1 — `mech_skill_validation`'s documented check order doesn't match code
The atom's numbered RULE list is: 1 existence, 2 turn/controller, 3 action-state, **4-5 cost/
cooldown**, **6 grid boundary**, **7 range**, 8 target-type. Actual code
(`preSkillChecks`/`checkSkillTarget`, confirmed in §3.1) checks **range before grid-boundary**
(range-band comparison runs first; the zone-selection/`outofgrid` check only runs after range
passes) and, more significantly, checks **the entire target set before cost/cooldown**, not after.
This is a real, verifiable order inversion between STABLE documentation and shipped code — worth a
correction pass on this atom regardless of the test-writing effort, since a test author following
the atom's literal ordering would write assertions in the wrong sequence for a "which error fires
first when two conditions are both true" boundary test.

### 8.4 Confirmed drift #2 — `mech_trigger_system` documents functionality that doesn't exist yet
The atom (DRAFT, v2.0) describes, as current mechanic:
- A full **"Movement Trigger Execution"** algorithm ("for each cell in the path... if passing
  through: OnStep triggers fire") — but §4.1 confirmed `Move()` never loops over intermediate path
  cells and OnStep never fires.
- OnDeath firing "when entity dies while in or on this cell" — but §4.1 confirmed `RemoveEntity`
  never calls `ProcessPositionalEffects`.
- A **"Force Stop Triggers"** section (`ForceStopMove`/`ForceEndTurn` properties) with no
  corresponding code found by any agent or this session's greps.
- A **"Trigger Stacking"** ordering guarantee ("First Come First Served... all valid effects fire")
  — plausible given the loop structure, but not independently confirmed against a multi-effect
  test case (none exists — see §9).

This reads as **aspirational documentation presented as current mechanic**, not merely a coverage
gap — a test author trusting this atom at face value would write OnStep/OnDeath/ForceStop tests
against code that silently does nothing. The atom's own `## EXPECTATION` section is also empty (no
content after the header) — a completeness gap independent of the drift.

### 8.5 Confirmed drift #3 — `mech_positional_effects`'s "Zone Entity Pattern" has no producer
The atom documents an "anchor entity" pattern (invisible, `Duration`-based, `WalkThrough=true`) for
multi-cell zone effects like "poisonous fog, healing zone" as a current mechanic. Per ISS-154's
independently-verified finding (a passive zone-aura skill has "no producer mechanism" anywhere in
the codebase) and ISS-153's independently-verified finding (`EntityDuration`/`ExpiresWithCaster` are
fully wired on the *consumer* side but nothing in production ever sets non-default values), this
anchor-entity pattern is **consumer-ready but has never been produced by any code path**. Same
aspirational-documentation shape as §8.4.

### 8.6 What's accurate and well-maintained
`module_skill_sandbox` matches the new `battletest` harness exactly, field-for-field, method-for-
method — no drift. `mechanic_item_buff_application` and `mechanic_buff_attribution_accessor` are
**exemplary** — both explicitly self-report their own known gaps (`BuffTickDown` dead code,
duration not on the wire) rather than presenting aspirational behavior as current, which is exactly
the opposite failure mode from §8.4/§8.5. No STABLE atom in the targeting family shows up in the
orphan-detection pass (`atd_crawl gaps=true`) — every STABLE targeting atom has at least one code
implementation.

### 8.7 Gaps — nothing documents these at all
- **No atom governs whether a targeting check honors buffed vs. base stats.** §5.3's crux finding
  (basic attack reads buffed AttackRange, skill cast range does not) is a real, structural
  inconsistency with no atom anywhere reconciling it or even flagging it as known/deferred. This is
  the single highest-value new atom to write out of this whole investigation, once the team decides
  which behavior is correct.
- **No dedicated atom for skill range/zone geometry** analogous to `rule_combat_range_validation` —
  the 2D-Manhattan-vs-Euclidean-AoE divergence (§2.3), the hardcoded `Line` axis (§2.2), and the
  symmetric-cube-only `Square:N` grammar restriction (§2.1) are all documented only in this
  session's own investigation, nowhere in ATD.
- `RegisterBuff`, `GetBuffsFor`, and the `Buffs` field itself carry **no `@spec-link` at all** —
  confirmed directly from `mechanic_buff_attribution_accessor`'s own "Pre-existing gap, not created
  by this atom" note.
- No atom exists yet for the combat-outcome trigger family (OnHit/OnDodge/OnParry/OnMiss) — correct
  per ATD discipline, since ISS-149's design questions are still open and the standard doesn't want
  atoms written against undecided design; ISS-148/149 are the right interim placeholders. Flagging
  only so this isn't mistaken for an oversight — it's the process working as intended.
- **New from Round 2**: no atom documents that elevation/Z-targeting has three completely
  disconnected rules across Move/Attack/Skill (§12), nor that skill `TargetTypeTile` targeting has
  no cell-type check at all (§11) — both are structural inconsistencies of the same shape as the
  buff/targeting gap above, and both are good candidates for the same kind of reconciling atom once
  the team decides the intended behavior.

### 8.9 Two more confirmed drifts, found by the Round 2 LOS and obstacle agents

**Drift #4 — `mechanic_backstab_detection_algorithm.atom.md` falsely claims LOS is tested.** The
atom documents an explicit LOS prerequisite for backstab bonuses ("the path from the attacker to the
target's back must be clear of opaque obstacles or walls") and states it is "Verified by
`backstab_test.go`." Neither claim survives a direct read: `Entity.IsBackstabbing`
(`upsilontypes/entity/entity.go:126-153`) computes a pure facing-angle test with no obstacle/wall
logic anywhere in it, and `backstab_test.go` only asserts that angle boolean — it never constructs
an obstacle or exercises any LOS path. This is a false "verified" claim on a STABLE-adjacent test
attribution, not just a missing feature — worth a higher-priority correction than a typical DRAFT
coverage gap, since it could mislead someone into skipping backstab-vs-obstacle test coverage on the
belief it already exists.

**Drift #5 — `mech_constructed_obstacle.atom.md` documents a "Barrier" that "blocks LoS" with no
enforcing code.** Line 99: `**Barrier**: HP = 40, WalkThrough = false, blocks LoS`. `WalkThrough`
is a real, enforced mechanism (§11.5); "blocks LoS" is not — there is no LOS enforcement anywhere
server-side to block (§13.1). Same aspirational-attribute pattern as drifts #2/#3 (§8.4/§8.5): a
real game object's documented property list includes a clause with no implementing code.

**Not a drift, but worth relaying**: `upsilonapi/docs/api_go_action_feedback.atom.md` already
carries a "KNOWN ISSUES" section (lines 44-45) that anticipates part of §7.5's AoE-wire finding —
this investigation didn't discover that gap from nothing, it corroborated and substantially sharpened
an existing, already-flagged doc note with a full code trace (the dedup-cache mechanism specifically
was not previously identified, per the agent's read of that atom). Good example of the atom doing
its job — flagging a known gap — even though the gap itself is more severe than the atom's own note
suggests.

### 8.8 What's still not investigated on the ATD side
This session's ATD pass was targeted at the specific atoms this investigation's other sections
surfaced, plus a project-wide stats/orphan/lint sweep. It did **not** do a full semantic
`atd_check --semantic` compliance pass (LLM-graded @spec-link-vs-code compliance) on every targeting
file, nor a full read of every one of the 84 atoms in the project. `atd_lint` was attempted and
returned a bare "linting failed" with no detail — worth re-running standalone (outside this
document's scope) to see if that's a real structural problem or a transient tool issue.

---

## 9. Existing test coverage & harness guide for the new round 🟢

Source: `notes_tests.md` (agent "Existing targeting test coverage"). Suite is fully green (189
tests passed, 15 packages, confirmed via `rtk proxy go test ./...`).

### 9.1 Two harnesses — use the new one
- **Old style** (`package rules`): `makeGameStateForTwo()` family, raw `FakeController`, manual
  property-map surgery (`sk.Targeting[property.PropertyToString(property.Zone)] = zp`). Still what
  most existing targeting tests use.
- **New style** (`battletest` package, `@spec-link [[module_skill_sandbox]]`, ATD-accurate per §8.6):
  fluent `Scenario`/`Actor`/`SkillSpec` builder. **Preferred for the new round.** Verbatim
  signatures, a full worked example, and the house table-driven style (`TestRepositionBlockedLanding`)
  are captured in `notes_tests.md` in full and are directly reusable as templates.
- **Caveat**: `SkillSpec.Zone(patternStr string)` exists in the new harness's builder
  (`builders.go:49`) but is **entirely unexercised by any existing test** — the one AoE test in the
  repo (`aoe_skill_test.go`) still uses the old raw `def.DefaultZone()` approach. Verify
  `SkillSpec.Zone(...)` actually works end-to-end (a trivial smoke test) before basing a large batch
  of new AoE tests on it.

### 9.2 Coverage matrix — highlights (full ~25-row matrix in `notes_tests.md`)
Well covered: out-of-range/out-of-grid rejection, Self/FriendOnly/EnemyOnly targeting (success +
failure), Tile-only occupied-rejection, basic-attack's 10 failure modes, reposition fly-over vs.
landing vs. blocked-landing (table-driven), backstab orientation detection.

**Explicitly uncovered (17 items, direct answer to "what should the new round prioritize")**:
1. Exact boundary range (at-max success as an explicit assertion, not incidental)
2. Min-range enforcement (code path exists, zero tests)
3. Diagonal distance (no test ever differs in both X and Y simultaneously)
4. Zero/negative range
5. Dead-entity targeting
6. Out-of-bounds beyond the positive grid edge, for **skills** specifically (only tested for basic
   attack)
7. AoE overlapping the caster's own tile
8. AoE hitting allies mixed into an enemy-oriented zone
9. AoE shapes other than `"Neighbours"` — **zero tests use `Circle:N`/`Square:N`/`Line:N`** (§2.2's
   exact point counts are ready-made assertions for this)
10. AoE with an empty target set
11. AoE with duplicate/overlapping-cell targets
12. A target dying mid-AoE-resolution (order dependence)
13. `TargetTypeEntityOrTile` — the 6th enum value, completely untested
14. Tile-only targeting **success** case (only the occupied-failure case is tested)
15. Reposition + AoE composition
16. Reposition diagonal paths (all existing cases are axis-aligned)
17. Skill-cost/cooldown-vs-target-check ordering (code order confirmed in §3.1/§8.3, never asserted
    by a dedicated test — this is also the exact ordering the ATD drift in §8.3 got wrong, so a test
    here doubles as the regression guard for that atom fix)

Add from this document's own findings (not in the original agent's list, but now concrete thanks to
§§5, 7): a buffed-AttackRange-does-not-affect-skill-cast-range regression test (locks in §5.3's
current, arguably-wrong behavior so any future fix is a deliberate, visible change), and a
server-does-not-enforce-LOS-even-though-client-does test (§7.3) if LOS enforcement is ever expected
to be symmetric.

### 9.3 Round 2 additions — 8 more concrete, ready-to-write gaps
18. `TargetTypeTile` skill cast directly onto a Water/Obstacle cell — currently **succeeds** with no
    rejection (§11.3); write both a regression test locking in today's behavior and a design
    decision ticket, since this is inconsistent with attack/move's explicit terrain checks.
19. `pattern.Circle`/`Square`/`Line`/`Neighbours` have **zero unit tests at any level** (§12.6,
    confirmed independently by §11.6) — the point-count table in §2.2 is ready-made expected-output
    data; this is the cheapest, highest-value test to add from this entire document.
20. Cross-Z AoE sweep (§12.3's crux scenario: a `Circle:2` AoE centered on a target whose Z the range
    check never validated can still hit an entity 2 Z-levels away) — zero coverage, and the only
    cross-Z test in the whole suite is a single Move rejection case (§12.6).
21. `JumpHeight` boundary case: a step exactly at `Δz == JumpHeight` should succeed — only the
    rejection case (`Δz > JumpHeight`) is currently tested (§12.2).
22. An entity placed on (or an AoE resolving onto) an Obstacle-typed cell — nothing prevents this at
    the grid layer (§11.5) and it's completely unexercised; worth a test asserting the actual
    (currently undefined-by-omission) behavior once decided.
23. AoE multi-target wire result end-to-end: given §7.5's confirmed production bug, a regression test
    at the `upsilonapi` HTTP-handler level asserting the synchronous `/action` reply carries all N
    `results` entries (it does, today) would at least lock in the one wire path that works, and a
    second test on the webhook path documenting today's single-entry/dedup-drop behavior would give
    the eventual fix something to flip from red to green.
24. LOS-gating consistency: a test asserting a skill declared `TargetingMechanics: "Line of Sight"`
    is treated identically to `"Anywhere"` server-side (locks in §13's finding so a future LOS
    implementation is a deliberate, visible change, not a silent behavior shift).
25. Backstab-vs-obstacle: per §8.9's drift #4, `mechanic_backstab_detection_algorithm.atom.md` claims
    an LOS-blocked backstab test exists; it doesn't. Either write the missing test or correct the
    atom's "Verified by" claim — ideally both, with the test written first.

---

## 10. Issues cross-referenced and verified against code

Every issue below was read in full or substantial part and checked against current code (not taken
at face value, per the original brief).

| Issue | Status | Verdict |
|---|---|---|
| ISS-157 (bare-int Range inversion) | claims "Open" | **Actually resolved** — its own "Resolution — settled 2026-09-02" section confirms bare-int Range now resolves to `value=0,max=N`. Structured form unaffected. `Delay`/`Channeling`/`Cooldown`/`Duration` bare-int interpretation explicitly left out of scope/unreviewed. |
| ISS-158 (battleui wire shape mismatch) | Open, Medium | **Confirmed directly** in this session (§7.3) — `TargetType` read bug is real and reproducible from the code as written, not just alleged. |
| ISS-159 (leech tests mis-filed under Targeting) | Open, Low | Mechanical fix only; 9 test call-sites write a Cost property into `Targeting["TargetType"]`, masked because `Skill.GetProperty` cross-scans all three maps. |
| ISS-154 (Regen Aura zone unimplemented) | Open, Medium | Needs a self-centered *moving* `Square:1` zone + `OnTurn` heal-ally trigger; blocked by both the passive-dispatch bypass (§3.1/§4.7) and the zero-producer gap (§8.5). No "moving zone" precedent exists anywhere — all positional effects today are fixed-tile. |
| ISS-155 (Shield Bash `OnReceivedHit`) | Open, Medium | Same passive/reaction dispatch gap; needs the same missing combat-outcome trigger vocabulary as ISS-149. |
| ISS-149 (combat-outcome trigger family) | Open, Medium | Independently re-derived by this investigation's own analysis (§4) — every claim matches. |
| ISS-148 (Parry unimplemented) | Open, Medium | Confirmed zero read sites in combat; blocked on ISS-149. |
| ISS-160 (PoisonTrap DamageScale default) | Open, Medium | `DamageScale` defaults to 100 (not 0) when absent — poison/stun-only effects silently also deal full attack-scaled bonus damage. Confirmed live in `PoisonTrap()` (7 call sites) and `TestRuleSkillEffectPoisonCounter`; no test currently asserts HP after these fire, so the bug is invisible to the suite. Not targeting per se, but directly relevant to any new positional-trigger/AoE test that uses `PoisonTrap`. |
| ISS-079 (grid cell Y-major/width-major) | Open, Medium | Affects `output.go` grid serialization (`cells[x][y]`); several CLI scenarios already assume Y-major. Relevant if any new wire test touches grid serialization directly. |
| ISS-142 (skill-originated attribute buffs unsupported) | Open — **but its seed-data narrative is stale** | Core claim (skills cannot buff attributes; `RegisterBuff` has exactly 2 non-test, item-only callers) independently confirmed true by §5.1. **However**, ISS-142 also describes the seed catalog as malformed (illegal keys `Type`/`Radius`/`MP`/`SP`/`Stat`) — a direct read of the current `upsilonhub/internal/seed/seed.go` in this session shows the seed rows already use the corrected vocabulary (`Zone`/`TargetType`/`MPLeech`/`SPLeech`/`DamageScale`/`Heal`/`RepositionSubject`/`RepositionDistance`/`StunPower`/`StunChance`). **Do not cite ISS-142's seed-data description as current fact** — this is exactly the kind of issue-vs-code drift the brief warned about. |
| ISS-153 (temporary-entity summon/trap, no producer) | Open, Medium | Consumer side (`EntityDuration`/`ExpiresWithCaster`) fully wired; no production code path ever sets non-default values. Missing feature work, not a defect. Directly relevant to §8.5's atom-drift finding. |
| ISS-146 (Shield buff semantics deferred) | Open, Medium | Deliberate deferral — Shield treated as plain resource for buff purposes; its real cap/absorption/overshield semantics are unaddressed. |

Current (verified-fresh) seed skill catalog, for reference when building fixtures that mirror real
production skills:
```go
{fireballID, "Fireball", "Direct", `{"Zone":"Single","Range":3}`, `{"MPLeech":3}`, `{"DamageScale":150}`, "I", 5},
{healID, "Heal", "Direct", `{"Zone":"Single","Range":2}`, `{"MPLeech":4}`, `{"Heal":10}`, "I", 5},
{sprintID, "Sprint", "Direct", `{"TargetType":"Tile","Range":{"value":1,"max":3}}`, `{"SPLeech":2}`, `{"RepositionSubject":"Self","RepositionDistance":3}`, "I", 3},
{lightningStrikeID, "Lightning Strike", "Direct", `{"Zone":"Circle:1","Range":2}`, `{"MPLeech":5}`, `{"DamageScale":170}`, "II", 8},
{shieldBashID, "Shield Bash", "Reaction", `{"Zone":"Single","Range":1}`, `{"SPLeech":3}`, `{"DamageScale":0,"StunPower":15,"StunChance":100}`, "II", 7},
{regenAuraID, "Regen Aura", "Passive", `{"TargetType":"Self","Range":0}`, `{}`, `{"Heal":1}`, "I", 4},
```
Note `Lightning Strike`'s `"Zone":"Circle:1"` is a live production skill using the exact
7-point-cross shape computed in §2.2 — a natural real-world fixture for the first `Circle:N` AoE
test.

**New candidate issues surfaced by Round 2** (not filed — read-only investigation scope — but
flagged since they're real, code-confirmed findings, not speculation): the AoE webhook dedup bug
(§7.5, almost certainly the highest-severity finding in this whole document — it's a live production
bug, not a gap), skill targeting's missing cell-type check allowing `TargetTypeTile` onto
Water/Obstacle cells (§11.3), and the LOS skill-balance inconsistency where `"Line of Sight"`
targeting gets a cost discount for a restriction with zero server-side effect (§13, "balance
corollary"). Worth filing all three via the issue-management workflow when you're ready.

---

## 11. Obstacles & cell-type validation across targeting 🟢

Source: Round 2 dedicated agent, cross-checking `upsilonmapdata/grid/cell/cell.go`,
`upsilonmapdata/grid/pathfinding.go`, `skill_validation.go`, `attack_checks.go`, `move.go`,
`reposition.go`, and the `upsilonapi` wire layer.

### 11.1 "Obstacle" is a `CellType` enum value, not a boolean flag
`upsilonmapdata/grid/cell/cell.go:12-28`:
```go
type CellType int
const (
    Obstacle CellType = 0  // impassable, blocks line-of-sight (doc claim only — see §13)
    Ground   CellType = 1  // walkable, primary combat layer
    Water    CellType = 2  // movement penalties / unique interactions
    Dirt     CellType = 3  // sub-surface layer
    Debug    CellType = 4
    Debug2   CellType = 5
)
```
`Cell` has **no boolean `Obstacle`/`Blocking` field** — `Obstacle` is simply the zero value of
`CellType`, so a bare `Cell{}` literal defaults to "obstacle." `Cell.IsOccupied()` is pure
entity-occupancy (`len(c.EntityIDs) > 0`) — it is repeatedly conflated with "obstacle" throughout
the codebase but is a completely different concept (terrain type vs. who's standing there).

### 11.2 `SelectPositionsByPattern`/`SelectPositionsByPattern2D` never inspect cell type
```go
func (g *Grid) SelectPositionsByPattern(origin position.Position, pat pattern.Pattern) []position.Position {
    res := []position.Position{}
    pos := pat.ApplyInArea(origin, g.Width, g.Length, g.Height)
    for _, p := range pos {
        if g.Contains(p) {          // bare map-membership check — no Type read anywhere
            res = append(res, p)
        }
    }
    return res
}
```
`Grid.Contains` is `_, ok := g.Cells[p]; return ok` — existence only. Neither `Pattern.ApplyInArea`
(pure coordinate-bounds math) nor `Contains` ever reads `Cell.Type`. An Obstacle- or Water-typed cell
that exists in the grid's cell map passes through AoE/zone selection identically to a Ground cell.

### 11.3 Skill targeting has zero cell-type checks — confirmed, with a direct comparison table
`checkSkillTarget`'s entire `TargetType` switch (`skill_validation.go:123-189`) reads only
`c.EntityIDs`/`c.IsOccupied()` in every branch — **never `c.Type`**. Concretely:

| CellType | Move/reposition landing | Attack target | Skill `TargetTypeTile` target | A* pathfinding neighbor |
|---|---|---|---|---|
| Ground | ✅ | ✅ | ✅ | ✅ |
| Dirt | ✅ | ✅ | ✅ (no check) | ❌ (A* requires exactly `Ground`) |
| Water | ❌ rejected | ❌ `entity.attack.celltype` | ✅ **allowed, no check** | ❌ |
| Obstacle | ❌ rejected | ❌ rejected | ✅ **allowed, no check** | ❌ |
| Debug/Debug2 | ❌ rejected | ❌ rejected | ✅ **allowed, no check** | ❌ |

Attack has an explicit check skill targeting lacks entirely:
```go
// attack_checks.go:53-56
if target.Type != cell.Ground && target.Type != cell.Dirt {
    return false, msg.ReplyWithError("Invalid attack", "entity.attack.celltype")
}
```
No equivalent line exists anywhere in `skill_validation.go`. **Confirmed yes**: a `TargetTypeTile`
skill can legally be cast directly onto a Water, Obstacle, or Debug cell today, provided the cell
exists and is unoccupied — the only test for `TargetTypeTile`
(`TestRuleSkillFailTargetNoApplicableTarget_Cell`) exercises the occupancy branch only, against an
occupied *Ground* cell; no test targets an unoccupied non-Ground cell because no rejection exists to
test.

### 11.4 Positional-effect placement has no cell-type validation, and no production creator at all
`Scenario.Trap` (the test harness's only writer of `GameState.PositionalEffects`) does zero
`Grid.CellAt`/`Contains`/`Type` validation on the placement position. More significantly: **grepping
every non-test writer of `GameState.PositionalEffects` in `upsilonbattle` found only cleanup/removal
code — nothing in production ever creates one.** The "invisible anchor entity" mechanism
(`TimeBased`, `Invisible=true`, `WalkThrough=true`) described in `mech_positional_effects.atom.md`
as current mechanic has **zero implementation anywhere** (`grep -rn "TimeBased\|Invisible"` across
non-test `upsilonbattle` code: zero hits) — this independently reconfirms §8.5's ATD drift finding
from the code side, and sharpens ISS-154's "no producer mechanism" finding into "no producer
mechanism, period, for any positional effect, not just this one skill."

### 11.5 Can an entity occupy an Obstacle cell? Nothing stops it
`Grid.AddEntity`/`MoveEntity` do zero cell-type checking — the *only* place `cell.Obstacle` is
excluded during placement is `Grid.RandomPosition()` (a spawn-convenience helper, opt-in per call
site, not an invariant). `WalkThrough` (`HasBlockingEntity`, used only by `move.go`/`reposition.go`)
governs whether one entity can move onto a cell already holding *other entities*, based on those
entities' own `WalkThrough` property — it has nothing to do with `Cell.Type` and is never consulted
by `checkSkillTarget` or AoE effect application. If entities ever did end up co-located with an
Obstacle cell (bug, hand-authored spawn, or a `ReplaceCellType` call after the fact), an
`EnemyOnly`/`FriendOnly`/`Entity` AoE selection would collect them via `c.EntityIDs` with no
`WalkThrough` or `Type` gate at all — the effect would apply as if nothing were unusual.

### 11.6 Test coverage: exactly two tests in the whole suite ever set a non-Ground/Dirt cell type
```
rules_move_extended_test.go:142:  ReplaceCellType(..., cell.Obstacle)   // Move rejection test
rules_attack_failure_test.go:114: ReplaceCellType(..., cell.Water)      // Attack rejection test
```
**Zero tests do this for a skill** (targeting, cast, or AoE zone) and **zero tests do this for
positional-effect placement.** This independently reconfirms §2.4/§9.3's "no AoE-shape test exists
beyond `Neighbours`" finding from a different angle — the near-total absence of terrain-type
variation in the test fixtures generally, not just for AoE shapes specifically.

### 11.7 Wire mapping is a lossy simplification that happens to (accidentally) match the skill gap
`upsilonapi/api/output.go:497`: `Obstacle: cl.Type == cell.Obstacle` — a single boolean, exact
equality against `CellType(0)` only. Water/Debug/Debug2 all serialize as `obstacle: false`,
indistinguishable from Ground/Dirt on the wire; there is no `type`/`cell_type` field at all. The
resurrection round-trip DTO (`ResurrectCell`) is equally lossy — anything that isn't `Obstacle`
collapses to `Ground` on reconstruction. For skill targeting this happens to be harmless (skills
don't check cell type either, so the client's blind spot matches the server's), but for move/attack
it's actively misleading: a Water tile reports `obstacle: false` (i.e. "fine"), while the server
rejects it for both move and attack. No code or comment anywhere marks this asymmetry as
intentional — it reads as an artifact of `CellType` never having been fully round-tripped to the
client.

---

## 12. Elevation (Z-axis) impact on targeting 🟢

Source: Round 2 dedicated agent, tracing production board generation, `JumpHeight`, and the 3D
`Circle`/`Square`/`Line` pattern math against real grid Z-bounds.

### 12.1 Elevation is real but shallow in production — and three unrelated generators sit unused
The only two call sites that build a live `*grid.Grid` (`upsilonapi/bridge/bridge_start.go:60-69`,
the actual match-start path, and an unused `ruler.go` helper) both hardcode `Type:
gridgenerator.Flat`. `generateFlat` picks one `ground_height` for the whole map, then applies sparse
per-column noise (`applyHeightVariation`: 10% chance to raise a tile by 1, 2% chance to lower it by
1) — real matches are "almost-flat with occasional 1-tile bumps," never genuine multi-level terrain.
`Hill` and `River` are fully implemented and unit-tested at the generator level but **never selected
in production**. `Mountain` is worse — it's a `GridType` constant with **no case in `Generate()`'s
switch**, silently falling through to `default: res = g.generateFlat()`; selecting `Mountain` today
silently produces a flat map, with no test that would catch this. Nearly every unit test uses
`GeneratePlainSquare`, hardcoded to a single Z=1 plane.

### 12.2 `JumpHeight` — fully traced, and it only governs movement
Read at exactly one production call site pattern, repeated 11 times (once in `move.go:143`, ten
times identically across every AI micro-behavior file feeding `AStarPath`). It gates a per-step Z
delta cap in `Position.IsAdjacent`:
```go
func (p Position) IsAdjacent(p2 Position, allowedJump int) bool {
    return (p.X == p2.X && tools.Abs(p.Y-p2.Y) == 1 && tools.Abs(p.Z-p2.Z) <= allowedJump) ||
        (p.Y == p2.Y && tools.Abs(p.X-p2.X) == 1 && tools.Abs(p.Z-p2.Z) <= allowedJump)
}
```
Per-step, not cumulative. The one live cross-Z test in the whole suite
(`TestRuleMoveFailNotAdjascentJumpHeight`) confirms the rejection case (`Δz=3` fails against default
`JumpHeight=2`) but has **no positive boundary test** (`Δz == JumpHeight` succeeding) and no
buffed-`JumpHeight` test, despite `JumpHeight` being one of the 8 entity-buffable keys (§5.2).

### 12.3 Three completely disconnected Z rules — the coherence gap
- **Move**: per-step `|Δz| ≤ JumpHeight` (§12.2).
- **Attack**: hardcoded `zDiff > effectiveRange+1`, **never reads `JumpHeight` at all** — a
  character with `JumpHeight=0` gets the same `+1` vertical attack allowance as one with
  `JumpHeight=5`.
- **Skill**: **no Z gate whatsoever.** `target.Z` is fully client-supplied and unconstrained by the
  range check (`skill_validation.go:99`, explicit comment: "ignoring height").

A buffed `JumpHeight` changes movement/pathing reach only — zero effect on attack or skill vertical
reach. There is no shared "vertical reach" concept anywhere in the engine.

### 12.4 The crux scenario: AoE sweeps Z-levels the range check never validated
`pattern.Circle(radius)` is a genuine 3D Euclidean sphere (`x²+y²+z²≤radius²` across all three
axes) — for `radius=2`, the point `(0,0,2)` (2 levels straight up) satisfies `0+0+4≤4` and is
included. `SelectPositionsByPattern` applies this pattern against **real 3D grid cells** (a true map
lookup keyed by full `{X,Y,Z}`, not a 2D projection) — so a `Circle:2` AoE centered on a target tile
genuinely reaches `Z±2` at that column, *as long as a real cell physically exists there*. Since the
range check that decided the target tile was reachable never inspected `target.Z` in the first
place, **a target position at any Z the client cares to supply passes the range gate outright** as
long as X/Y are in range and X/Y/Z resolve to a real cell — no reachability, LOS, or jump-height
reasoning applies to target selection itself. In today's `Flat`-only production maps this is nearly
unreachable in practice (barely any real Z variance exists — §12.1), but the mechanism itself is a
real, currently zero-coverage gap waiting for any map with real verticality.

### 12.5 Bonus finding: `Grid.ReplaceCell` doesn't bounds-check the new position's Z
`ReplaceCell` validates only that the **old** position currently has a cell — it never checks
`PositionIsInGrid`/`Height` for the **new** position before inserting. `applyHeightVariation`'s
"raise by 1" branch (exactly the mechanism that gives production maps their real elevation) calls
this directly; if a column is already at `Height-1`, the raise event silently inserts a cell at
`Z == Height` — outside the grid's own declared bound, invisible to every `TopMost*` accessor (all
loop from `Height-1` down) and unreachable by `SelectPositionsByPattern` (whose bounds filter runs
`pt.Z < height` first). A silently-created, permanently-orphaned ghost cell — code-inspection
finding, not runtime-verified, and with no test coverage either way.

### 12.6 Everything else checked for Z-awareness — none found
Backstab/orientation (`IsBackstabbing`, `AngleTo`) is purely 2D — no `.Z` reference anywhere; an
attacker directly above/below a target has undefined-by-omission orientation behavior. No AI
behavior file scores a position based on its Z value (Z is only ever carried along inertly or gated
per-step via `JumpHeight`/A*). Reposition/dash effects are explicitly Z-locking by design
(`repositionLanding` keeps `from.Z` unconditionally) — a fourth, independent Z-handling rule,
correctly documented as intentional fly-over semantics. `pattern.go`'s 3D shape functions
(`Circle`/`Square`/`Line`/`Neighbours`) have **zero dedicated unit tests** — the package's only test
file exercises an unrelated 2D pathfinding helper.

---

## 13. Line of sight 🟢

Source: Round 2 dedicated agent, exhaustive grep sweep of the backend plus a direct trace of the
frontend's `hasLOS` implementation.

### 13.1 Server-side: no LOS/occlusion algorithm exists anywhere, live, dead, or test-only
An exhaustive grep for `LineOfSight|LOS|raycast|occlu|visib|sightline|bresenham` across
`upsilonbattle`, `upsilonmapdata`, `upsilontypes`, `upsiloncli` turns up exactly one place the string
`"Line of Sight"` is even compared — the already-known no-op in `skill_validation.go:119`, explicitly
annotated unimplemented by its own author's comment. Every other hit is unrelated (`Invisible` is a
client-snapshot-suppression flag, `KnownEntities` doc comments mean "known to the controller," not
sightline visibility). **No grid-walk, ray, or occlusion function exists to enforce LOS anywhere in
the backend.**

### 13.2 Client-side LOS is real, and blocks on both terrain *and* entities — purely 2D
`hasLOS` (duplicated verbatim in `useActionDispatch.js:124-139` and `BattleArenaSandbox.vue:132-145`
— two independent copies of the same logic):
```js
function hasLOS(sx, sy, tx, ty) {
    const dx = tx - sx, dy = ty - sy;
    const dist = Math.max(Math.abs(dx), Math.abs(dy));
    if (dist <= 1) return true;
    for (let i = 1; i < dist; i++) {
        const cx = Math.round(sx + dx * i / dist);
        const cy = Math.round(sy + dy * i / dist);
        if (grid.value.cells[cx]?.[cy]?.obstacle) return false;
        if (allEntities.value.some(e => e.id !== currentEntityId.value && e.position.x === cx && e.position.y === cy && e.hp > 0)) return false;
    }
    return true;
}
```
Linear-interpolation-and-round sampling (Chebyshev-distance step count) — not true Bresenham, no
octant handling, but a real algorithm. It blocks on **both** static terrain (`cell.obstacle`) and
**living entities** (explicitly excluding the caster and dead entities) — so yes, a standing entity
blocks another entity's skill-targeting LOS client-side. It is purely 2D — the function signature
only ever takes `sx,sy,tx,ty`, no Z term anywhere, matching the server's own 2D-only range math.

### 13.3 The real surprise: the client applies LOS to *every* skill, unconditionally
`calculateSkillRange()` calls `hasLOS(...)` for every skill's range preview **regardless of that
skill's `TargetingMechanics` value** — `TargetingMechanics` is never even read anywhere in
`useActionDispatch.js` (confirmed by grep: only `Range` and `TargetType` are read from
`skill.targeting`). So the actual divergence is not "the LOS mechanic exists but isn't enforced" —
it's stronger than that: **the client always shows an LOS-filtered preview for every skill, with no
relationship at all to the skill's declared mechanic, while the server enforces neither variant for
any skill.** `"Anywhere"` and `"Line of Sight"` behave identically on both sides today, just
differently-identically (client: always filtered; server: never filtered).

### 13.4 AI is purely range-based; no sightline reasoning anywhere
Checked `flank.go`, `kite_away.go`, `ambush.go` directly (plus a full grep of `behavior/` and
`behavior/micro/`). All engagement decisions use `tools.Distance(...) <= atkRange` — pure Euclidean/
Manhattan range, never LOS. `ambush.go`'s "move adjacent to an obstacle to hide" logic only checks
`cell.Type != cell.Ground` on cardinal neighbors to find cover-adjacent tiles — positioning flavor,
not a sightline test between self and target.

### 13.5 ATD documentation — partial and, in one case, actively wrong (see §8.9 for the full drift writeups)
No atom proposes or scopes a `TargetingMechanics`/skill-LOS feature build-out as DRAFT future work.
What exists: `mech_constructed_obstacle.atom.md` documents a Barrier's "blocks LoS" attribute with
no enforcing code (§8.9 drift #5); `mechanic_backstab_detection_algorithm.atom.md` documents an LOS
prerequisite for backstab and falsely claims it's "Verified by `backstab_test.go`" — the actual test
only checks facing angle (§8.9 drift #4); `entity_grid.atom.md` and
`upsilonmapdata`'s own VISION atom both describe `Obstacle`/geometric-precision as "blocks
line-of-sight"/enabling LOS calculations at the doc-intent level, again with no implementing code.
**No issue in `/issues/` tracks any of this** — the LOS gap (client/server divergence, the
unconditional-client-filter surprise, the backstab-atom drift) is entirely undocumented as debt.

### 13.6 What server-side LOS would need
The grid already carries sufficient static data for basic terrain-only occlusion — `CellType ==
Obstacle`, addressable by real 3D position, already asserted by doc comments to "block LOS." No new
map-authoring investment is required for *that* much. What's missing is purely the tracing algorithm
itself (nothing exists to build on), and — if entity-blocking parity with the client is wanted — new
logic to look up live entity occupancy along a traced path (the server has the underlying data via
`Cell.EntityIDs`, just no function that consults it for this purpose).

### Balance corollary (found incidentally, load-bearing for how much this divergence actually matters)
`upsilontypes/entity/skill/skillweight/skillweight.go:57-63` charges skills a **+40 Positive-Skill-
Weight budget premium** for `TargetingMechanics = "Anywhere"`, implicitly pricing `"Line of Sight"`
as the cheaper, more-restricted baseline — and the procedural skill generator's own comment
(`blueprint.go:20-21`) confirms this is deliberate: *"Default TargetingMechanics is 'Anywhere' which
adds +40 PSW. Override to LoS so budget calculations are deterministic."* Since LOS is never actually
enforced server-side (§13.1/§13.3), a skill authored or generated with `"Line of Sight"` gets a real
balance discount for a restriction with **zero actual gameplay effect** — it behaves exactly like
`"Anywhere"` in practice but is priced as though it were meaningfully weaker. This is a design-
integrity gap adjacent to targeting proper, not filed as an issue per this investigation's read-only
scope, but it's the concrete evidence for why the LOS gap is worth prioritizing over a typical
"nice to have" feature — it's currently distorting the skill-balance economy, not just missing a
polish feature.

---

## 14. Explicit gap summary (per the user's request to annotate what's missing — updated after the Round 2 follow-up)

| Area | Status | What's solid | What's still missing |
|---|---|---|---|
| Range & distance | 🟢 Complete | Full formula trace, divergence documented, rejection table | — |
| Line of sight | 🟢 Complete (Round 2) | No server LOS anywhere; client algorithm fully traced; unconditional-filter surprise found; balance-corollary bug found | — |
| Zone/AoE geometry | 🟢 Complete (Round 1 partial + Round 2 closed it) | Shape grammar, exact point counts, anchoring/team-filter rules, obstacle behavior, vertical-sweep crux scenario | — |
| Obstacles/cell-type validation | 🟢 Complete (Round 2) | Full walkable/targetable matrix across move/attack/skill/pathfinding, wire mapping, zero-producer positional-effect finding | — |
| Elevation (Z-axis) | 🟢 Complete (Round 2) | Production-map reality check, `JumpHeight` trace, 3-disconnected-rules finding, crux vertical-AoE scenario, bonus grid-bounds bug | — |
| TargetType/validation | 🟢 Complete | Full chain, full rejection table (both skill and attack paths) | — |
| Triggers/hooks | 🟢 Complete | Current dispatch mechanism, dead-code findings, exact onHit insertion points, re-entrancy verdict | — (design questions are ISS-149's, correctly not pre-answered here) |
| Buff/debuff | 🟢 Complete (agent interrupted by rate limit, but had already finished — no self-review pass done) | Full crux finding (base-vs-effective divergence), whitelist, stacking, serialization | A final read-through by a human/second pass wouldn't hurt, but no known content gaps |
| Data model | 🟢 Complete | Full key table, typed-vs-generic verdict, bad-cast surfaces | — |
| Wire/serialization | 🟢 Complete (Round 1 partial + Round 2 resolved the central question) | DTO shapes, ISS-158 confirmed directly, AoE multi-target representation fully traced end-to-end | — |
| ATD feedback | 🟢 Complete (Round 1 direct tool queries + Round 2 found 2 more drifts) | Full atom inventory, 5 confirmed drifts with atom-vs-code evidence, orphan/coverage stats, 4 concrete gap-atoms identified | No full `atd_check --semantic` compliance sweep; `atd_lint` errored opaquely and wasn't debugged |
| Test coverage | 🟢 Complete | Full matrix, 25-item uncovered list (17 Round 1 + 8 Round 2), harness guide with reusable templates | — |

**Bottom line**: every area flagged as a void after Round 1 is now closed. The two rounds together
surfaced one confirmed **production bug** (§7.5 — AoE webhook results silently drop to ≤1 target due
to a version-keyed dedup collision, independent of any future test-writing effort), one confirmed
**skill-balance inconsistency** (§13 — LOS targeting gets a cost discount for a restriction with no
gameplay effect), and five confirmed **ATD documentation drifts** where an atom describes
functionality that doesn't exist in code (§8.3–§8.5, §8.9). None of the remaining line items in this
table represent open investigation work — what's left everywhere is test-writing, not more research.
The only two loose ends genuinely worth a short follow-up rather than being blocking: `atd_lint`'s
opaque "linting failed" error (worth a quick standalone rerun to see if it's transient), and whether
`Pattern.Contains`/`ContainsAny`/`ContainsAll` have a live targeting call site (low priority, neither
Round 2 agent surfaced one).

---

## 15. Proposed unit test suite for the next round

Compiled from every gap/finding across §§1–14, deduplicated against §9's existing 25-item list and
extended with everything the rest of the document surfaced (buff crux, wire/webhook bug, ATD drifts,
malformed-input panics, Z-axis, LOS). Grounded against the actual repo: harness API confirmed live in
`upsilonbattle/battlearena/battletest/{builders,scenario,inspect}.go`; existing test-file names
confirmed in `upsilonbattle/battlearena/ruler/rules/*_test.go`, `upsilonapi/api/*_test.go`, and
`upsilonmapdata/grid/position/pattern/pattern_test.go`.

**Markers**: 🐛 = exercises a confirmed bug/structural inconsistency — write to lock in *current*
behavior as an explicit, visible regression floor, not as a "should pass" spec, until a fix is
decided. 📄 = doubles as a regression guard for an ATD atom-vs-code drift found in §8/§8.9 (fixing
the atom or the code should make the test's intent obvious either way). No marker = pure coverage gap,
no known issue behind it. **Harness**: `battletest` = new fluent harness (preferred, `battlearena/
battletest`); `rules` = old-style `package rules` harness; `pattern` = plain Go table test in
`upsilonmapdata/grid/position/pattern`; `api` = `upsilonapi/api` HTTP/DTO-level test; `frontend` =
Vitest/Jest in `upsilonbattleui`, out of the Go suite.

### A. Range & distance
| # | Proposed test | Asserts | Harness | Reveals |
|---|---|---|---|---|
|A1| `TestSkillRangeAtMinBoundary_Succeeds` | dist == MinRange succeeds, explicit assertion not incidental | battletest | — |
|A2| `TestSkillRangeAtMaxBoundary_Succeeds` | dist == MaxRange succeeds | battletest | — |
|A3| `TestSkillRangeBelowMin_Rejected` | dist < MinRange rejects with `skill.target.range` even at "close" distance | battletest | — |
|A4| `TestSkillRangeDiagonal_ManhattanSum` | dx=2,dy=3 validated against Manhattan sum=5, first test ever varying both axes at once | battletest | — |
|A5| `TestSkillRangeZeroBand_OnlyOriginTileValid` | `Range(0,0)` accepts only the caster's own tile, rejects every neighbour | battletest | — |
|A6| `TestSkillRangeIgnoresZ_SameXYDifferentZ_BothPass` | two same-X/Y targets at different Z both pass the identical 2D check | battletest | 🐛 §1/§12.3 |
|A7| `TestAttackVerticalAllowance_ExactBoundary` | Δz == effectiveRange+1 succeeds, Δz == effectiveRange+2 fails | rules | — |
|A8| `TestSkillVsAttackRangeFormula_SameGeometryDivergentVerdict` | identical X/Y/Z pair evaluated by both formulas side-by-side, diverging on Z | rules | 🐛 §1 |
|A9| `TestBuffedAttackRange_NoEffectOnSkillCastRange` | +N AttackRange item buff changes attack legality, zero effect on skill range at same distance | battletest | 🐛 §5.3 |

### B. Zone / AoE geometry
| # | Proposed test | Asserts | Harness | Reveals |
|---|---|---|---|---|
|B1| `TestPattern_Circle1_Yields7PointCross` | `pattern.Circle(1)` == exact 7-point 3D cross from §2.2's table | pattern | — |
|B2| `TestPattern_Circle2_Yields33Points` / `TestPattern_Circle3_Yields123Points` | same, radius 2 and 3 | pattern | — |
|B3| `TestPattern_Square1_IsFullCubeIncludingCorners` | `Neighbours()`/`Square(1,1,1)` = full 27-cell cube, includes `(1,1,1)` at Manhattan dist 3 | pattern | — |
|B4| `TestPattern_Line_AlwaysDrawsPositiveX_IgnoresTargetDirection` | `Line:3` toward a westward target still resolves east of the caster | pattern | 🐛 §2.2 |
|B5| `TestZoneSet_MalformedForms_Panic` | table-driven: `"Circle"`, `"Circle:0"`, `"Circle:-1"`, `"Circle:abc"`, `"Hexagon:3"` all panic raw, not structured-error | rules | 🐛 §2.1 |
|B6| `TestSkillSpecZone_SmokeEndToEnd` | `SkillSpec.Zone("Circle:1")` resolves a real hit set — first-ever exercise of this builder method | battletest | — |
|B7| `TestAoECircle1_LightningStrikeFixture_Hits7Cells` | real seed skill `Lightning Strike` (`Zone:"Circle:1"`) hits exactly the 7-cell cross | battletest | — |
|B8| `TestAoE_EuclideanCircleExcludesInRangeManhattanDiagonal` | a diagonal ally within Manhattan cast-range sits outside the caster's own `Circle:1` AoE | battletest | — |
|B9| `TestAoE_OverlapsCasterTile_CasterIncludedForEntityAndFriendOnly` | zone centered so caster's own cell is inside pattern → caster is in the hit set | battletest | — |
|B10| `TestAoE_EnemyOnly_NeverSelfHits` | structural contrast to B9 — `EnemyOnly` can't include the caster | battletest | — |
|B11| `TestAoE_MixedAllyEnemyInZone_BothHitUnderEntityTarget` | ally + enemy both inside an `Entity`-target AoE both get hit, no team filter | battletest | — |
|B12| `TestAoE_NoFalloffByDistance_IdenticalDamageAtEveryRadius` | near and far targets in the same AoE take identical computed damage | battletest | — |
|B13| `TestAoE_PartiallyOffGrid_KeepsOnGridCellsOnly` | zone straddling map edge drops off-board cells, doesn't reject the cast | battletest | — |
|B14| `TestAoE_FullyOffGrid_RejectsWithOutOfGridError` | pattern origin entirely off-grid → `skill.target.outofgrid` | battletest | — |
|B15| `TestAoE_EmptyTargetSet_RejectsWithTargetNoneError` | zero eligible entities in zone → `skill.target.none` | battletest | — |
|B16| `TestAoE_OverlappingCellSelection_NoDoubleHitPerEntity` | overlapping pattern cells don't double-apply the effect to one entity | battletest | — |
|B17| `TestAoE_TargetDiesMidResolution_RemainingHitsDeterministic` | a target killed earlier in the same AoE loop doesn't crash/double-process later in the loop | battletest | — |
|B18| `TestTargetTypeEntityOrTile_Success` | the untested 6th `TargetType` enum value resolves against occupied and empty tiles | battletest | — |
|B19| `TestTargetTypeTile_SuccessOnEmptyGroundCell` | tile-only targeting success path (only the occupied-failure case exists today) | battletest | — |
|B20| `TestReposition_ThenAoE_ZoneCentersOnPostMoveTile` | AoE cast immediately after reposition centers off the new position, not the old one | battletest | — |
|B21| `TestReposition_DiagonalPath_Succeeds` | non-axis-aligned reposition path, all existing cases are axis-aligned | battletest | — |

### C. TargetType, validation chain & ordering
| # | Proposed test | Asserts | Harness | Reveals |
|---|---|---|---|---|
|C1| `TestTargetCheck_FiresBeforeCostCheck_NotAfter` | out-of-range + insufficient-MP simultaneously → range error wins, not cost error | battletest | 📄 §8.3 drift #1 |
|C2| `TestRangeCheck_FiresBeforeGridBoundaryCheck` | out-of-range + fully-off-grid simultaneously → range error wins | battletest | 📄 §8.3 drift #1 |
|C3| `TestDeadEntity_NeverInResolvedTargetSet` | an entity killed by a prior action never appears in a later AoE's hit set | battletest | — |
|C4| `TestPassiveReactionCounter_BypassesTargetResolutionEntirely` | Passive/Reaction/Counter behaviors never compute a target set at all | battletest | — |
|C5| `TestAttackNoEntityCheck_BothSitesAgree` | the duplicated `entity.attack.noentity` check (pre-check + inline) behaves identically at both | rules | — |

### D. Obstacles & cell-type validation
| # | Proposed test | Asserts | Harness | Reveals |
|---|---|---|---|---|
|D1| `TestSkillTargetTypeTile_OntoWaterCell_CurrentlySucceeds` | `TargetTypeTile` cast directly onto Water succeeds, no rejection | battletest | 🐛 §11.3 |
|D2| `TestSkillTargetTypeTile_OntoObstacleCell_CurrentlySucceeds` | same, onto Obstacle | battletest | 🐛 §11.3 |
|D3| `TestSkillTargetTypeTile_OntoDebugCell_CurrentlySucceeds` | same, onto Debug/Debug2 | battletest | 🐛 §11.3 |
|D4| `TestAoESelection_IgnoresCellTypeOfSweptCells` | AoE sweeping Ground+Water+Obstacle cells collects entities from all identically | battletest | — |
|D5| `TestEntityOnObstacleCell_StillAoETargetable` | entity manually placed on Obstacle cell still selected normally by AoE | battletest | — |
|D6| `TestPositionalEffectPlacement_OnObstacleCell_NoRejection` | `Scenario.Trap` at an Obstacle position places with zero validation | battletest | 📄 §8.5 drift #3 |
|D7| `TestWireObstacleField_WaterCellReportsFalse_ServerStillRejects` | `obstacle:false` for Water is misleading vs. actual move/attack rejection | api | 🐛 §11.7 |

### E. Elevation (Z-axis)
| # | Proposed test | Asserts | Harness | Reveals |
|---|---|---|---|---|
|E1| `TestJumpHeight_ExactBoundary_Succeeds` | Δz == JumpHeight succeeds (only the rejection case is tested today) | rules | — |
|E2| `TestJumpHeight_Buffed_WidensMovementReach` | +N JumpHeight item buff actually widens the accepted per-step Δz | battletest | — |
|E3| `TestSkillCircle2AoE_HitsTargetTwoZLevelsAway` | `Circle:2` centered on a Z-blind-range-validated target also hits an entity 2 Z-levels up | battletest | 🐛 §12.4 |
|E4| `TestAttackVerticalAllowance_IgnoresJumpHeightStat` | JumpHeight=0 and JumpHeight=5 entities get the identical `+1` attack vertical allowance | rules | 🐛 §12.3 |
|E5| `TestSkillRange_NoVerticalGateAtAll` | target directly above/below caster passes range purely on X/Y Manhattan distance | battletest | 🐛 §12.3 |
|E6| `TestGridReplaceCell_RaiseAtMaxHeight_OrphansGhostCellOutOfBounds` | height-variation raise at `Height-1` inserts an unreachable cell at `Z==Height` | pattern/rules | 🐛 §12.5 |
|E7| `TestBackstab_DirectlyAboveOrBelowTarget_PurelyAngleBased` | attacker directly above/below target gets whatever the 2D angle math yields, pinned explicitly | rules | — |
|E8| `TestGridType_Mountain_SilentlyFallsThroughToFlat` | selecting `Mountain` produces a flat map, no error/log | (mapdata generator) | 🐛 §12.1 |

### F. Line of sight
| # | Proposed test | Asserts | Harness | Reveals |
|---|---|---|---|---|
|F1| `TestTargetingMechanicsLOS_IdenticalToAnywhere_ServerSide` | `"Line of Sight"` and `"Anywhere"` skills both hit a target behind an Obstacle equally | battletest | 🐛 §13.1/§13.3 |
|F2| `TestBackstab_ThroughObstacle_StillGrantsBackstab` | obstacle physically between attacker and target's back doesn't block the backstab bonus | rules | 📄 §8.9 drift #4 |
|F3| `TestSkillWeightBudget_LOSDiscountDespiteNoEnforcement` | a generated `"Line of Sight"` skill gets the cheaper PSW budget with zero runtime restriction | (skillweight pkg) | 🐛 §13 balance corollary |
|F4| `TestHasLOS_AppliedToEveryPreview_RegardlessOfTargetingMechanics` | client filters every skill's range preview through `hasLOS`, `TargetingMechanics` never read | frontend | 🐛 §13.3 |

### G. Triggers / hooks
| # | Proposed test | Asserts | Harness | Reveals |
|---|---|---|---|---|
|G1| `TestOnStep_NeverFiresDuringMultiTileMove` | a 3-tile move through an OnStep-tagged cell never triggers it | battletest | 🐛 §4.1 |
|G2| `TestOnDeath_NeverFiresOnEntityRemoval` | killing an entity on an OnDeath-tagged cell dispatches nothing | battletest | 🐛 §4.1 |
|G3| `TestReposition_SkipsOnExitAndIntermediateCells_UnlikeMove` | reposition fires OnEnter only; contrasted in the same test against `Move()`'s OnExit+OnEnter pair | battletest | — |
|G4| `TestPositionalEffect_TwoEffectsOneCell_FireOrder` | actual fire order for two stacked effects on one cell, vs. atom's claimed "FCFS" | battletest | 📄 §8.4 drift #2 |
|G5| `TestMeleeAttack_NoAccuracyDodgeRoll_AlwaysHits` | melee has zero hit-test today — pin as the pre-ISS-149 baseline | rules | — |
|G6| `TestEffectApplicator_ConflatesAccuracyMissAndDodgeIntoOneRoll` | no way to distinguish an accuracy-miss outcome from a dodge outcome from the applied effect | rules | 🐛 §4.4 |
|G7| `TestParryProperty_NoReadSiteInCombat` | nonzero `Parry` on a skill/entity produces zero behavioral difference | battletest | 🐛 §4.4 (ISS-148) |

### H. Buff/debuff → targeting
| # | Proposed test | Asserts | Harness | Reveals |
|---|---|---|---|---|
|H1| `TestBuffedAttackRange_EnablesOtherwiseOutOfRangeAttack` | baseline: item AttackRange buff correctly widens basic-attack legality | battletest | — |
|H2| `TestBuffedAttackRange_SkillCastRangeUnaffected` | same buff, same distance — skill cast still rejected out-of-range (see A9, cross-referenced) | battletest | 🐛 §5.3 |
|H3| `TestBuffedAttackRange_SkillAoEZoneUnaffected` | same buff has zero effect on `Circle:N`/`Square:N` zone extent | battletest | 🐛 §5.3/§5.6 |
|H4| `TestEntityZoneBuff_DisplayOnly_NeverConsultedByTargeting` | a raw `ZoneProperty` on an item buff never affects actual targeting resolution | battletest | 🐛 §5.2 |
|H5| `TestBuffTickDown_NeverCalledFromEndOfTurn` | a duration-limited buff's remaining duration is untouched by an end-of-turn cycle | rules | 🐛 §5.4 |
|H6| `TestBuffableWhitelist_TargetingRelevantKeys` | table over the 8-key whitelist: `AttackRange`/`JumpHeight` buffable, `Zone` structurally excluded | rules | — |
|H7| `TestAttackRangeBuff_AbsentFromWirePayload` | after buffing, no `AttackRange` field (buffed or base) appears anywhere in the entity DTO | api | 🐛 §5.5 |

### I. Wire / serialization (incl. the AoE webhook bug)
| # | Proposed test | Asserts | Harness | Reveals |
|---|---|---|---|---|
|I1| `TestSyncActionReply_AoESkill_CarriesAllNResultsEntries` | the sync `/action` HTTP reply for a 3-target AoE has a 3-element `results` array | api | — (locks in the working path) |
|I2| `TestWebhookActionFeedback_AoESkill_HardcodedSingleResultEntry` | webhook `Results` slice is always length-1 regardless of actual hit count | api | 🐛 §7.5.1 |
|I3| `TestWebhookDedupCache_MultiTargetAoE_DropsAllButOneNotification` | N same-`Version` `NotifyActor` calls collapse to ≤1 delivered webhook | api | 🐛 §7.5.2 (highest-severity) |
|I4| `TestHTTPControllerMapResults_ShapeIsCorrect_ButUnused` | orphaned `mapResults` converter already produces the right N-entry shape | api | 🐛 §7.5 (dead scaffolding) |
|I5| `TestCreditAwards_LumpSumDuplicatedAcrossAoEResults` | same aggregate credit slice copied onto every `ActionResult`, naive summation overcounts | api | 🐛 §7.5 credits |
|I6| `TestPropertyDTO_TargetTypeSerializesUnderSValueNotValue` | server-side confirmation grounding ISS-158's client read bug | api | 🐛 §7.3/ISS-158 |
|I7| `TestUseActionDispatch_TargetTypeAlwaysFallsBackToEntity` | `skill.targeting?.TargetType?.value` is `undefined` for every real skill | frontend | 🐛 §7.3/ISS-158 |
|I8| `TestZoneWireField_RawPatternStringOnly_NoResolvedOffsets` | `EquippedSkill.Zone` serializes `"Circle:3"` as a bare string, no offset list | api | — |

### J. Data model / bad-cast surfaces
| # | Proposed test | Asserts | Harness | Reveals |
|---|---|---|---|---|
|J1| `TestDefaultIntProperty_SetNonInt_Panics` | `.Set(interface{})` with a non-int panics outside the one guarded call site | (property pkg) | — |
|J2| `TestSetSkillPropValue_MalformedZoneString_AdminHandlerBehavior` | confirm whether the guarded admin call site still lets the panic escape to the handler | (upsilonapi handler) | 🐛 §2.1/§6.3 |
|J3| `TestLeechCostInTargetingMap_StillResolvesViaCrossScan` | the 9 mis-filed leech-in-Targeting call sites still resolve correctly pre-ISS-159-fix | rules | 📄 ISS-159 |

### K. Cross-referenced ATD-drift lock-ins (for traceability, not new tests)
`C1+C2` → drift #1 (`mech_skill_validation` order) · `G1+G2+G4` → drift #2 (`mech_trigger_system`
aspirational content) · `D6` → drift #3 (`mech_positional_effects` zone-entity producer) · `F2` →
drift #4 (`mechanic_backstab_detection_algorithm`'s false "Verified by" claim) · `F1` → drift #5
(`mech_constructed_obstacle`'s unenforced "blocks LoS"). Writing these six tests (C1, C2, D6, F1, F2,
plus one of G1/G2/G4) before or alongside the atom corrections gives each drift fix a red→green guard.

**Priority read, if only doing a handful first**: B1/B5 (cheapest, zero-existing-coverage, ready-made
expected data), I3 (highest-severity live bug), H2 (highest-value new-atom candidate per §8.7), D1–D3
(cheap table test, real gap), F1 (cheapest LOS regression lock-in).
