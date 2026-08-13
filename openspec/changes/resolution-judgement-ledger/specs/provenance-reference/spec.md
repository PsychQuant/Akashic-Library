## MODIFIED Requirements

### Requirement: A reference SHALL be attachable to a named field

A reference SHALL identify which assertion it supports. A record-level list of references that does not distinguish which field each reference supports SHALL NOT satisfy this requirement.

In addition to fields the record carries, exactly two resolution verdict fields SHALL be attachable: `resolution-confirmed` and `resolution-rejected`. This is a closed pair — no further virtual fields may be inferred from it. A verdict reference SHALL carry a `value` locating the judged pairing; the value is not a member of any record collection and SHALL NOT be subject to collection-membership validation.

#### Scenario: One record carries values from several sources

- **WHEN** a record's fields derive from different sources
- **THEN** each reference SHALL name the field it supports

##### Example: A person record with three sourced fields

| Field | Source | Reference names field |
| ----- | ------ | --------------------- |
| `profile.affiliations` | institute roster page | yes |
| `orcid` | ORCID public API | yes |
| `names` alias entry | manual adjudication | yes |

#### Scenario: A reference names a field the record does not carry

- **WHEN** a reference names a field absent from the record and the field is not a resolution verdict field
- **THEN** the store SHALL reject the record with an error naming the field

#### Scenario: A verdict reference without a value is rejected

- **WHEN** a reference names `resolution-confirmed` or `resolution-rejected` without a `value`
- **THEN** the store SHALL reject the record, since a verdict without its pairing is unanchored

### Requirement: A reference SHALL be able to record a judgement that is not a retrieval

Some assertions rest on reasoning over other evidence rather than on a single retrieval. A reference SHALL be able to record such a judgement, naming the evidence it rests on, without a URL or a content digest.

For resolution verdict fields (`resolution-confirmed` / `resolution-rejected`) only, the judgement MAY rest on no digests: a verdict is a primary human adjudication, not reasoning over stored evidence. When supporting evidence exists its digests SHOULD still be named. This exception is bound to the same closed field pair and SHALL NOT extend to any other field.

#### Scenario: A value is asserted on cross-referenced evidence

- **WHEN** a value is asserted because several retrieved sources agree
- **THEN** the reference SHALL record the reasoning and SHALL name the digests of the sources it rests on

##### Example: An identifier confirmed by corroboration

- **GIVEN** an ORCID record whose employment field names only a current institution
- **WHEN** the identifier is accepted because the work dates fall within a known tenure window, the subject matter matches, and one work is co-authored with a confirmed member of the same institution
- **THEN** the reference records that reasoning and names the digests of the ORCID record and of the co-author's page

#### Scenario: A judgement reference is given a content digest

- **WHEN** a judgement reference carries a content digest of its own
- **THEN** the store SHALL reject the record, because a judgement is not a retrieval and has no bytes of its own

#### Scenario: A resolution verdict rests on no digests

- **WHEN** a `resolution-confirmed` or `resolution-rejected` reference records a judgement with an empty rests-on list
- **THEN** the record SHALL be accepted, since the verdict itself is the primary adjudication

#### Scenario: A non-verdict judgement with empty rests-on is still rejected

- **WHEN** a judgement reference on any other field has an empty rests-on list
- **THEN** the store SHALL reject the record naming rests-on
