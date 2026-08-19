## ADDED Requirements

### Requirement: Name equality used for judgement SHALL admit no false positives

Wherever the system asserts that two names are the same and acts on that assertion by
discarding one of them, the equality criterion SHALL admit only differences that cannot
distinguish two real names. Surrounding whitespace and repeated whitespace within a name
SHALL NOT make two names distinct. Case, compatibility mappings, and punctuation
variants SHALL NOT be treated as equal for this purpose.

The criterion used for judgement SHALL be distinct from the criterion used for pairing.
Pairing may over-match because a person reviews the result; judgement has no reviewer
after it.

#### Scenario: Two names differ only by trailing whitespace

- **GIVEN** a record naming a person as `謝叔蓉` in one partition and `謝叔蓉 ` in the other
- **WHEN** the record is validated
- **THEN** the two SHALL be reported as occupying both partitions, as if they were written
  identically

#### Scenario: Two names differ only by repeated internal whitespace

- **GIVEN** a merge in which the surviving record already carries `Li  Ming` and the merged
  record carries `Li Ming`
- **THEN** the merged name SHALL NOT be added a second time

#### Scenario: Two names differ by letter case

- **GIVEN** a record carrying `Macdonald` in one partition and `MacDonald` in the other
- **WHEN** the record is validated
- **THEN** the two SHALL NOT be treated as the same name by the judgement criterion

##### Example: Why case is excluded

- **GIVEN** the judgement criterion is used to discard one of two names
- **WHEN** the only difference between them is letter case
- **THEN** discarding either one asserts an identity that the difference alone does not
  establish, so the criterion SHALL leave them distinct and the question SHALL be raised
  with a person instead

### Requirement: Near-duplicate names SHALL be surfaced rather than silently kept apart

Two names carried by the same record that the pairing criterion considers a match, but
that the judgement criterion considers distinct, SHALL be reported as an unresolved
question. They SHALL NOT be merged automatically, and they SHALL NOT be left unremarked.

The report SHALL be advisory: it SHALL NOT prevent the record from being written, because
the two names may genuinely be distinct.

#### Scenario: A record carries two spellings that differ only by hyphen variant

- **GIVEN** a record carrying both `Chang, Y-H.` and `Chang, Y‐H.` (U+2010)
- **WHEN** the record is validated
- **THEN** the validation SHALL report the pair as an unresolved near-duplicate, and the
  record SHALL still be writable

#### Scenario: A record carries two names that are unrelated

- **GIVEN** a record carrying both `鄭澈` and `Che Cheng`
- **WHEN** the record is validated
- **THEN** no near-duplicate SHALL be reported, because the pairing criterion does not
  match them either
