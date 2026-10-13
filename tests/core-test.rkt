#lang racket/base

(require rackunit
         racket/list
         racket/string
         validate)

(test-case "primitives"
  (check-equal? (parse (string-schema) "hi") "hi")
  (check-equal? (parse (int-schema #:min 0 #:max 10) 7) 7)
  (check-equal? (parse (string-schema #:pattern #rx"^[a-z]+$") "abc") "abc")
  (check-equal? (parse (real-schema #:min 0.0) 1.5) 1.5)
  (check-equal? (parse (any-schema) (list 1 "two" 'three)) (list 1 "two" 'three))
  (check-equal? (parse (boolean-schema) #t) #t)
  (check-true (err? (parse-safe (int-schema) 1.5)))
  (check-true (err? (parse-safe (string-schema #:min-length 3) "ab"))))

(test-case "exact integers only"
  (check-true (err? (parse-safe (int-schema) 3.0)))  ; 3.0 is not exact
  (check-equal? (parse (int-schema) 3) 3))

(test-case "list-of reports element paths"
  (define r (parse-safe (list-of (string-schema)) (list "ok" 42 "fine")))
  (check-true (err? r))
  (define e (first (err-errors r)))
  (check-equal? (validate-error-path e) '(1))
  (check-true (string-contains? (render-error e) "[1]")))

(test-case "nested paths: items.0.title"
  (define schema
    (object #:fields
            (list (field 'items
                         (list-of (object #:fields (list (field 'title (string-schema)))))))))
  (define r (parse-safe schema (hasheq 'items (list (hasheq 'title "a")
                                                    (hasheq 'title 99)))))
  (check-true (err? r))
  (define e (first (err-errors r)))
  (check-equal? (validate-error-path e) '(items 1 title))
  (check-true (string-contains? (render-error e) "items.[1].title")))

(test-case "object: string and symbol keys both accepted"
  (define schema (object #:fields (list (field 'name (string-schema)))))
  (check-equal? (parse schema (hasheq 'name "a")) (hasheq 'name "a"))
  (check-equal? (parse schema (hash "name" "a")) (hasheq 'name "a")))

(test-case "object: present-but-false is not missing"
  (define schema (object #:fields (list (field 'flag (maybe (boolean-schema)) #:optional #t))))
  (check-equal? (parse schema (hasheq 'flag #f)) (hasheq 'flag #f))
  (check-equal? (parse schema (hasheq)) (hasheq 'flag #f)))

(test-case "object: optional with default"
  (define schema
    (object #:fields
            (list (field 'size (int-schema) #:optional #t #:default 10))))
  (check-equal? (parse schema (hasheq)) (hasheq 'size 10))
  (check-equal? (parse schema (hasheq 'size 3)) (hasheq 'size 3)))

(test-case "object: closed rejects unknown fields"
  (define schema
    (object #:fields (list (field 'a (any-schema))) #:closed? #t))
  (check-equal? (parse schema (hasheq 'a 1)) (hasheq 'a 1))
  (check-true (err? (parse-safe schema (hasheq 'a 1 'b 2))))
  (check-true (string-contains?
               (render-error (first (err-errors (parse-safe schema (hasheq 'a 1 'b 2)))))
               "unknown field 'b'")))

(test-case "object: missing required field names the field"
  (define schema (object #:fields (list (field 'name (string-schema)))))
  (check-true (err? (parse-safe schema (hasheq))))
  (check-true (string-contains?
               (render-error (first (err-errors (parse-safe schema (hasheq)))))
               "missing required field")))

(test-case "union takes the first matching branch"
  (define schema (union (list (int-schema) (string-schema))))
  (check-equal? (parse schema 5) 5)
  (check-equal? (parse schema "five") "five")
  (check-true (err? (parse-safe schema 1.5))))

(test-case "maybe maps #f and json null to the default"
  (define schema (maybe (string-schema) #:default "unset"))
  (check-equal? (parse schema #f) "unset")
  (check-equal? (parse schema 'null) "unset")
  (check-equal? (parse schema "x") "x"))

(test-case "literal and enum"
  (check-equal? (parse (literal "GET") "GET") "GET")
  (check-true (err? (parse-safe (literal "GET") "POST")))
  (check-equal? (parse (enum '("news" "paper")) "paper") "paper")
  (check-true (err? (parse-safe (enum '("news" "paper")) "blog"))))

(test-case "refine and map-schema"
  (define even-int (refine (int-schema) even? "an even integer"))
  (check-equal? (parse even-int 4) 4)
  (check-true (err? (parse-safe even-int 3)))
  (define len (map-schema (string-schema) string-length))
  (check-equal? (parse len "hello") 5))

(test-case "lazy allows recursive schemas"
  (define tree
    (object #:fields
            (list (field 'value (int-schema))
                  (field 'children (lazy (λ () (list-of tree))) #:optional #t #:default '()))))
  (define t (hasheq 'value 1 'children (list (hasheq 'value 2))))
  ;; optional fields with defaults always appear in the output
  (check-equal? (parse tree t)
                (hasheq 'value 1
                        'children (list (hasheq 'value 2 'children '())))))

(test-case "parse raises exn:fail:validate carrying all errors"
  (define schema
    (object #:fields
            (list (field 'a (string-schema))
                  (field 'b (string-schema)))))
  (check-exn exn:fail:validate?
             (λ () (parse schema (hasheq 'a 1 'b 2))))
  (define errs
    (exn:fail:validate-errors
     (with-handlers ([exn:fail:validate? values])
       (parse schema (hasheq 'a 1 'b 2))
       #f)))
  (check-equal? (length errs) 2))

(test-case "hash-of validates keys and values"
  (define schema (hash-of (symbol-schema) (int-schema)))
  (check-equal? (parse schema (hash 'a 1 'b 2)) (hash 'a 1 'b 2))
  (check-true (err? (parse-safe schema (hash 'a "x")))))

(test-case "tuple fixes arity"
  (check-equal? (parse (tuple (list (string-schema) (int-schema))) (list "a" 1))
                (list "a" 1))
  (check-true (err? (parse-safe (tuple (list (string-schema) (int-schema))) (list "a")))))
