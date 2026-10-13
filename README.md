# validate

[![CI](https://github.com/turinglambdaai/validate/actions/workflows/ci.yml/badge.svg)](https://github.com/turinglambdaai/validate/actions/workflows/ci.yml)

Schema validation and typed JSON decoding for Racket. Declare a schema
once, parse untrusted data with it everywhere, get verified values or
path-addressed errors — the zod workflow, at the JSON boundary.

## Install

```
raco pkg install validate
```

## Use

```racket
(require validate)

(define post-schema
  (object #:fields
          (list (field 'title (string-schema #:min-length 1))
                (field 'kind (enum '("news" "paper" "github")))
                (field 'score (int-schema #:min 0 #:max 10) #:optional #t #:default 0)
                (field 'tags (list-of (string-schema)) #:optional #t #:default '()))))

(parse post-schema (some-untrusted-payload))
;; => '#hash((title . "...") (kind . "news") (score . 0) (tags . ()))

(parse-safe post-schema (hasheq 'title 99))
;; => (err (list (validate-error '(title) "a string" 99 ...)))

;; JSON boundary, both directions
(define payload (read-json (open-input-string body)))   ; untrusted
(define post (parse (jsexpr-schema post-schema) payload))
(jsexpr-encode (hasheq 'ok #t 'kind 'done))             ; symbols handled
```

- object lookups accept string or symbol keys, equal- or eq-based
  hashes — JSON decoders and hand-built `hasheq`s both decode
- errors carry paths from the root: `items.[1].title: expected a
  string (got: 99)`
- `parse-safe` collects every problem in one pass, `parse` raises them
  all at once
- `to-jsexpr`/`jsexpr-encode` normalize symbols, keywords, vectors and
  mutable hashes instead of dying in a json-module contract

## Development

```
raco pkg install --auto --link .
raco test tests
raco setup --check-pkg-deps -l validate
```

## License

[MIT](LICENSE)
