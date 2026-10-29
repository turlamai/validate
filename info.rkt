#lang info

(define collection "validate")
(define version "0.1")
(define deps '("base"))
(define build-deps '("scribble-lib" "racket-doc" "rackunit-lib"))
(define scribblings '(("scribblings/validate.scrbl" ())))
(define pkg-desc "Schema validation and typed JSON decoding for untrusted data")
(define license 'MIT)
(define pkg-authors '(turlamai))
(define test-omit-paths '("scribblings"))
