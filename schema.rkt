#lang racket/base

;; Schema combinators.  A schema is an opaque procedure: input value +
;; path in, (cons validated-value errors) out.  A failed element
;; contributes errors and does not throw; parse-safe collects them all
;; so one pass reports every problem with its path.

(require racket/contract
         racket/list
         "error.rkt")

(provide (contract-out
          [schema? (-> any/c boolean?)]
          [make-schema (-> (-> any/c (listof (or/c symbol? exact-integer? string?))
                                 (cons/c any/c (listof validate-error?)))
                           schema?)]
          [run (-> schema? any/c (listof (or/c symbol? exact-integer? string?))
                   (cons/c any/c (listof validate-error?)))]
          [parse (-> schema? any/c any/c)]
          [parse-safe (-> schema? any/c (or/c ok? err?))]
          [string-schema (->* () (#:min-length exact-nonnegative-integer?
                                  #:max-length (or/c exact-nonnegative-integer? #f)
                                  #:pattern (or/c regexp? #f))
                             schema?)]
          [symbol-schema (-> schema?)]
          [bytes-schema (-> schema?)]
          [boolean-schema (-> schema?)]
          [int-schema (->* () (#:min (or/c exact-integer? #f)
                                #:max (or/c exact-integer? #f))
                           schema?)]
          [real-schema (->* () (#:min (or/c real? #f) #:max (or/c real? #f))
                            schema?)]
          [any-schema (-> schema?)]
          [null-schema (-> schema?)]
          [literal (-> any/c schema?)]
          [enum (-> (and/c pair? list?) schema?)]
          [list-of (->* (schema?)
                        (#:min-length exact-nonnegative-integer?
                         #:max-length (or/c exact-nonnegative-integer? #f))
                        schema?)]
          [vector-of (-> schema? schema?)]
          [tuple (-> (and/c pair? (listof schema?)) schema?)]
          [hash-of (-> schema? schema? schema?)]
          [field (->* ((or/c symbol? string?) schema?)
                      (#:optional boolean? #:default any/c)
                      field?)]
          [field? (-> any/c boolean?)]
          [object (->* (#:fields (listof field?))
                       (#:closed? boolean?)
                       schema?)]
          [union (-> (and/c pair? (listof schema?)) schema?)]
          [maybe (->* (schema?) (#:default any/c) schema?)]
          [refine (-> schema? (-> any/c boolean?) string? schema?)]
          [map-schema (-> schema? (-> any/c any/c) schema?)]
          [lazy (-> (-> schema?) schema?)]))

;; A schema wraps proc : (-> any/c path (cons/c any/c (listof validate-error?))).
;; The value half is meaningless when the error half is non-empty.
(struct schema (proc) #:reflection-name 'schema)

(define (schema-run s v path)
  ((schema-proc s) v path))

(define run schema-run)

;; For sibling modules that need to build schemas (jsexpr.rkt).
(define (make-schema proc) (schema proc))

(define (parse s v)
  (define result (schema-run s v '()))
  (unless (null? (cdr result))
    (raise-validate-errors 'parse (cdr result)))
  (car result))

(define (parse-safe s v)
  (define result (schema-run s v '()))
  (if (pair? (cdr result))
      (err (cdr result))
      (ok (car result))))

;; ---- helpers ---------------------------------------------------------------

(define (fail path expected got [message expected])
  (list (validate-error path expected got message)))

(define (pure v) (cons v '()))

(define ((pred-schema pred expected) v path)
  (if (pred v) (pure v) (cons #f (fail path expected v))))

;; ---- primitives ------------------------------------------------------------

(define (string-schema #:min-length [min-length 0]
                       #:max-length [max-length #f]
                       #:pattern [pattern #f])
  (schema
   (λ (v path)
     (cond
       [(not (string? v)) (cons #f (fail path "a string" v))]
       [(< (string-length v) min-length)
        (cons #f (fail path (format "a string of at least ~a character(s)" min-length) v))]
       [(and max-length (> (string-length v) max-length))
        (cons #f (fail path (format "a string of at most ~a character(s)" max-length) v))]
       [(and pattern (not (regexp-match? pattern v)))
        (cons #f (fail path (format "a string matching ~s" pattern) v))]
       [else (pure v)]))))

(define (symbol-schema) (schema (pred-schema symbol? "a symbol")))
(define (bytes-schema) (schema (pred-schema bytes? "a byte string")))
(define (boolean-schema) (schema (pred-schema boolean? "a boolean")))
(define (null-schema) (schema (pred-schema null? "null")))

(define (any-schema) (schema (λ (v path) (pure v))))

(define (int-schema #:min [min #f] #:max [max #f])
  (schema
   (λ (v path)
     (cond
       [(not (exact-integer? v)) (cons #f (fail path "an exact integer" v))]
       [(and min (< v min)) (cons #f (fail path (format "an integer >= ~a" min) v))]
       [(and max (> v max)) (cons #f (fail path (format "an integer <= ~a" max) v))]
       [else (pure v)]))))

(define (real-schema #:min [min #f] #:max [max #f])
  (schema
   (λ (v path)
     (cond
       [(not (real? v)) (cons #f (fail path "a real number" v))]
       [(and min (< v min)) (cons #f (fail path (format "a real >= ~a" min) v))]
       [(and max (> v max)) (cons #f (fail path (format "a real <= ~a" max) v))]
       [else (pure v)]))))

;; ---- simple combinators ------------------------------------------------------

(define (literal v)
  (schema (λ (got path)
            (if (equal? got v)
                (pure v)
                (cons #f (fail path (format "the literal value ~s" v) got))))))

(define (enum choices)
  (schema (λ (v path)
            (if (member v choices)
                (pure v)
                (cons #f (fail path (format "one of ~s" choices) v))))))

(define (list-of s #:min-length [min-length 0] #:max-length [max-length #f])
  (schema
   (λ (v path)
     (cond
       [(not (list? v)) (cons #f (fail path "a list" v))]
       [(< (length v) min-length)
        (cons #f (fail path (format "a list of at least ~a item(s)" min-length) v))]
       [(and max-length (> (length v) max-length))
        (cons #f (fail path (format "a list of at most ~a item(s)" max-length) v))]
       [else
        (define-values (vals errss)
          (for/lists (v1 v2)
                     ([item (in-list v)]
                      [i (in-naturals)])
            (define r (schema-run s item (append path (list i))))
            (values (car r) (cdr r))))
        (define errs (append* errss))
        (if (pair? errs) (cons #f errs) (pure vals))]))))

(define (vector-of s)
  (schema
   (λ (v path)
     (if (vector? v)
         (schema-run (list-of s) (vector->list v) path)
         (cons #f (fail path "a vector" v))))))

(define (tuple schemas)
  (define n (length schemas))
  (schema
   (λ (v path)
     (cond
       [(not (list? v)) (cons #f (fail path (format "a list of ~a element(s)" n) v))]
       [(not (= (length v) n))
        (cons #f (fail path (format "a list of exactly ~a element(s), got ~a" n (length v)) v))]
       [else
        (define-values (vals errss)
          (for/lists (v1 v2)
                     ([item (in-list v)]
                      [s (in-list schemas)]
                      [i (in-naturals)])
            (define r (schema-run s item (append path (list i))))
            (values (car r) (cdr r))))
        (define errs (append* errss))
        (if (pair? errs) (cons #f errs) (pure vals))]))))

(define (hash-of key-s value-s)
  (schema
   (λ (v path)
     (cond
       [(not (hash? v)) (cons #f (fail path "a hash" v))]
       [else
        (define-values (kvs errss)
          (for/lists (v1 v2)
                     ([(k val) (in-hash v)])
            (define rk (schema-run key-s k path))
            (define rv (schema-run value-s val (append path (list k))))
            (values (cons (car rk) (car rv))
                    (append (cdr rk) (cdr rv)))))
        (define errs (append* errss))
        (if (pair? errs) (cons #f errs) (pure (make-immutable-hash kvs)))]))))

;; ---- objects ------------------------------------------------------------------

(struct field-info (key schema optional? default) #:transparent)

(define field? field-info?)

(define (field key schema #:optional [optional? #f] #:default [default #f])
  (field-info (if (string? key) (string->symbol key) key) schema optional? default))

;; Object input hashes come from JSON decoders (string keys) and from
;; family code (symbol keys), from equal- and eq-based hashes alike —
;; so lookups scan and compare, never hash-ref into unknown key types
;; (hasheq + string keys is the classic cross-module bomb).  Returns
;; (cons #t value) when present — present-but-#f must not be confused
;; with absent.
(define (lookup-field v key-sym)
  (for/first ([(k val) (in-hash v)]
              #:when (or (equal? k key-sym)
                         (equal? k (symbol->string key-sym))))
    (cons #t val)))

(define (object #:fields fields #:closed? [closed? #f])
  (schema
   (λ (v path)
     (cond
       [(not (hash? v)) (cons #f (fail path "an object (hash)" v))]
       [else
        (define-values (out errs)
          (for/fold ([acc (hasheq)] [errs '()]) ([f (in-list fields)])
            (define key (field-info-key f))
            (define hit (lookup-field v key))
            (define r
              (cond
                [hit (schema-run (field-info-schema f)
                                 (cdr hit)
                                 (append path (list key)))]
                [(field-info-optional? f) (pure (field-info-default f))]
                [else
                 (cons #f
                       (list (validate-error
                              (append path (list key))
                              (format "field '~a'" key)
                              'missing
                              "missing required field")))]))
            (values (if (pair? (cdr r)) acc (hash-set acc key (car r)))
                    (append errs (cdr r)))))
        (cond
          [(pair? errs) (cons #f errs)]
          [(not closed?) (pure out)]
          [else
           (define known (map field-info-key fields))
           (define extra
             (for/first ([(k _) (in-hash v)]
                         #:unless (member (if (symbol? k) k (string->symbol (format "~a" k)))
                                          known))
               k))
           (if extra
               (cons #f (fail path
                              (format "an object with only the fields ~s" known)
                              v
                              (format "unknown field '~a'" extra)))
               (pure out))])]))))

;; ---- higher-order combinators --------------------------------------------------

(define (union schemas)
  (schema
   (λ (v path)
     (let loop ([ss schemas])
       (cond
         [(null? ss)
          (cons #f (fail path
                         (format "a value matching any of ~a union alternative(s)"
                                 (length schemas))
                         v
                         "no union alternative matched"))]
         [else
          (define r (schema-run (car ss) v path))
          (if (pair? (cdr r)) (loop (cdr ss)) r)])))))

(define (maybe s #:default [default #f])
  (schema
   (λ (v path)
     (cond
       ;; JSON null arrives as the symbol 'null; absent optional keys
       ;; never reach a schema (object handles defaults itself)
       [(or (not v) (eq? v 'null)) (pure default)]
       [else (schema-run s v path)]))))

(define (refine s pred message)
  (schema
   (λ (v path)
     (define r (schema-run s v path))
     (cond [(pair? (cdr r)) r]
           [(pred (car r)) r]
           [else (cons #f (fail path message (car r)))]))))

(define (map-schema s f)
  (schema
   (λ (v path)
     (define r (schema-run s v path))
     (if (pair? (cdr r)) r (cons (f (car r)) '())))))

;; Recursion needs lazy: a schema that contains itself.
(define (lazy thunk)
  (schema (λ (v path) (schema-run (thunk) v path))))
