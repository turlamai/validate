#lang racket/base

;; Validation results and errors.  A failed parse never throws inside
;; parse-safe: errors come back as (listof validate-error?) with a
;; path pointing at the offending position, e.g. "items.[1].title".

(require racket/contract
         racket/list
         racket/string)

;; path: keys (symbols/strings) and indices (integers) from the root.
(struct validate-error (path expected got message) #:transparent)

(struct ok (value) #:transparent)
(struct err (errors) #:transparent)

(struct exn:fail:validate exn:fail (errors) #:transparent)

(define (raise-validate-errors who errs)
  (define detail (string-join (map render-error errs) "; "))
  (raise (exn:fail:validate
          (format "~a: ~a" who detail)
          (current-continuation-marks)
          errs)))

(define (render-error e)
  (define p
    (string-join
     (for/list ([seg (in-list (validate-error-path e))])
       (if (exact-integer? seg) (format "[~a]" seg) (format "~a" seg)))
     "."))
  (format "~a~a~a"
          (if (string=? p "") "" (string-append p ": "))
          (validate-error-message e)
          (format " (got: ~a)" (format-got (validate-error-got e)))))

(define (format-got v)
  (define s (format "~s" v))
  (if (> (string-length s) 60) (string-append (substring s 0 60) "…") s))

(provide (contract-out
          [struct validate-error
            ([path (listof (or/c symbol? exact-integer? string?))]
             [expected string?]
             [got any/c]
             [message string?])]
          [render-error (-> validate-error? string?)]
          [struct ok ([value any/c])]
          [struct err ([errors (listof validate-error?)])]
          [exn:fail:validate? (-> any/c boolean?)]
          [exn:fail:validate-errors
           (-> exn:fail:validate? (listof validate-error?))]
          [exn:fail:validate
           (-> string? (or/c continuation-mark-set? #f)
               (listof validate-error?)
               exn:fail:validate?)])
         (rename-out [raise-validate-errors raise-validate-errors]))
