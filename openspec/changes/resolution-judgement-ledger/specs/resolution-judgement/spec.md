## ADDED Requirements

### Requirement: A resolution verdict SHALL be recorded as a provenance reference on the judged record

A human resolution verdict (confirmation or rejection of a pairing between an entry author literal and a person or organization) SHALL be persisted as a `ProvenanceReference` of kind `judgement` on the judged record, using field `resolution-confirmed` or `resolution-rejected`, with `value` locating the pairing as `<citekey> :: <literal>`. No new serialized shape SHALL be introduced; the store format SHALL remain unchanged.

#### Scenario: Rejecting a proposed candidate

- **WHEN** a user rejects a resolution candidate by its row identifier
- **THEN** a `resolution-rejected` reference SHALL be written to the candidate person naming the pairing, and the entry SHALL NOT be modified

#### Scenario: Applying a proposed candidate

- **WHEN** a user applies a resolution candidate
- **THEN** the entry author is rewritten as before, and additionally a `resolution-confirmed` reference SHALL be written to the person in the same operation

#### Scenario: Round-trip on an existing-format store

- **WHEN** a record carrying verdict references is encoded and decoded on the current store format
- **THEN** the record SHALL round-trip byte-stably with no format marker change

### Requirement: Rejection SHALL be distinct from absence

A rejected pairing ("checked — not this person") SHALL be a recorded observation distinguishable from an unresolved literal ("not yet checked"). The two states SHALL NOT be conflated in any surface.

#### Scenario: Distinguishing the two states after the fact

- **WHEN** an entry author literal has a rejected pairing with person A and no verdict for person B
- **THEN** the ledger reports the A-pairing as rejected and the B-pairing as pending

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

Reject and apply actions SHALL be triggered only by explicit row identifiers supplied by the caller. No automatic rejection, automatic application, or automatic merge path SHALL exist.

#### Scenario: No auto-reject from low counts

- **WHEN** a candidate's evidence class has many rejections historically
- **THEN** the candidate is still proposed (ordered lower) and no verdict is written without an explicit action
