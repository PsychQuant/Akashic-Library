## Purpose

Defines which judgement records a literal-to-key pairing can hold — confirmed, rejected, and undecided — which two records count as the same record, how a pairing's state is derived from them, and how nomination and batch apply treat a pairing that was checked but could not be decided. It exists so that "checked and undecided" is distinguishable from "never checked", and so that a per-work judgement can be recorded next to an earlier apply verdict for the same pairing.

## ADDED Requirements

### Requirement: Verdict fields SHALL be a closed set of three

A resolution verdict reference SHALL use exactly one of three fields: `resolution-confirmed`, `resolution-rejected`, `resolution-undecided`. All three SHALL use the value grammar `<kind>:<key> :: <literal>` and SHALL be judgement references. The store SHALL reject any other field that claims to be a verdict. A fourth verdict field SHALL NOT be introduced without amending this requirement.

#### Scenario: An undecided verdict is accepted on a person record

- **WHEN** a person record holds a reference with field `resolution-undecided`, value `work:chen2020a :: C.-H. Chen`, and a judgement statement
- **THEN** the store SHALL load the record without quarantine

#### Scenario: An undecided verdict with a malformed value is rejected

- **WHEN** a person record holds a reference with field `resolution-undecided` and value `chen2020a C.-H. Chen`
- **THEN** the store SHALL reject the record with an error naming the value grammar

### Requirement: Only undecided verdicts SHALL carry evidence digests

An undecided verdict SHALL be allowed to name zero or more content digests in its rests-on list. Confirmed and rejected verdicts written by the resolution surfaces SHALL carry an empty rests-on list. The evidence for a decided pairing SHALL live in the judged record's ordinary references.

#### Scenario: An undecided verdict names what was checked

- **WHEN** an operator records a pairing as undecided with two stored source digests
- **THEN** the written verdict SHALL list both digests in its rests-on
- **AND** its statement SHALL be the operator's text followed by the tail `[rule: checked-undecided]`

#### Scenario: An undecided verdict with no stored evidence

- **WHEN** an operator records a pairing as undecided without any digest
- **THEN** the verdict SHALL be written with an empty rests-on list

### Requirement: Confirmed and rejected verdicts SHALL belong to one of two judgement classes

Each confirmed or rejected verdict SHALL belong to exactly one class, derived from its rule tail:

| Class | Condition |
| ----- | --------- |
| `judged` | the rule is exactly `author-judged-per-work` or exactly `author-organization-judged` |
| `nominated` | every other case, including a missing rule tail and an unrecognised rule |

This is a closed enumeration. A third class SHALL NOT be introduced by analogy.

#### Scenario: A legacy verdict without a rule tail

- **WHEN** a confirmed verdict's statement carries no `[rule: …]` tail
- **THEN** its class SHALL be `nominated`

#### Scenario: An organization attribution

- **WHEN** a confirmed verdict's rule tail is `author-organization-judged`
- **THEN** its class SHALL be `judged`

#### Scenario: A per-work judgement

- **WHEN** a confirmed verdict's rule tail is `author-judged-per-work`
- **THEN** its class SHALL be `judged`

### Requirement: Verdict identity SHALL be defined by three named keys

The system SHALL define three keys and SHALL NOT compare verdicts by any other definition.

- The **pairing key** SHALL be the holder kind, the holder, and the normalized literal. It SHALL exclude the field and the class.
- The **record key** SHALL be the single definition of duplicate for write deduplication, merge collapse, and the duplicate-record health scan:
  - for a confirmed or rejected verdict: the field, the pairing key, and the class;
  - for an undecided verdict: the byte-exact content of the whole reference.
- The **field-and-pairing key** SHALL be the field plus the pairing key, used only where a caller needs "same field, same pairing, regardless of class".

Contradiction detection SHALL compare pairing keys and SHALL ignore class.

#### Scenario: Two classes of the same confirmed pairing are distinct records

- **WHEN** a person holds a `nominated` confirmed verdict and a `judged` confirmed verdict for `work:chen2020a :: C.-H. Chen`
- **THEN** their record keys SHALL differ
- **AND** the duplicate-record health scan SHALL NOT report them

