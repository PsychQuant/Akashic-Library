## ADDED Requirements

### Requirement: Organization name-classification legs SHALL require a reason

`update-organization` and `akashic_update_organization` SHALL accept a judgement (`--judgement`, `judgement`) and optional evidence digests (`--rests-on`, `rests_on`). The judgement SHALL be required whenever the call carries at least one non-blank name in `authorize` or `unauthorize`; evidence given without a judgement SHALL be refused. The records written are specified by the authorized-name capability; an organization SHALL accept name-classification records only on the `authorized` field. The response SHALL report how many records the call wrote.

#### Scenario: Designating an organization name with a reason

- **WHEN** organization `iss` is updated with `authorize: ["Institute of Statistical Science"]` and `judgement: "所方正式英文名稱"`
- **THEN** `Institute of Statistical Science` SHALL be authorized
- **AND** the organization SHALL hold a reference with field `authorized`, value `Institute of Statistical Science`, and statement `指定：所方正式英文名稱`
- **AND** the response SHALL report one record written

#### Scenario: Withdrawing without a reason

- **WHEN** organization `iss` is updated with `unauthorize: ["Institute of Statistical Science"]` and no judgement
- **THEN** the call SHALL be refused before the store is read
