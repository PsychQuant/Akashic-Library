## MODIFIED Requirements

### Requirement: Formal concepts SHALL NOT occupy the canonical entity namespace

A *formal concept* is an expression whose role is to select, group, or index entities — a view, a classification, a query, a saved filter, or an index structure. A formal concept is recognised by what it fails to do: it determines no fields of its own, so the loader must decode it as some existing shape.

The canonical entity namespace (`entities/<uuid>.yaml`) SHALL contain only records that determine their own fields. Formal concepts SHALL NOT be stored there, and SHALL NOT be assigned an entity UUID.

The discriminating test SHALL be whether the candidate corresponds to a record shape — that is, whether it determines which fields exist and therefore which decoder the loader dispatches to. The test SHALL be stated independently of how a shape is marked in a file, because the marking mechanism may change while the criterion does not. Identity, a stable name, aliases, and a change history are necessary but NOT sufficient: an index schema version has all four and is not an entity.

Being referred to by other records SHALL NOT be required for admission, and grouping entities SHALL NOT by itself be grounds for refusal. Both criteria were previously implied by describing the admitted class as "something referred to in the world" and the refused class as anything that groups entities. Neither survives contact with the discriminating test: a record of an unresolved identity question groups two entities and is referred to by nothing, yet it determines its own fields and therefore selects its own decoder, while a view is referred to by configuration and still selects no shape. Where the earlier phrasing and the test disagree, the test SHALL govern — it is the criterion the loader actually enforces.

#### Scenario: A record that groups entities but selects its own shape is admitted

- **WHEN** a candidate groups two or more entities, is referred to by no other record, and determines a set of fields that no existing shape decodes
- **THEN** it SHALL be admitted, because the discriminating test asks what the loader must dispatch to, not what points at the record

##### Example: An unresolved identity question

- **GIVEN** a candidate whose fields are a question in words, a list of candidate entity references, and an optional judgment with its evidence
- **AND** that nothing in the store refers to it, and that it exists to group two entities
- **WHEN** the discriminating test is applied
- **THEN** it SHALL be admitted, because no existing decoder reads those fields
- **AND** the contrast with a view SHALL be recorded: a view groups entities too, but a view's fields are decodable as an existing shape, so no dispatch decision turns on it

## ADDED Requirements

### Requirement: Admissions to the entity namespace SHALL be recorded with their reasoning

When a candidate is admitted to the canonical entity namespace, the decision SHALL be recorded together with the reasoning that the discriminating test produced — which fields the candidate determines, and therefore which decoder it selects.

Recording the reasoning SHALL be required because the test is stated once but applied repeatedly; without the applications on record, a later contributor sees only a list of admitted shapes and cannot tell which of the necessary-but-insufficient criteria did the work. That is the inference the accompanying explainer records as incorrect.

A recorded admission SHALL cite the contrast that made the decision non-trivial — a candidate the test rejects for the same reason this one passes — so that the record teaches the test rather than merely reporting its outcome.

This requirement SHALL apply to admissions made after it takes effect. Shapes already in the set when it takes effect SHALL NOT be treated as incomplete for lacking such a record. The scoping is deliberate rather than an oversight: a requirement that declares the set retroactively incomplete on the day it lands says nothing about what anyone should do, and the reasoning for an earlier admission reconstructed years later is not the reasoning that was actually applied. Where an earlier admission's reasoning is wanted, it SHALL be recovered from that admission's own change rather than invented here.

#### Scenario: An admission is recorded with its reasoning

- **WHEN** a candidate is admitted to the canonical entity namespace
- **THEN** the record SHALL state which fields the candidate determines
- **AND** it SHALL cite a rejected candidate that fails the same test

##### Example: A record of an unresolved identity question is admitted

- **GIVEN** a candidate whose fields are a question in words, a list of candidate entity references, and an optional judgment with its evidence
- **WHEN** the discriminating test is applied
- **THEN** the candidate SHALL be admitted, because those fields exist only on this shape and the loader must dispatch to a decoder that reads them
- **AND** the record SHALL cite the view as the contrasting rejection: a view selects no shape of its own, so the loader would decode it as some existing shape, whereas this candidate cannot be decoded as any existing shape

#### Scenario: An admission without recorded reasoning is incomplete

- **WHEN** a shape is added to the known set with no recorded shape-selection reasoning
- **THEN** the addition SHALL be treated as incomplete, because the set's closure is a property of how it changes and an unargued addition does not exhibit that property
