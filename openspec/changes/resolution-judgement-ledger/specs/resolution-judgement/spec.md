## ADDED Requirements

### Requirement: A resolution verdict SHALL be recorded as a provenance reference on the judged record

A human resolution verdict (confirmation or rejection of a pairing between a literal and a person or organization) SHALL be persisted as a `ProvenanceReference` of kind `judgement` on the judged record, using field `resolution-confirmed` or `resolution-rejected`, with `value` locating the pairing under the single grammar `<kind>:<key> :: <literal>` where kind is one of `work` (entry citekey; person family), `person`, or `org` (literal-holding record key; organization family). The kind token is mandatory — person and organization keys may legally collide (#166), and one grammar with an explicit kind is the only alternative to context-dependent parsing. No new serialized shape SHALL be introduced. Stores holding verdict references SHALL be format ≥ 8 (write-gated as with formats 6/7): the field whitelist is strict, so a pre-#232 binary quarantines the whole record — the gate converts that into refuse-if-newer's explicit "please upgrade".

#### Scenario: Rejecting a proposed candidate

- **WHEN** a user rejects a resolution candidate by its row identifier
- **THEN** a `resolution-rejected` reference SHALL be written to the candidate person naming the pairing, and the entry SHALL NOT be modified

#### Scenario: Applying a proposed candidate

- **WHEN** a user applies a resolution candidate
- **THEN** the entry author is rewritten as before, and additionally a `resolution-confirmed` reference SHALL be written to the person in the same operation

#### Scenario: Round-trip on a format-8 store

- **WHEN** a record carrying verdict references is encoded and decoded on a format-8 store
- **THEN** the record SHALL round-trip byte-stably, and reading or writing it SHALL NOT itself change the format marker

#### Scenario: Verdict write on a pre-8 store

- **WHEN** a reject is attempted on a store whose format is below 8
- **THEN** the action SHALL be refused with a message naming the required format; an apply SHALL still rewrite the entry but SHALL skip the confirmed verdict and disclose the skip in its response

#### Scenario: Renaming a cited work migrates the verdict

- **WHEN** an entry referenced by a `work:` verdict value is renamed to a new citekey
- **THEN** the verdict values SHALL be rewritten to the new citekey in the same operation and the rewrite SHALL be reported — a rejection SHALL NOT silently revert to pending

### Requirement: Rejection SHALL be distinct from absence

A rejected pairing ("checked — not this person") SHALL be a recorded observation distinguishable from an unresolved literal ("not yet checked"). The surfaces bound by this requirement are a closed enumeration — the resolve surfaces: `resolvePeople` (MCP), `resolve-people` and `resolve-organizations` (CLI), and the App adjudication view. Entity views (`akashic person`) and `doctor` are explicitly deferred (proposal Non-Goals; tracked as follow-up) — do not extrapolate additional surfaces from this requirement by similarity.

#### Scenario: Distinguishing the two states after the fact

- **WHEN** one entry's pairing with a person is rejected and a second entry carries the same literal with no verdict
- **THEN** the ledger reports the first pairing as rejected and the second as pending (a literal matching two persons is an ambiguity, produces no candidates, and is counted under `ambiguityTotal`, not `pending`)

### Requirement: The resolver SHALL NOT re-propose a rejected pairing

Resolution candidate generation SHALL exclude exactly the rejected `(citekey, literal, record key)` triples. The same literal on a different entry SHALL still be proposed.

#### Scenario: A rejected candidate stays rejected

- **WHEN** resolution runs after a pairing was rejected
- **THEN** that pairing does not appear among candidates, and the pending count does not include it

#### Scenario: Rejection does not blanket-ban the literal

- **WHEN** the same literal appears on a different entry
- **THEN** that new pairing is proposed normally

### Requirement: Calibration counts SHALL be derived, never stored

Three-state counts (confirmed / rejected / pending) per evidence class SHALL be computed from verdict references at read time. No count SHALL be persisted in any record.

#### Scenario: Counts reflect the reference set

- **WHEN** the reference set changes (a verdict is added)
- **THEN** the next computation reflects it without any stored counter being updated

### Requirement: Presentation SHALL use counts, order without hiding, and keep pending visible

Resolution surfaces SHALL present three-state counts (never ratios), SHALL order rejected pairings last without hiding them, and SHALL expose the total pending amount.

#### Scenario: No ratio anywhere

- **WHEN** counts are 3 confirmed / 1 rejected / 4 pending
- **THEN** the response contains those integers and no derived percentage or probability field

#### Scenario: Rejected candidates remain visible

- **WHEN** a candidate's pairing is rejected
- **THEN** it appears last in ordering with its rejected marker, not removed

### Requirement: A verdict SHALL require explicit human invocation

Reject and apply SHALL be explicit human actions, and no automatic rejection, automatic application, or automatic merge path SHALL exist. The explicit-invocation forms are a closed enumeration: MCP apply/reject take caller-supplied row identifiers; CLI `resolve-people --reject` takes row identifiers, CLI apply and the organization family use their pre-existing explicit selection mechanisms (`--apply` with narrowing; `--reject` requires narrowing). Apply and reject SHALL NOT be combined in one invocation.

#### Scenario: No auto-reject from low counts

- **WHEN** a candidate's evidence class has many rejections historically
- **THEN** the candidate is still proposed (ordered lower) and no verdict is written without an explicit action

### Requirement: Verdict references SHALL NOT carry rests-on; evidence carriers are assigned by lifecycle

A resolution verdict reference SHALL NOT carry a rests-on slot (#280 ruling, 2026-08-14). Evidence supporting resolution work has exactly two carriers, assigned by the lifecycle stage of the question: for a **decided** pairing (confirmed or rejected), the load-bearing evidence SHALL live in the judged person's or organization's `references` (entity level, written via the bootstrap path, content-addressed into `sources/`); for an **undecided** pairing (investigated but insufficient), the collected evidence SHALL live in a divergence record's `judgement.restsOn`. The verdict itself stays lightweight — this preserves the batch character of apply/reject (#232's design; a per-pairing digest requirement would degrade batch resolution into per-item resolution) and the link between a verdict and its evidence is the judged entity itself, not a per-verdict binding. This is a deliberate design ruling, not a gap; reversing it later is an additive schema change with no migration cost.

#### Scenario: Evidence for a confirmed pairing

- **WHEN** a user confirms a pairing after collecting load-bearing evidence
- **THEN** the evidence SHALL be recorded as `references` on the person (not on the verdict), and the verdict SHALL be written without any evidence pointer

#### Scenario: Evidence for an undecidable pairing

- **WHEN** investigation ends without sufficient evidence to decide
- **THEN** no verdict SHALL be written; the collected evidence SHALL be recorded in a divergence record's `judgement.restsOn` so the next investigator resumes from it
