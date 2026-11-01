## ADDED Requirements

### Requirement: Discovery never imports
The system SHALL emit candidates without store mutations. Only explicit user
selection of displayed stable IDs permits bootstrap verification and cites links.

#### Scenario: No selection
- WHEN a search produces candidates or a user only asks to continue searching
- THEN no bootstrap, link, library or store write occurs

### Requirement: Bounded, auditable OpenAlex query
The system SHALL use meta.count, explicit AND/OR semantics, inclusive year bounds,
cursor pagination and finite budgets. Each response SHALL have an observation time;
partial retrieval SHALL never be represented as complete.

#### Scenario: Count-only request
- WHEN the user supplies no narrowing criterion or explicit sort
- THEN request one result and report meta.count without emitting candidates

### Requirement: Methodology clues are not verdicts
The system SHALL retain uncertain candidates and separate text evidence from the
agent's methodological relevance judgement and the user's import decision.