#### Scenario: A nominated confirmed and a judged rejected are a contradiction

- **WHEN** a person holds a `nominated` confirmed verdict and a `judged` rejected verdict for the same pairing
- **THEN** the contradiction health scan SHALL report the pairing

##### Example: Record-key equality

| Reference A | Reference B | Same record key |
| ----------- | ----------- | --------------- |
| confirmed, `nominated`, literal `C.-H. Chen` | confirmed, `nominated`, literal `C.-H.  Chen` | yes |
| confirmed, `nominated` | confirmed, `judged` | no |
| undecided, statement "checked affiliations" | undecided, statement "checked co-authors" | no |
| undecided, identical bytes | undecided, identical bytes | yes |

### Requirement: Merge and rename SHALL preserve coexisting records

Merge collapse and rename folding SHALL use the record key. Two verdicts for the same pairing in different classes SHALL both survive a person merge, a work merge that rewrites holder values, and a rename. Undecided verdicts that differ in any byte SHALL all survive.

#### Scenario: A work merge keeps both classes

- **WHEN** two works are merged and a person holds a `nominated` confirmed verdict for the doomed work and a `judged` confirmed verdict for the surviving work with the same literal
- **THEN** after the merge the person SHALL hold both verdicts, both pointing at the surviving work

### Requirement: A pairing's state SHALL be derived as decided, undecided, or pending

For a pairing of holder, literal, and judged entity, the state SHALL be computed from the records and SHALL NOT be stored:

| State | Condition |
| ----- | --------- |
| `decided` | at least one confirmed or rejected verdict of any class |
| `undecided` | no confirmed or rejected verdict, and at least one undecided verdict |
| `pending` | no verdict of any field |

Undecided verdicts SHALL remain on the record after the pairing becomes decided. They SHALL NOT be retired, and SHALL NOT be treated as contradicting a confirmed or rejected verdict.

#### Scenario: A decision after an undecided check

- **WHEN** a pairing holds one undecided verdict and a confirmed verdict is then written
- **THEN** the pairing's state SHALL be `decided`
- **AND** the undecided verdict SHALL still be present

### Requirement: Calibration counts SHALL distinguish undecided from pending

Counts SHALL be four-valued: confirmed, rejected, undecided, pending.

- Confirmed and rejected SHALL count raw verdict references per rule. Coexisting classes SHALL each count in their own rule bucket.
- Undecided and pending SHALL count candidate pairings by state, bucketed by the candidate's rule.
- A pairing whose state is `undecided` SHALL NOT count as pending.

#### Scenario: A checked pairing leaves pending

- **WHEN** an exact-tier candidate pairing with no verdict gains one undecided verdict
- **THEN** the exact bucket's pending count SHALL decrease by one
- **AND** its undecided count SHALL increase by one

### Requirement: Nomination SHALL disclose undecided checks and filtered apply SHALL exclude them

An undecided pairing SHALL still be nominated. Every candidate row and ambiguity entry whose pairing holds undecided verdicts SHALL disclose the number of them on every face. The CLI filtered `--apply` of resolve-people SHALL exclude those candidates, list each excluded row with a pointer to per-work judgement, and SHALL exit non-zero without writing when every candidate is excluded. An explicit per-id apply SHALL write on every face; resolve-venues has no filtered batch apply on either face, so its list SHALL only disclose the count.

#### Scenario: Filtered apply skips a checked pairing

- **WHEN** the CLI runs `resolve-people --apply` and one exact-tier candidate holds an undecided verdict
- **THEN** that candidate SHALL NOT be applied
- **AND** the output SHALL list it as excluded because it was checked and left undecided

#### Scenario: MCP per-id apply writes a checked pairing

- **WHEN** the MCP face applies that candidate by its three-part id
- **THEN** the author slot SHALL be keyed and a confirmed verdict SHALL be written
- **AND** the undecided verdict SHALL remain

### Requirement: Undecided verdicts SHALL be written only through an explicit per-id leg

