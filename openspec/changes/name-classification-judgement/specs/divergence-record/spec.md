## ADDED Requirements

### Requirement: A venue merge SHALL NOT demote an authorized name that carries a name-classification record

Resolving a venue divergence SHALL be refused, in preview and in apply alike, when a merged venue holds an authorized name that the merge would take out of the authorized partition and the merged venue holds any name-classification record on the `authorized` field for that name. The refusal SHALL name each such name with its latest record statement, and SHALL point to withdrawing the designation on the merged venue or designating the name on the survivor, both with a reason. A demotion of an authorized name that carries no such record SHALL remain a warning.

A name-classification record held by a merged venue SHALL be carried to the survivor, byte for byte, when its name's classification after the merge — in or out of the authorized partition, in or out of the variant partition — equals its classification on the merged venue. Otherwise the record would be lost, and the merge SHALL be refused, naming the name and both classifications. The classification SHALL be compared before any byte-identical record on the survivor is considered; a survivor that holds a byte-identical record but classifies the name differently SHALL NOT let the merge pass.

#### Scenario: A judged authorized name would be demoted

- **WHEN** merged venue `d` designates `Doomed Journal` with a record `指定：官網刊頭` and survivor `k` does not hold that name
- **THEN** the preview SHALL be refused naming `Doomed Journal` and `指定：官網刊頭`
- **AND** the store SHALL be unchanged

#### Scenario: A mechanical authorized name would be demoted

- **WHEN** merged venue `d` has `Doomed Journal` authorized with no name-classification record and survivor `k` does not hold that name
- **THEN** the merge SHALL proceed and report a warning about the demotion

#### Scenario: A withdrawal record whose classification agrees is carried

- **WHEN** merged venue `d` holds `Old Title` unclassified with a record `撤回：刊名已改` and the survivor does not hold that name
- **THEN** after the merge the survivor SHALL hold `Old Title` unclassified and the record byte for byte

### Requirement: A person merge SHALL carry a name-classification record whose classification agrees

Resolving a person divergence SHALL carry each name-classification record held by a merged person to the survivor, byte for byte, when the name is authorized on both or on neither, and SHALL report it among the carried references in preview and in apply alike. When the classifications differ, the merge SHALL be refused, naming the name, both classifications, and the way out.

#### Scenario: Twins designated by two batches

- **WHEN** person twins both hold the same authorized name, each with a designation record whose reason differs, and one is merged into the other
- **THEN** the merge SHALL proceed
- **AND** the survivor SHALL hold both records

