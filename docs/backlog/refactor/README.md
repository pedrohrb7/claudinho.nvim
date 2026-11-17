# Refactor backlog

Planned refactors that aren't urgent bugs but are worth doing deliberately, one file per refactor.

- File name: `YYYY-MM-DD-short-slug.md` (date opened, slug describing the refactor).
- Start every new entry from `TEMPLATE.md`.
- Update `Status` as it moves through `Proposed` -> `In progress` -> `Done` (link the PR) or `Dropped` (say why).
- If a refactor is large enough to need a design decision, write a spec first - a feature folder `../../features/<slug>/` with only `spec.md` (its **Source** points back to this entry) - and link it here instead of duplicating the reasoning. In a project still on the legacy layout, the spec goes in `../../specs/`.
- Keep the index below in sync whenever an entry is created or its status changes.

## Index

| Entry                                                                                                                                          | Status   |
| ---------------------------------------------------------------------------------------------------------------------------------------------- | -------- |
| [ClaudinhoSendCompleteData doc comment: stale README section and tag](2026-11-15-types-sendcomplete-doc-comment.md)                            | Proposed |
| [Em dash in pre-existing Lua comments](2026-11-17-em-dash-in-lua-comments.md)                                                                  | Proposed |
| [Leftovers of removed options in test setup and comments](2026-11-17-stale-removed-option-leftovers-in-tests.md)                               | Proposed |
| [Unit mocks of config.without_removed_options out of sync with the real signature](2026-11-17-unit-mocks-without-removed-options-signature.md) | Proposed |
