## MODIFIED Requirements

### Requirement: Shape labels SHALL be drawn from a closed set

The set of shape labels SHALL be closed. A record carrying a label that is not a known shape SHALL be quarantined, and the reason SHALL name the unrecognised label.

A record carrying no shape label SHALL be quarantined with a reason distinct from the unrecognised-label reason, because the two describe different mistakes.

Where the unrecognised label names something the project handles elsewhere, the reason SHALL say where it belongs. Naming a sign as unrecognised establishes only that it has no meaning in this position; a reader also needs to know the position in which it does have one.

Membership of the set SHALL change only by a recorded decision that the candidate selects a record shape, per the discriminating test the entity-boundary capability states. Closure is a property of how the set changes, not a claim that it is finished — a set that grows by argument is still closed against labels that arrive without one.

#### Scenario: A formal concept is proposed as a shape

- **WHEN** a file carries a label naming a formal concept such as a view
- **THEN** the file SHALL be quarantined
- **AND** the reason SHALL name that label as unrecognised, rather than reporting a generic classification failure
- **AND** the reason SHALL state where a definition of that kind does belong, so that the report distinguishes a misplaced sign from a meaningless one

#### Scenario: A record carries no label

- **WHEN** a file carries no shape label
- **THEN** the file SHALL be quarantined with a reason stating that the shape label is missing

#### Scenario: One unclassifiable record does not stop the load

- **WHEN** one file in the canonical entity namespace cannot be classified
- **THEN** the remaining files SHALL still load, and the unclassifiable file SHALL appear in the quarantine report

#### Scenario: A label admitted by the discriminating test is recognised

- **WHEN** a file carries a label that names a shape admitted to the set by a recorded shape-selection decision
- **THEN** the file SHALL be decoded as that shape rather than quarantined

##### Example: The identity-question shape

- **GIVEN** the label naming a record of an unresolved identity question, admitted because it determines its own fields and therefore its own decoder
- **WHEN** a file carrying that label is loaded
- **THEN** it SHALL be decoded as that shape
- **AND** re-encoding it SHALL produce a byte-identical file
