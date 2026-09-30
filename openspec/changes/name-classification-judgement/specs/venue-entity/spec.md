## ADDED Requirements

### Requirement: Venue name-classification legs SHALL require a reason and SHALL NOT share a call with the paginated judgement

`update-venue` and `akashic_update_venue` SHALL require the existing judgement parameter (`--judgement`, `judgement`) whenever the call carries at least one non-blank name in `add_variant`, `authorize`, or `unauthorize`; the existing evidence parameter (`--rests-on`, `rests_on`) SHALL be optional for these legs. A call that carries both a name-classification leg and the paginated judgement (`paginated` or `clear_paginated`) SHALL be refused, because the two judgements would share one reason. Both refusals SHALL happen before the store is read, after the existing name checks, so a malformed name keeps its existing message.

The venue records written by these legs are specified by the authorized-name capability. The `variant` field of a venue's references SHALL carry only those records. The removal face for venue references SHALL NOT remove a name-classification record, and SHALL name the classification legs as the way to change a classification.

#### Scenario: A variant marked with a reason

- **WHEN** a venue is updated with `add_variant: ["PSYCHOMETRIKA"]` and `judgement: "WoS 大寫形"`
- **THEN** `PSYCHOMETRIKA` SHALL be in the venue's variant list
- **AND** the venue SHALL hold a reference with field `variant`, value `PSYCHOMETRIKA`, and statement `指定：WoS 大寫形`

#### Scenario: Paginated and authorize in one call

- **WHEN** a venue is updated with `paginated: true`, `authorize: ["Psychometrika"]`, a judgement, and evidence
- **THEN** the call SHALL be refused with zero writes

#### Scenario: Removing a name-classification record

- **WHEN** the removal face is asked to remove the `authorized` reference whose value is a designated name and whose statement is `指定：期刊官網刊頭`
- **THEN** the call SHALL be refused with zero writes
- **AND** the message SHALL point to `--authorize` and `--unauthorize`
