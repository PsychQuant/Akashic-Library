## MODIFIED Requirements

### Requirement: An organization SHALL be a record shape of its own

The canonical entity namespace SHALL admit organization records. An organization record SHALL be marked by a bare shape label, and that label SHALL be added to the closed set of known shapes.

The organization identity field MAY reuse the name used by another shape, because the label already determines the shape.

An organization record SHALL be able to record its own name variants and its own history, independently of any person or work that refers to it.

An organization record SHALL designate its outward-facing names by the same means as any other entity: an explicit subset of the names it carries, at most one per writing system. The name history SHALL be retained and SHALL remain orthogonal to that designation — renaming and writing system are independent axes, and an organization that has been renamed SHALL still be able to designate one outward-facing name per writing system among the names currently in force.

Resolving the outward-facing name of an organization SHALL proceed as for any other entity, with one additional step before the stable key: when no name is designated, the name currently in force SHALL be used. That step SHALL be retained because it is a query over the name history, not a reading of name order.

#### Scenario: An organization is stored and reloaded

- **WHEN** an organization record is written to the canonical entity namespace and reloaded
- **THEN** it SHALL be decoded as an organization on the strength of its shape label alone
- **AND** re-encoding it SHALL produce a byte-identical file

#### Scenario: An organization is renamed

- **WHEN** an organization's name changes while the organization continues to exist
- **THEN** the record SHALL retain both names with their validity ranges
- **AND** references from person records SHALL remain valid without being rewritten

#### Scenario: An organization designates one outward-facing name per writing system

- **WHEN** an organization carries both an ideographic name and a Latin name currently in force, and designates one of each as authorized
- **THEN** validation SHALL accept the record
- **AND** resolving its outward-facing name for the ideographic writing system SHALL yield the ideographic one

#### Scenario: A renamed organization designates only its current name

- **WHEN** an organization has been renamed and designates only the name currently in force
- **THEN** validation SHALL accept the record
- **AND** the superseded name SHALL remain recorded with its validity range

#### Scenario: An organization designates nothing

- **WHEN** an organization designates no authorized name
- **THEN** resolving its outward-facing name SHALL yield the name currently in force
- **AND** SHALL yield the stable key when no name is currently in force
