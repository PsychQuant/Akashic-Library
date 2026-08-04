## ADDED Requirements

### Requirement: Admissions to the entity namespace SHALL be recorded with their reasoning

When a candidate is admitted to the canonical entity namespace, the decision SHALL be recorded together with the reasoning that the discriminating test produced — which fields the candidate determines, and therefore which decoder it selects.

Recording the reasoning SHALL be required because the test is stated once but applied repeatedly; without the applications on record, a later contributor sees only a list of admitted shapes and cannot tell which of the necessary-but-insufficient criteria did the work. That is the inference the accompanying explainer records as incorrect.

A recorded admission SHALL cite the contrast that made the decision non-trivial — a candidate the test rejects for the same reason this one passes — so that the record teaches the test rather than merely reporting its outcome.

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
