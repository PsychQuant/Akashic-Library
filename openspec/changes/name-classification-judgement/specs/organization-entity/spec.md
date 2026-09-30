## ADDED Requirements

### Requirement: The organization authorize leg SHALL require a reason

`update-organization` and `akashic_update_organization` SHALL accept a judgement (`--judgement`, `judgement`) and optional evidence digests (`--rests-on`, `rests_on`). The judgement SHALL be required whenever the call carries at least one non-blank name in `authorize`; a judgement or evidence given when the call carries no non-blank `authorize` name SHALL be refused. The organization update surface has no withdrawal leg (`unauthorize` was removed in #557 R1 verify, pending a ruling), so `authorize` is its only name-classification leg. The records written are specified by the authorized-name capability; an organization SHALL accept name-classification records only on the `authorized` field. The response SHALL report how many records the call wrote.

#### Scenario: Designating an organization name with a reason

- **WHEN** organization `iss` is updated with `authorize: ["Institute of Statistical Science"]` and `judgement: "所方正式英文名稱"`
- **THEN** `Institute of Statistical Science` SHALL be authorized
- **AND** the organization SHALL hold a reference with field `authorized`, value `Institute of Statistical Science`, and statement `指定：所方正式英文名稱`
- **AND** the response SHALL report one record written

#### Scenario: Designating without a reason

- **WHEN** organization `iss` is updated with `authorize: ["Institute of Statistical Science"]` and no judgement
- **THEN** the call SHALL be refused before the store is read

#### Scenario: Confirming an already authorized name writes a record

- **WHEN** organization `iss` authorizes `Institute of Statistical Science` with a judgement and is then updated with the same `authorize` and a different judgement
- **THEN** the organization SHALL hold a second reference with statement `確認：` followed by the second judgement
- **AND** the file SHALL be written, because the call recorded a new reference

#### Scenario: A reason with nothing to designate

- **WHEN** organization `iss` is updated with an empty `authorize` and a judgement
- **THEN** the call SHALL be refused with zero writes
