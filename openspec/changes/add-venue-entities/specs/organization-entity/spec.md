## ADDED Requirements

### Requirement: Organization single-record MCP faces

Following the #304 adjudication transfer (org modeling restart, attribution units fully open), the MCP surface SHALL provide `akashic_add_organization` (single-record creation, add-person contract shape: explicit key, write-face closed exception form) and `akashic_resolve_organizations` (resolution with verdicts, resolve-people contract shape). Both SHALL be registered in the mcp-cli-parity adjudication tables alongside their existing CLI counterparts.

#### Scenario: Adding an organization via MCP

- **GIVEN** a valid key, names, and optional parent reference
- **WHEN** `akashic_add_organization` is called
- **THEN** an organization entity is created with a v4 UUID id, and the call is rejected if the key already exists

#### Scenario: Organization resolution follows literal-first promotion

- **GIVEN** person affiliation literals matching an organization's names
- **WHEN** `akashic_resolve_organizations` applies a confirmed match
- **THEN** the literal is promoted to a key reference and a resolution verdict is recorded
