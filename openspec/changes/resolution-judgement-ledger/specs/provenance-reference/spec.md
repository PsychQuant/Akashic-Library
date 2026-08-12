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