resolve-people and resolve-venues SHALL each provide an undecided leg on both the CLI and the MCP face. The leg SHALL take ids of the form `<citekey>:<index>:<entityKey>=<statement>` and an optional list of evidence digests that applies to every id in the call. The leg SHALL be called alone. It SHALL NOT be combined with apply, reject, judge, refute, split, un-split, drop, or attribute-org.

The whole batch SHALL be refused with zero writes when any of the following holds:

- an id is malformed or duplicated;
- a statement is blank;
- the judged entity does not exist;
- a digest is malformed;
- the store format is below 19;
- digests are given without any undecided id;
- the call carries more than 200 ids, more than 20 digests, or a statement longer than 4,096 bytes.

A single id SHALL be skipped and named, while the rest of the batch proceeds, when any of the following holds:

- the work does not exist or the index is out of range;
- the citekey cannot be uniquely located;
- the slot is not a literal;
- the pairing is already decided.

An id whose identical record already exists SHALL be reported as already recorded and SHALL NOT be written again.

#### Scenario: Recording undecided on an already decided pairing

- **WHEN** a pairing already holds a rejected verdict and the undecided leg names it
- **THEN** that id SHALL be skipped with a reason naming the existing decision
- **AND** no verdict SHALL be written for it

#### Scenario: Combining the undecided leg with apply

- **WHEN** a call passes both undecided ids and apply ids
- **THEN** the call SHALL be refused with zero writes

### Requirement: Per-work judgement SHALL coexist with an earlier nominated verdict

When a judge call names an author slot that is already keyed to the same person, and that person holds only a `nominated` confirmed verdict for the pairing, the judge SHALL write a `judged` confirmed verdict next to it and SHALL NOT modify the author slot. The literal SHALL be recovered from the existing verdict, and only when exactly one literal is recoverable. When a `judged` confirmed verdict with the same statement exists, the call SHALL be a no-op reported as already judged. When a `judged` confirmed verdict with a different statement exists, the id SHALL be skipped and named. A refute call SHALL behave the same way toward an existing `nominated` rejected verdict.

When a judge call names an author slot that is still a literal, the slot SHALL be assigned. When its judgement cannot be stored — because the store format is below 19 and a `nominated` verdict exists for the pairing, or because a `judged` verdict with a different statement already exists for the pairing, including one written earlier in the same call — the response row SHALL carry `verdictNotRecorded` with the reason. The same disclosure SHALL apply to attribute-org. A refute call whose judgement collides with a `judged` rejected verdict written earlier in the same call SHALL skip and name the id.

#### Scenario: Judge after apply

- **WHEN** `chen2020a` author slot 1 was applied to `chen-ch` and `--judge 'chen2020a:1:chen-ch=論文登記中研院統計所'` is run
- **THEN** `chen-ch` SHALL hold both the apply verdict and a `judged` confirmed verdict with that statement
- **AND** the author slot SHALL still be `.key("chen-ch")`

#### Scenario: Refute after reject

- **WHEN** a pairing holds a `nominated` rejected verdict from `--reject` and a refute call names it with a reason
- **THEN** the person SHALL hold both rejected verdicts

#### Scenario: Judgement that cannot be stored is disclosed

- **WHEN** `w1` author slots 0 and 1 are both the literal `C-H Chen`, slot 0 was judged to `chen-ch` with statement A, and slot 1 is judged to `chen-ch` with statement B
- **THEN** slot 1 SHALL become `.key("chen-ch")`
- **AND** the judged row for slot 1 SHALL carry `verdictNotRecorded` naming why statement B was not stored

### Requirement: Store format 19 SHALL gate the new verdict shapes

The supported store format SHALL be 19. The following writes SHALL require store format 19 or higher:

- writing an undecided verdict;
- writing a judged verdict that coexists with a nominated verdict for the same pairing.

A binary that supports only format 18 SHALL refuse to open a format-19 store.

#### Scenario: Undecided write on a format-18 store

- **WHEN** the undecided leg is called against a store whose marker is 18
- **THEN** the call SHALL be refused with zero writes and an error naming the required format
