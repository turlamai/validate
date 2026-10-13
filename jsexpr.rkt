#lang racket/base

;; The JSON boundary.  Encode side: to-jsexpr turns everyday Racket
;; data (symbols, keywords, vectors, mutable hashes, proper pairs)
;; into a JSON-representable shape instead of dying in a json-module
;; contract.  Decode side: jsexpr-schema gates untrusted input on JSON
;; representability before a schema looks at it.

(require racket/contract
         json
         "error.rkt"
         "schema.rkt")

(provide (contract-out
          [json-value? (-> any/c boolean?)]
          [to-jsexpr (-> any/c json-value?)]
          [jsexpr-encode (-> any/c string?)]
          [jsexpr-schema (-> schema? schema?)]))

;; JSON-representable, accepting BOTH string and symbol hash keys:
;; different Racket builds' read-json disagree, family code builds
;; hasheq with symbol keys, and both must decode.
(define (json-value? v)
  (or (string? v)
      (boolean? v)
      (real? v)
      (null? v)
      (eq? v 'null)
      (and (list? v) (andmap json-value? v))
      (and (hash? v)
           (for/and ([(k val) (in-hash v)])
             (and (or (symbol? k) (string? k))
                  (json-value? val))))))

;; 'null is jsexpr's null and passes through untouched; every other
;; symbol becomes a string.
(define (to-jsexpr v)
  (cond
    [(or (null? v) (boolean? v) (string? v)
         (real? v) (eq? v 'null))
     v]
    [(symbol? v) (symbol->string v)]
    [(keyword? v) (keyword->string v)]
    [(char? v) (string v)]
    [(pair? v)
     (if (list? v)
         (map to-jsexpr v)
         (raise-not-json v "a dotted pair"))]
    [(vector? v) (map to-jsexpr (vector->list v))]
    [(hash? v)
     (for/hash ([(k val) (in-hash v)])
       (values (hash-key k) (to-jsexpr val)))]
    [else (raise-not-json v (describe v))]))

;; 9.3's write-json only accepts symbol keys, so normalize all keys to
;; symbols; that also matches this build's read-json output shape.
(define (hash-key k)
  (cond [(symbol? k) k]
        [(string? k) (string->symbol k)]
        [(keyword? k) (string->symbol (keyword->string k))]
        [else (raise-not-json k "a non-string hash key")]))

(define (describe v)
  (with-handlers ([exn:fail? (λ (_) "an opaque value")])
    (define n (object-name v))
    (if n (format "~s" n) "an opaque value")))

(define (raise-not-json v what)
  (raise (exn:fail:validate
          (format "to-jsexpr: ~a is not JSON-representable: ~a" (format-value v) what)
          (current-continuation-marks)
          (list (validate-error '() "a JSON value" v (format "not JSON-representable (~a)" what))))))

(define (format-value v)
  (define s (format "~s" v))
  (if (> (string-length s) 50) (string-append (substring s 0 50) "…") s))

(define (jsexpr-encode v)
  (jsexpr->string (to-jsexpr v)))

;; Gate on JSON representability first, so untrusted input that a
;; schema would happily accept (e.g. symbols) still gets rejected with
;; a JSON-shaped error.
(define (jsexpr-schema s)
  (make-schema
   (λ (v path)
     (if (json-value? v)
         (run s v path)
         (cons #f
               (list (validate-error path "a JSON-representable value" v
                                     "not a JSON-representable value")))))))
