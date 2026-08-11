## ADDED Requirements

### Requirement: Affiliation ranges SHALL support fail-closed valid-day assessment

A person affiliation `DateRange` SHALL be assessable at one exact Gregorian `ValidDay` without using `TimelineOf.current` or `DateRange.overlaps`. Assessment SHALL distinguish definite containment, definite exclusion, temporal indeterminacy, and invalid temporal evidence. Bounded endpoints SHALL be inclusive. A year- or month-precision endpoint SHALL represent its complete possible day interval and SHALL NOT be silently replaced by its first or last day as a claimed fact.

#### Scenario: An exact bounded affiliation contains an interior day

- **WHEN** an affiliation range starts at `2020-01-01`, ends at `2020-12-31`, and is assessed at `2020-06-15`
- **THEN** the assessment SHALL be definite containment

#### Scenario: A coarse endpoint leaves its boundary indeterminate

- **WHEN** an affiliation starts at month precision `2020-06` and is assessed at `2020-06-15`
- **THEN** the assessment SHALL be temporal indeterminacy
- **AND** it SHALL NOT claim definite containment or exclusion

#### Scenario: A day after the latest possible coarse start is contained

- **WHEN** an open affiliation starts at month precision `2020-06` and is assessed at `2020-07-01`
- **THEN** the assessment SHALL be definite containment

#### Scenario: Unknown endpoints do not become infinities

- **WHEN** an affiliation has no start or has `endedUnknown` without a known applicable end
- **THEN** a non-excluded requested day SHALL be temporal indeterminacy
- **AND** unknown start SHALL NOT be treated as negative infinity
- **AND** unknown end SHALL NOT be treated as positive infinity

#### Scenario: An exact attestation establishes only its observed day

- **WHEN** an attested-only affiliation contains `2020-06-15`
- **THEN** assessment at `2020-06-15` SHALL be definite containment
- **AND** assessment at a different day SHALL NOT extend that observation into a range

#### Scenario: Contradictory or malformed evidence is invalid

- **WHEN** an affiliation mixes attested observations with start or end, contains an invalid Gregorian endpoint, or has an end definitely earlier than its start
- **THEN** the assessment SHALL be invalid temporal evidence
- **AND** it SHALL NOT be converted to a Boolean result
