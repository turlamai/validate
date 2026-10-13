# AGENTS.md

## What this is

`validate` — schema validation and typed JSON decoding for Racket.
Single-collection package (`validate` = collection = package name).
Family library line; the data-boundary counterpart to the protocol
libs (websocket, server-sent-events, feed).

## Layout

- `error.rkt` — validate-error/ok/err structs, exn:fail:validate,
  render-error; definitions BEFORE provide (contract-out struct quirk)
- `schema.rkt` — schema combinators; a schema is an opaque proc
  (value, path) → (cons validated errors)
- `jsexpr.rkt` — JSON boundary: to-jsexpr normalizer, jsexpr-encode,
  jsexpr-schema gate
- `main.rkt` — re-exports

## Invariants

- parse-safe NEVER throws; it collects every error in one pass. The
  object combinator must keep validating later fields after an earlier
  field fails — no early skip.
- Paths are root-first: `(append path (list seg))`, never cons.
- Object lookups scan-and-compare (string AND symbol keys, any hash
  flavor); never hash-ref into unknown key types.
- Object output always contains every declared field (optional filled
  with defaults) with symbol keys, in an immutable equal-based hash.
- `fail` is internal-only — the name collides with rackunit's.
- Primitives are 0-arg functions returning schemas (uniform with the
  parametrized ones).

## Conventions

- Code comments in English.

## Quality gates (before any release)

1. `raco test tests` — all green
2. `raco setup --check-pkg-deps -l validate` — zero violations
3. `raco setup -l validate` — docs build clean, zero undefined tags
