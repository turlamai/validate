#lang scribble/manual

@(require (for-label validate
                     racket/base)
          scribble/example)

@title{validate: Schema Validation and Typed JSON Decoding}
@defmodule[validate]

Schema validation for untrusted data — the zod workflow in Racket:
declare a schema once, parse with it everywhere, get verified values
or path-addressed errors. The killer application is the JSON boundary:
@racket[jsexpr-schema] gates decoded JSON before a schema looks at it,
and @racket[to-jsexpr] encodes everyday Racket data (symbols, keywords,
vectors, mutable hashes) without dying in a json-module contract.

@section{Parsing}

@defproc[(schema? [v any/c]) boolean?]

Recognizes schemas built by this library.

@defproc[(parse [s schema?] [v any/c]) any/c]

Validates @racket[v], returning the verified (possibly transformed)
value. On failure raises @racket[exn:fail:validate?] carrying every
error.

@defproc[(parse-safe [s schema?] [v any/c]) (or/c ok? err?)]

The non-raising form: @racket[(ok value)] or @racket[(err errors)].

@defstruct*[ok ([value any/c])]

@defstruct*[err ([errors (listof validate-error?)])]

@defstruct*[validate-error ([path (listof (or/c symbol? exact-integer? string?))]
                            [expected string?]
                            [got any/c]
                            [message string?])]

@racket[path] runs from the root: keys, then bracketed indices.
@defproc[(render-error [e validate-error?]) string?]
formats one, e.g. @racketresult["items.[1].title: expected a string (got: 99)"].

@defproc[(exn:fail:validate? [v any/c]) boolean?]

@defproc[(exn:fail:validate-errors [e exn:fail:validate?]) (listof validate-error?)]

@section{Schema combinators}

Every constructor is a function returning a @racket[schema?]; pass one
around, compose freely, recurse via @racket[lazy].

@defproc[(string-schema [#:min-length min-length (or/c exact-nonnegative-integer? #f) 0]
                        [#:max-length max-length (or/c exact-nonnegative-integer? #f) #f]
                        [#:pattern pattern (or/c regexp? #f) #f]) schema?]

@defproc[(int-schema [#:min min (or/c exact-integer? #f) #f]
                     [#:max max (or/c exact-integer? #f) #f]) schema?]

Exact integers only — @racket[3.0] is rejected.

@defproc[(real-schema [#:min min (or/c real? #f) #f]
                      [#:max max (or/c real? #f) #f]) schema?]

@defproc[(symbol-schema) schema?]
@defproc[(bytes-schema) schema?]
@defproc[(boolean-schema) schema?]
@defproc[(null-schema) schema?]
@defproc[(any-schema) schema?]

@defproc[(literal [v any/c]) schema?]
@defproc[(enum [choices (listof any/c)]) schema?]

@defproc[(list-of [s schema?]
                  [#:min-length min-length exact-nonnegative-integer? 0]
                  [#:max-length max-length (or/c exact-nonnegative-integer? #f) #f]) schema?]

Accepts lists, reports element errors as @racket[[index]]-addressed
paths.

@defproc[(vector-of [s schema?]) schema?]
@defproc[(tuple [schemas (listof schema?)]) schema?]

@defproc[(hash-of [key schema?] [value schema?]) schema?]

Open hashes; keys and values each validated.

@defstruct*[field ([key symbol?] [schema schema?] [optional? boolean?] [default any/c])]

@defproc[(field [key (or/c symbol? string?)] [s schema?]
                [#:optional optional? boolean? #f]
                [#:default default any/c #f]) field?]

@defproc[(object [#:fields fields (listof field?)]
                 [#:closed? closed? boolean? #f]) schema?]

The workhorse. Lookups accept string or symbol keys, from equal- or
eq-based hashes alike — JSON decoders and hand-built @racket[hasheq]s
both decode. Output is an immutable hash with symbol keys, containing
every declared field (optional ones filled with their default), so
downstream code can hash-ref without guards. Unknown keys are stripped;
with @racket[#:closed? #t] they become errors. Missing required fields
name the field in the error.

@defproc[(union [schemas (listof schema?)]) schema?]

First alternative without errors wins.

@defproc[(maybe [s schema?] [#:default default any/c #f]) schema?]

Maps @racket[#f] and JSON @racket['null] to @racket[default];
everything else goes through @racket[s].

@defproc[(refine [s schema?] [pred (-> any/c boolean?)] [message string?]) schema?]

@defproc[(map-schema [s schema?] [f (-> any/c any/c)]) schema?]

@defproc[(lazy [thunk (-> schema?)]) schema?]

Recursive schemas:

@racketblock[
(define tree
  (object #:fields
          (list (field 'value (int-schema))
                (field 'children (lazy (λ () (list-of tree)))
                       #:optional #t #:default '()))))]

@section{The JSON boundary}

@defproc[(jsexpr-schema [s schema?]) schema?]

Gates on JSON representability first, so input a schema would happily
accept (a symbol, a dotted pair) still gets rejected with a
JSON-shaped error.

@defproc[(to-jsexpr [v any/c]) json-value?]

Normalizes symbols, keywords, characters, vectors, proper pairs, and
mutable hashes into JSON-representable shapes; @racket['null] stays
JSON null; anything else (structs, dotted pairs) raises
@racket[exn:fail:validate?] with a message naming the culprit. Hash
keys normalize to symbols (what this Racket's @racket[write-json]
requires).

@defproc[(jsexpr-encode [v any/c]) string?]

@racket[(jsexpr->string (to-jsexpr v))].

@defproc[(json-value? [v any/c]) boolean?]

JSON representability, accepting string and symbol hash keys —
different Racket builds' @racket[read-json] disagree.
