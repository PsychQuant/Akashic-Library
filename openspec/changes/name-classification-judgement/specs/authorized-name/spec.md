## ADDED Requirements

### Requirement: Every name-classification judgement SHALL leave a judgement record

Each write surface that classifies a name — designating it as an authorized name, withdrawing that designation (on venues), or marking it as a variant — SHALL append one judgement reference to the record's references for every classification it asserts, including a restatement of a classification the record already holds. The reference SHALL carry the field of the partition it speaks about (`authorized` or `variant`), the name as its value, and a statement that begins with exactly one of three actions — designate (`指定：`), confirm (`確認：`), withdraw (`撤回：`) — followed by a non-empty reason. The three actions SHALL be a closed set parsed by a single parser; no fourth action SHALL be inferred.

A reason SHALL be required on every such surface; a call that would classify at least one non-blank name without a reason SHALL be refused as a whole with zero writes. The reason SHALL be at most 4,096 bytes. Evidence digests SHALL be optional, at most 20, and each SHALL be a valid, non-empty-content digest.

A change that the call causes without naming it SHALL also be recorded as a withdrawal: an authorized name displaced by a same-writing-system designation, and a name lifted out of the variant partition by a designation. The statement of such a record SHALL state the cause before the caller's reason.

A reference byte-identical to the latest name-classification record the record already holds for the same name and partition SHALL NOT be appended again. A record that repeats an earlier statement after an opposite action SHALL be appended, so that the latest record of a name always states the action that produced its current classification.

A reason SHALL contain at least one letter or digit and SHALL NOT begin with a combining mark, a format character, or a default-ignorable character. A single call SHALL classify at most 200 names; a call over the limit SHALL be refused as a whole with zero writes and without truncation.

#### Scenario: Designating a name writes one record

- **WHEN** a venue whose authorized list is empty is updated with `authorize: ["Psychometrika"]` and `judgement: "期刊官網刊頭"`
- **THEN** the venue SHALL hold exactly one new reference with field `authorized`, value `Psychometrika`, statement `指定：期刊官網刊頭`, and no evidence

#### Scenario: Restating an existing designation writes a confirmation

- **WHEN** a venue whose authorized list is `["Psychometrika"]` and which holds no judgement record is updated with `authorize: ["Psychometrika"]` and `judgement: "查證後確認"`
- **THEN** the venue SHALL hold a new reference with field `authorized`, value `Psychometrika`, and statement `確認：查證後確認`
- **AND** the authorized list SHALL be unchanged

#### Scenario: Designating again after a withdrawal with the same reason

- **WHEN** a venue designates `Some Journal` with reason `官網確認`, withdraws it with reason `查錯了`, and designates it again with reason `官網確認`
- **THEN** the venue SHALL hold three records for `Some Journal`, the last one `指定：官網確認`

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

### Requirement: The person names replacement SHALL record the authorized classification it changes

A partial update of a person that replaces its names SHALL require a reason when the replacement moves any name into or out of the authorized partition, and SHALL record only the names that move, on the `authorized` field: designate for a name entering and withdraw for a name leaving. A name that stays authorized SHALL get no record. A replacement that changes only the other names SHALL need no reason and SHALL record nothing; a reason given with a replacement that moves no name into or out of the authorized partition SHALL be refused as a whole with zero writes. An authorized name SHALL NOT leave the names altogether in a replacement, whether or not it carries a name-classification record: its withdrawal is recorded and the record is anchored to the names, so the replacement SHALL be refused as a whole with zero writes, and the refusal SHALL name the way out: keep the name among the other names with a reason, then delete it. A replacement that drops a name carrying a name-classification record SHALL be refused in the same way. A replacement SHALL NOT leave a person without any name. On a store whose format is below 22, these refusals SHALL also name the format gate and the upgrade path.

#### Scenario: Moving a name into the authorized partition without a reason

- **WHEN** a person whose names are all other names is updated so that one of them becomes authorized, with no reason
- **THEN** the call SHALL be refused
- **AND** the store SHALL be unchanged

#### Scenario: Correcting the spelling of an authorized name that has no record

- **WHEN** a person's authorized name `Quinn Q` has no name-classification record and the names are replaced with `Quin Q` authorized and `Quinn Q` absent, with a reason
- **THEN** the call SHALL be refused
- **AND** the store SHALL be unchanged
- **WHEN** the names are instead replaced with `Quin Q` authorized and `Quinn Q` among the other names, with the reason `改正拼寫`
- **THEN** `Quinn Q` SHALL hold the record `撤回：改正拼寫` and `Quin Q` the record `指定：改正拼寫`

#### Scenario: A reason with no authorized change

- **WHEN** a person's names are replaced with the same authorized names and a reason
- **THEN** the call SHALL be refused
- **AND** the store SHALL be unchanged

### Requirement: A name whose latest classification record is a withdrawal MAY be deleted together with its records

A venue, organization, or person name whose latest name-classification record, across both partitions, is a withdrawal SHALL be deletable together with all of its name-classification records. The deletion SHALL require a reason, which SHALL appear only in the report and SHALL NOT be written to the store, and SHALL require the record file to be committed and clean in git. A name whose latest record is not a withdrawal, or that has no record, or that still belongs to a partition, SHALL NOT be deleted this way, and the refusal SHALL name the way out for the name's situation: withdraw first, then delete, for a name still in a partition; designate it again and then withdraw it, for a name in no partition whose latest record is a designation or confirmation, including the swap and its cost when the writing system already has an authorized name; and, for a name with no record, the face that removes it on that entity or the steps that give it a withdrawal together with their cost. When the way out writes a record and the store format is below 22, the refusal SHALL also name the format gate. A deletion SHALL NOT leave the record without any name. On the command line, the person, organization, and venue deletions SHALL pass the target-store confirmation gate; a venue name-segment edit that only sets fields SHALL NOT.

#### Scenario: Deleting the only name of a person

- **WHEN** a person's only name is in the other names with the latest record a withdrawal, and that name is deleted with a reason
- **THEN** the call SHALL be refused
- **AND** the store SHALL be unchanged

#### Scenario: Deleting a mistyped name after it was displaced

- **WHEN** a venue designates the mistyped `Psychometrka`, designates `Some Journal` in the same writing system (which withdraws `Psychometrka`), and then removes the last segment of `Psychometrka` with a reason
- **THEN** `Psychometrka` SHALL no longer be a name of the venue
- **AND** its two name-classification records SHALL be gone

