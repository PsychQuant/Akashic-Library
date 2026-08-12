## MODIFIED Requirements

### Requirement: Every proposition SHALL state at least one explicit project relation

Every proposition SHALL contain at least one project relation. Its status SHALL be one of implemented, partial, aspirational, analogy_only, rejected, not_applicable, or intentional_nonconformance. Its mode, when applicable, SHALL be one of instance, structural_invariant, semantic_operation, formal_derivation, refusal, shown_constraint, meta_elucidation, or declared_nonconformance. Every relation SHALL contain a Traditional Chinese claim and rationale.
Each rationale SHALL be proposition-specific: after whitespace normalization, a rationale SHALL NOT be reused by a different proposition.
Every aspirational relation SHALL be backed by at least one proposition history item whose kind is issue and whose reference is a complete GitHub issue URL of the exact path form `https://github.com/{owner}/{repo}/issues/{positive-integer}`. Extra path components, issue number zero, and negative issue numbers SHALL be rejected. The same issue SHALL be reusable only for relations that identify the same concrete engineering gap. Offline validation SHALL verify this structural trace without querying GitHub.

#### Scenario: Honest absence of a project mapping

- **WHEN** a proposition has no defensible Akashic counterpart
- **THEN** it SHALL use status not_applicable
- **AND** its rationale SHALL state why forcing an analogy would be misleading

##### Example: No engineering counterpart

- **GIVEN** a proposition whose subject is outside a software library's representational boundary
- **WHEN** no direct invariant, operation, refusal, or declared nonconformance exists
- **THEN** its relation SHALL use status `not_applicable` with a proposition-specific reason

#### Scenario: Invalid or incomplete relation is rejected

- **WHEN** a proposition has no relation, an unknown enum value, an empty claim, or an empty rationale
- **THEN** validation SHALL fail with invalid-relation

##### Example: Empty rationale

- **GIVEN** record `6.5` has one relation whose rationale is empty
- **WHEN** strict validation runs
- **THEN** it SHALL report `6.5:invalid-relation`

#### Scenario: A generic relation rationale is reused across propositions

- **WHEN** two different proposition records contain the same rationale after whitespace normalization
- **THEN** validation SHALL fail with duplicate-rationale
- **AND** the diagnostic SHALL direct the editor to explain each proposition's concrete philosophical content

##### Example: Reused explanation

- **GIVEN** records `5` and `5.1` contain the same whitespace-normalized rationale
- **WHEN** strict validation runs
- **THEN** both affected records SHALL be reported with `duplicate-rationale`

#### Scenario: An aspirational relation has no issue trace

- **WHEN** an aspirational relation has no history item containing a complete GitHub issue URL
- **THEN** validation SHALL fail with invalid-relation
- **AND** the diagnostic SHALL identify the affected proposition and require an issue history reference
- **AND** URL paths with extra components, issue number zero, or a negative issue number SHALL be treated as incomplete

##### Example: Untracked truth-function aspiration

- **GIVEN** record `5.101` has status `aspirational` and an empty history array
- **WHEN** strict validation runs
- **THEN** it SHALL report `5.101:invalid-relation` and require a GitHub issue history reference

#### Scenario: Related aspirations share a precise issue

- **WHEN** two or more aspirational relations describe the same concrete engineering gap
- **THEN** each relation SHALL retain proposition-specific claim and rationale text
- **AND** each containing proposition SHALL reference that gap's complete GitHub issue URL in history

##### Example: One precise issue traces a proposition family

- **GIVEN** records `5.1` and `5.101` both require truth-functional composition
- **WHEN** each record keeps distinct claim and rationale text
- **THEN** both histories SHALL be allowed to reference `https://github.com/PsychQuant/Akashic-Library/issues/204`
