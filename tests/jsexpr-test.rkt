#lang racket/base

(require rackunit
         racket/file
         racket/string
         json
         validate)

(test-case "to-jsexpr normalizes the usual suspects"
  (check-equal? (to-jsexpr 'news) "news")
  (check-equal? (to-jsexpr 'null) 'null)             ; stays JSON null
  (define a-keyword '#:kw)
  (check-equal? (to-jsexpr a-keyword) "kw")
  (check-equal? (to-jsexpr #\a) "a")
  (check-equal? (to-jsexpr (vector 1 'two)) (list 1 "two"))
  (check-equal? (to-jsexpr (list 'a "b" 3)) (list "a" "b" 3))
  (check-equal? (to-jsexpr (hash "name" 'x)) (hash 'name "x")))

(test-case "to-jsexpr rejects non-JSON with a clear error"
  (check-exn exn:fail:validate?
             (λ () (to-jsexpr (cons 1 2))))          ; dotted pair
  (struct point (x y) #:transparent)
  (check-exn exn:fail:validate?
             (λ () (to-jsexpr (point 1 2)))))

(test-case "jsexpr-encode round-trips through the json module"
  (check-equal? (jsexpr-encode (hasheq 'a 1 'b (list 'x #t)))
                "{\"a\":1,\"b\":[\"x\",true]}"))

(test-case "jsexpr-schema accepts decoded json"
  (define schema (jsexpr-schema (object #:fields (list (field 'name (string-schema))))))
  (define decoded (read-json (open-input-string "{\"name\":\"a\"}")))
  (check-equal? (parse schema decoded) (hasheq 'name "a")))

(test-case "jsexpr-schema rejects non-JSON shapes a schema would accept"
  (define schema (jsexpr-schema (any-schema)))
  (check-true (err? (parse-safe schema (hasheq 'k 'sym))))  ; symbol value
  (check-true (err? (parse-safe schema (list (cons 1 2))))) ; dotted pair
  (check-equal? (parse schema (list 1 "two" #t)) (list 1 "two" #t)))
