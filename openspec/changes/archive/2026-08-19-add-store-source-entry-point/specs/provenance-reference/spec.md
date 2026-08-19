## ADDED Requirements

### Requirement: Stored content SHALL be reachable through a user-facing entry point

Storing retrieved content SHALL be available through both the tool interface and the
command-line interface, and both SHALL reach the same implementation. An ability that
exists only as a library function is not available to a user of this system.

The response returned by either interface SHALL make visible whether the caller's
provenance description was discarded, and whether the stored bytes were verified as
excluded from version control.

#### Scenario: Content is stored for the first time

- **GIVEN** a store with no copy of the content
- **WHEN** the caller submits the bytes together with a provenance description
- **THEN** the response SHALL name the digest under which the content was stored, SHALL
  report that an index entry was created, and SHALL report whether exclusion from version
  control was verified

#### Scenario: The same content is submitted a second time with a different description

- **GIVEN** a store that already holds the content under its digest
- **WHEN** the caller submits identical bytes with a provenance description that differs
  from the recorded one
- **THEN** the response SHALL report that no index entry was created, and SHALL return the
  submitted description that was not written, so that the caller can distinguish "already
  recorded" from "your description was dropped"

##### Example: Re-submitting an institute page with a corrected note

- **GIVEN** the store holds the bytes of an institute page under digest `sha256:a1b2…`
  with the note `retrieved from the mirror`
- **WHEN** the caller submits the same bytes with the note `retrieved from the canonical host`
- **THEN** the response names digest `sha256:a1b2…`, reports no index entry created, and
  returns the note `retrieved from the canonical host` as the discarded description

#### Scenario: The stored bytes are not excluded from version control

- **GIVEN** a store whose ignore rules do not exclude the content directory
- **WHEN** the caller submits content
- **THEN** the write SHALL be refused, and the refusal SHALL name the unverified exclusion

#### Scenario: Both interfaces receive the same submission

- **GIVEN** identical bytes and an identical provenance description
- **WHEN** the submission is made through the tool interface, and separately through the
  command-line interface
- **THEN** both SHALL produce the same digest, and both SHALL report the same values for
  index-entry creation, exclusion verification, and discarded description
