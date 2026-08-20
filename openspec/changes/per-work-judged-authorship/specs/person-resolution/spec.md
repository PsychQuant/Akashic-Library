## MODIFIED Requirements

### Requirement: Two or more hits within the nominating tier SHALL be reported as ambiguity

When the nominating tier yields two or more distinct person keys, the resolver SHALL report an ambiguity carrying that tier instead of any candidate. Ambiguities SHALL NOT be applicable.

An ambiguity records that the *nominator* could not decide. It SHALL NOT be read as a claim that the occurrence is undecidable. An occurrence reported as an ambiguity SHALL remain eligible for a judged pairing (see "A judged pairing SHALL resolve one occurrence"), which is a separate input carrying evidence the nominator does not have.

Two sanctioned exits exist, and they SHALL be distinguished by the scope of the claim they express:

- **Verified alias promotion** — a claim that a spelling *is one of a person's names*. After human verification, the literal's correct spelling is recorded as a variant alias on the right person **together with a provenance reference documenting the verification**, whereupon the occurrence nominates at the exact tier and is applied explicitly. This claim is store-wide: every occurrence of that spelling is affected.
- **Judged pairing** — a claim that *this author position on this work* is this person. This claim is per-occurrence and SHALL NOT alter the alias set of any person.

Guidance surfaces SHALL NOT direct operators to add discriminator fields (ORCID, affiliation) as a way to change nomination — the matching key space is names only, and discriminators inform the human, not the resolver.

#### Scenario: Initials collision becomes ambiguity

- **GIVEN** a literal "C-H Chen" and two persons whose aliases reduce to the same family-plus-initials key
- **WHEN** resolution runs
- **THEN** an ambiguity with tier `initials` listing both person keys is reported and no candidate is produced for that occurrence

#### Scenario: An ambiguous occurrence remains eligible for judgement

- **GIVEN** an occurrence reported as an ambiguity in the preceding scenario
- **WHEN** a judged pairing naming that occurrence and one of the listed person keys is submitted
- **THEN** the occurrence SHALL be resolved to that person key
- **AND** no candidate SHALL have been produced for that occurrence by the resolver

## ADDED Requirements

### Requirement: A judged pairing SHALL resolve one occurrence and SHALL carry its judgement

A judged pairing SHALL identify exactly one occurrence by work citekey, author index, and the literal currently at that position, together with the person key it is judged to be, and a non-empty judgement text stating the basis for the decision.

A judged pairing SHALL NOT carry a nominating tier. Nomination expresses how a pairing was surfaced; a judged pairing was not surfaced by the resolver, and assigning it a tier would misreport its provenance.

A judged pairing with an empty or whitespace-only judgement SHALL NOT be constructible. The judgement is the record of why the decision was made; a pairing without one is indistinguishable from a guess.

A judged pairing SHALL NOT carry evidence references. Evidence for a decided identity belongs on the judged person's own references; verdicts SHALL NOT gain a second content pointer.

#### Scenario: A judged pairing without judgement text is rejected

- **WHEN** a judged pairing is submitted whose judgement text is empty or contains only whitespace
- **THEN** construction SHALL fail
- **AND** no entry SHALL be modified and no verdict SHALL be written

#### Scenario: A judged pairing resolves the named author position

- **GIVEN** a work whose author at the named index is the literal named by the pairing
- **WHEN** the judged pairing is applied
- **THEN** that author position SHALL become a key reference to the named person
- **AND** a resolution-confirmed verdict SHALL be written on that person carrying the submitted judgement text

### Requirement: A judged pairing SHALL be applied only when the named position still holds the named literal

Before writing, the named work SHALL exist, the named author index SHALL be within range, and the author at that index SHALL still be the literal named by the pairing. When any of these does not hold, that pairing SHALL be skipped and the skip SHALL be reported naming the pairing; it SHALL NOT be applied silently and it SHALL NOT abort the remaining pairings.

Applying the same judged pairing twice SHALL leave the store unchanged after the first application.

#### Scenario: The named position no longer holds the named literal

- **GIVEN** a judged pairing naming an author position whose literal has since changed
- **WHEN** the pairing is applied
- **THEN** that author position SHALL be left unchanged
- **AND** the skip SHALL be reported naming that pairing

#### Scenario: Re-applying a judged pairing changes nothing

- **GIVEN** a judged pairing that has already been applied
- **WHEN** the same pairing is applied again
- **THEN** the author position SHALL remain a key reference to the same person
- **AND** no duplicate verdict SHALL be appended to that person

### Requirement: A judgement SHALL nominate the same literal elsewhere, with its provenance visible

A verdict written by a judged pairing SHALL carry a rule identifier distinct from those used by tier-derived nominations, and that identifier SHALL satisfy the same lexical constraint as existing rule identifiers so that it is disclosed verbatim rather than replaced by a placeholder.

Occurrences of the same literal in other works SHALL be nominated at the confirmed-elsewhere tier on the strength of that verdict, and the nomination reason SHALL disclose the judged rule identifier. Such a nomination SHALL remain a nomination: it SHALL NOT be applied without the caller naming either the tier or the individual pairing.

#### Scenario: A judgement surfaces the same literal in another work

- **GIVEN** a literal judged to a person on one work
- **AND** another work carrying the same literal at some author position
- **WHEN** resolution runs
- **THEN** that other occurrence SHALL be nominated at the confirmed-elsewhere tier
- **AND** the nomination reason SHALL disclose the judged rule identifier

#### Scenario: A judgement-derived nomination is not swept into a bare apply

- **GIVEN** a nomination produced at the confirmed-elsewhere tier by a judgement
- **WHEN** an apply is requested without naming a tier and without naming that pairing
- **THEN** the apply SHALL be refused
