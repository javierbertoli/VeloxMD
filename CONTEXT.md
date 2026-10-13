# VeloxMD Context

Glossary of domain terms used in VeloxMD.

## Document
A local Markdown file opened in the viewer. Supported extensions: `.md`, `.markdown`, `.mdc`, `.txt`.

## Link
A Markdown hyperlink in a Document. Classified by target:
- **Anchor link**: points to a Heading in the current Document (`#section`).
- **Document link**: points to another Document, optionally with an Anchor (`other.md#section`).
- **External link**: http(s), `mailto:`, or an existing local non-Document file; handed to the system default app.

## Anchor
Identifier of a Heading, derived GitHub-style: lowercase, punctuation stripped, spaces → `-`; repeated Headings get `-1`, `-2`, … suffixes. Matching is case-insensitive and URL-decoded.

## Heading
An ATX (`#`…`######`) or setext (`===`/`---` underline) heading in a Document. Navigation target for Anchors and the Table of Contents.

## Reachable
A Link target is Reachable when it resolves to an existing Document (or, for Anchor links, an existing Anchor). Unreachable targets produce a "Link target not found" notice.

## Navigation History
Ordered list of visited Documents (with scroll position) within one window. Following a Link (Document or Anchor) or a Table of Contents entry pushes onto it; Back returns to the previous entry and restores its scroll position.
