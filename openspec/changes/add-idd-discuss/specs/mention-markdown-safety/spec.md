## ADDED Requirements

### Requirement: Verified code boundaries only
The shared mention gate SHALL use the maintained pinned Markdown parser to recognize code regions. Unmatched inline delimiters, misleading closing-fence info strings, and GFM table boundaries SHALL NOT exempt live mention text. Ambiguous or unrepresented source SHALL remain in the scan.

#### Scenario: False fence close
- **WHEN** a fenced block contains an apparent closing delimiter with an info suffix followed by a valid closing fence and an unattested mention
- **THEN** the trailing mention remains subject to the gate and publication is refused

#### Scenario: Table divides apparent inline code
- **WHEN** a GFM table cell boundary divides backtick delimiters surrounding a mention
- **THEN** the mention is not exempted as a cross-cell code span

### Requirement: Original non-code bytes and conservative failure
Entity spelling and non-code source boundaries SHALL be preserved for the existing mechanical checks. Parser absence, incompatible version, or failure SHALL refuse dispatch. Code removal SHALL NOT concatenate adjacent text into a spurious URL or email exemption.

#### Scenario: Parser is missing
- **WHEN** the pinned dependency cannot be loaded
- **THEN** the helper reports the required dependency and no gh dispatch occurs

### Requirement: Fidelity across body sources and URL boundaries
The wrapper SHALL reject NUL-bearing body files before conversion to shell strings and SHALL parse each body source independently. URL exemptions SHALL stop at the GFM less-than boundary.

#### Scenario: Multiple body flags contain separate code delimiters
- **WHEN** an earlier body argument opens a code fence and a later body contains an unattested mention
- **THEN** the later body is checked independently and dispatch is refused

#### Scenario: NUL would change Markdown syntax in shell substitution
- **WHEN** a readable body file contains NUL bytes
- **THEN** the wrapper refuses before loading the content into a Bash variable

#### Scenario: Mention follows less-than after a URL
- **WHEN** a raw or entity-encoded mention follows `<` after an otherwise valid URL
- **THEN** the mention is not removed with the URL

### Requirement: Positive bounded URL exemptions
Only URL ranges identified by the maintained recognizer in the original inline source, with supported GFM prefix and complete hostname checks, SHALL be exempted. URL-like substrings with invalid prefixes or domains and ambiguous HTML/table contexts SHALL remain in the scan.

#### Scenario: Non-link URL-shaped text
- **WHEN** a body contains `xhttps://example.org/` or an underscore-bearing domain followed by an unattested mention
- **THEN** the mention remains subject to refusal rather than being deleted by a URL prefix match
