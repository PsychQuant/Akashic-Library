## ADDED Requirements

### Requirement: Every name-classification judgement SHALL leave a judgement record

Each write surface that classifies a name — designating it as an authorized name, withdrawing that designation (on venues), or marking it as a variant — SHALL append one judgement reference to the record's references for every classification it asserts, including a restatement of a classification the record already holds. The reference SHALL carry the field of the partition it speaks about (`authorized` or `variant`), the name as its value, and a statement that begins with exactly one of three actions — designate (`指定：`), confirm (`確認：`), withdraw (`撤回：`) — followed by a non-empty reason. The three actions SHALL be a closed set parsed by a single parser; no fourth action SHALL be inferred.

A reason SHALL be required on every such surface; a call that would classify at least one non-blank name without a reason SHALL be refused as a whole with zero writes. The reason SHALL be at most 4,096 bytes. Evidence digests SHALL be optional, at most 20, and each SHALL be a valid, non-empty-content digest.

A change that the call causes without naming it SHALL also be recorded as a withdrawal: an authorized name displaced by a same-writing-system designation, and a name lifted out of the variant partition by a designation. The statement of such a record SHALL state the cause before the caller's reason.

A reference byte-identical to one the record already holds SHALL NOT be appended again.

#### Scenario: Designating a name writes one record

- **WHEN** a venue whose authorized list is empty is updated with `authorize: ["Psychometrika"]` and `judgement: "期刊官網刊頭"`
- **THEN** the venue SHALL hold exactly one new reference with field `authorized`, value `Psychometrika`, statement `指定：期刊官網刊頭`, and no evidence

#### Scenario: Restating an existing designation writes a confirmation

- **WHEN** a venue whose authorized list is `["Psychometrika"]` and which holds no judgement record is updated with `authorize: ["Psychometrika"]` and `judgement: "查證後確認"`
- **THEN** the venue SHALL hold a new reference with field `authorized`, value `Psychometrika`, and statement `確認：查證後確認`
- **AND** the authorized list SHALL be unchanged

#### Scenario: A classification without a reason is refused

- **WHEN** a venue is updated with `authorize: ["Psychometrika"]` and no judgement
- **THEN** the call SHALL be refused
- **AND** the store SHALL be unchanged

##### Example: records per classification

| Call | Records appended |
| ---- | ---------------- |
| authorize X, X not authorized | authorized X `指定：R` |
| authorize X, X already authorized | authorized X `確認：R` |
| authorize X displaces same-script Y | authorized Y `撤回：同書寫系統改指定「X」——R` and authorized X `指定：R` |
| authorize X, X was a variant | variant X `撤回：改指定為 authorized——R` and authorized X `指定：R` |
| unauthorize X (venue) | authorized X `撤回：R` |
| add_variant X, X not a variant | variant X `指定：R` |
| add_variant X, X already a variant | variant X `確認：R` |

### Requirement: A name-classification record SHALL be anchored to the record's names

A name-classification record SHALL be accepted when its value is one of the names the record carries, whether or not the name currently belongs to the partition the record speaks about. The partition lists SHALL remain the classification of the record; the records SHALL be provenance and SHALL NOT be read as the classification.

A judgement reference on the `authorized` field whose statement does not follow the name-classification grammar SHALL keep its prior meaning: its value SHALL be an authorized name and it SHALL name at least one evidence digest. A judgement on the `authorized` or `variant` field with no evidence SHALL follow the name-classification grammar. The `variant` field SHALL carry only name-classification records, and SHALL be accepted only on venues.

#### Scenario: A withdrawal keeps its history

- **WHEN** a venue designates `Psychometrika` with a reason and is then updated with `unauthorize: ["Psychometrika"]` and another reason
- **THEN** the venue SHALL hold both records
- **AND** it SHALL load and validate while `Psychometrika` is no longer authorized

#### Scenario: A record names a string that is not a name of the record

- **WHEN** a record carries a name-classification record whose value is not one of its names
- **THEN** loading SHALL reject the record

##### Example: anchoring outcomes

| Record's names | authorized | Reference | Outcome |
| -------------- | ---------- | --------- | ------- |
| `Psychometrika`, `PSYCHOMETRIKA` | `Psychometrika` | authorized `PSYCHOMETRIKA` `撤回：…` | accepted |
| `Psychometrika` | (none) | authorized `Psychometrika` `指定：…` | accepted |
| `Psychometrika` | `Psychometrika` | authorized `Psychometrica` `指定：…` | rejected |
| `Psychometrika` | `Psychometrika` | authorized `Psychometrika` judgement `來源` with no evidence | rejected |

### Requirement: Writing a name-classification record SHALL require store format 22

The store format marker SHALL be raised to 22, because a reader built for format 21 rejects the file of any record carrying a name-classification record. A write of a person, organization, or venue carrying a name-classification record SHALL be refused, naming the required format, when the store's marker is below 22. The migration path that proposes authorized names SHALL NOT write the store format marker.

#### Scenario: Designating on a format-21 store

- **WHEN** a venue is updated with `authorize` and a reason on a store whose marker is 21
- **THEN** the call SHALL be refused with zero writes
- **AND** the message SHALL name store format 22

#### Scenario: The authorized-name migration on a store with nothing to write

- **WHEN** the migration path runs with an instruction to write and a reason on a store whose marker is 18 and whose people all designate an authorized name
- **THEN** the store format marker SHALL remain 18
