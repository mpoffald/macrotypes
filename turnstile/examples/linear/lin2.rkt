#lang turnstile/quicklang

;; alternate implementation of linear λ-calculus
;; - when compared to lin.rkt
;; - all vars are linear
;; - uses generalized "expected-type" mechanism

;; TODO: add expected-ty version of rules

(require (for-syntax syntax/id-set))
(provide → λ #%app ann
         Bool if #%datum pair split free)

(define-base-type Bool)
(define-type-constructor → #:arity > 0)
(define-type-constructor × #:arity = 2)

;; some set operations on free ids
(begin-for-syntax
  (define (unused-err xs)
    (format "linear vars unused: ~a\n" (stx->datum xs)))
  (define (stx-subset? xs ys)
    (and (stx-list? xs) (stx-list? ys)
         (free-id-subset? (immutable-free-id-set (stx->list xs))
                          (immutable-free-id-set (stx->list ys)))))
  (define (stx-diff xs ys)
    (if (and (stx-list? xs) (stx-list? ys))
        (free-id-set->list
         (free-id-set-symmetric-difference
          (immutable-free-id-set (stx->list xs))
          (immutable-free-id-set (stx->list ys))))
        xs))
  (define (stx-set-sub xs ys)
    (free-id-set->list
     (free-id-set-subtract (immutable-free-id-set (stx->list xs))
                           (immutable-free-id-set (stx->list ys)))))
  (define (stx-cons x xs)
    (if (stx-e xs) (cons x xs) (list x)))
  )

; 'USED = prop name for used vars

(define-typed-variable-syntax
  #:name #%lin-var
  [(~and stx (#%var x- (~datum :) τ)) ⇐* USED used-vars ≫
   #:fail-when (and (stx-e #'used-vars) (stx-member #'x- #'used-vars))
               (format "attempting to use linear var twice: ~a" (stx->datum #'x-))
   #:with vars-out (stx-cons #'x- #'used-vars)
   ----------
   [⊢ x- (⇒ : τ) (⇒* USED vars-out)]])

(define-typed-syntax λ
  [(_ ([x:id (~datum :) τ_in:type] ...) e) ⇐* USED vars-in ≫
   [[x ≫ x- : τ_in.norm] ... ⊢ e ≫ e- (⇒ : τ_out) (⇒* USED used-vars)]
   #:do[(printf "bound vars: ~a\n" (stx->datum #'(x ...)))
        (printf "used vars: ~a\n" (stx->datum #'used-vars))]
   #:fail-unless (stx-subset? #'(x- ...) #'used-vars)
                 (unused-err (stx-diff #'(x- ...) #'used-vars))
   #:with rst (stx-set-sub #'used-vars #'(x- ...))
   -------
   [⊢ (λ- (x- ...) e-) (⇒ : (→ τ_in.norm ... τ_out))
                       (⇒* USED rst)]]
  ;; TODO: add used
  #;[(_ (x:id ...) e) ⇐ (~→ τ_in ... τ_out) ≫
   [[x ≫ x- : τ_in] ... ⊢ e ≫ e- ⇐ τ_out]
   ---------
   [⊢ (λ- (x- ...) e-)]])

(define-typed-syntax (#%app e_fn e_arg ...) ⇐* USED vars-in ≫
  [⊢ e_fn ≫ e_fn- (⇐* USED vars-in) (⇒* USED vars1) (⇒ : (~→ τ_in ... τ_out))]
  #:fail-unless (stx-length=? #'[τ_in ...] #'[e_arg ...])
                (num-args-fail-msg #'e_fn #'[τ_in ...] #'[e_arg ...])
;  [⊢ e_arg ≫ e_arg- ⇐ τ_in] (⇐⇒ USED vars1 vars-out) ...
  ;; TODO: invent turnstile syntax for this fold-infer op
  #:with [(e_arg- ...) vars-out]
  (for/fold ([es null] [used #'vars1])
            ([e (stx->list #'(e_arg ...))]
             [ety (stx->list #'(τ_in ...))])
    (define/with-syntax [e- τ] (infer+erase (attach e 'USED used)))
    (unless (typecheck? #'τ ety)
      (pretty-print (stx->datum #'τ))
      (pretty-print (stx->datum ety))
      (error "type error"))
    (values (cons #'e- es) (detach #'e- 'USED)))
;  [⊢ e_arg ≫ e_arg- (⇐* USED vars_i) (⇐ : τ_in) (⇒* USED vars_o)] ...
;  #:with vars-out (car (stx-reverse #'(vars_o ...)))
  --------
  [⊢ (#%app- e_fn- e_arg- ...) (⇒* USED vars-out) (⇒ : τ_out)])

(define-typed-syntax (ann e (~datum :) τ:type) ≫
  [⊢ e ≫ e- ⇐ τ.norm]
  --------
  [⊢ e- ⇒ τ.norm])

(define-typed-syntax (pair e1 e2) ⇐* USED vars-in ≫
  [⊢ e1 ≫ e1- (⇐* USED vars-in) (⇒ : τ1) (⇒* USED vars1)]
  [⊢ e2 ≫ e2- (⇐* USED vars1) (⇒ : τ2) (⇒* USED vars2)]
  -----------------
  [⊢ (#%app- cons- e1- e2-) (⇒ : (× τ1 τ2))
                            (⇒* USED vars2)])

(define-typed-syntax (split e (~datum as) (x y) (~datum in) body) ≫
  [⊢ e ≫ e- ⇒ (~× τx τy)]
  [[x ≫ x- : τx] [y ≫ y- : τy] ⊢ body ≫ body- ⇒ τ]
  -------------
  [⊢ (let*- ([p e-][x- (car p)][y- (cdr p)]) body-) ⇒ τ])

(define-typed-syntax (free e) ⇐* USED vars-in ≫
  [⊢ e ≫ e- (⇐* USED vars-in) (⇒* USED vars-out) (⇒ : τ)]
  -----------
  [⊢ e- (⇒ : τ) (⇒* USED vars-out)])

(define-typed-syntax #%datum
  [(_ . b:boolean) ≫
   --------
   [⊢ (#%datum- . b) ⇒ Bool]]
  [(_ . x) ≫
   --------
   [#:error (type-error #:src #'x #:msg "Unsupported literal: ~v" #'x)]])

(begin-for-syntax 
  (define current-join 
    (make-parameter 
      (λ (x y) 
        (unless (typecheck? x y)
          (type-error
            #:src x
            #:msg  "branches have incompatible types: ~a and ~a" x y))
        x))))

(define-syntax ⊔
  (syntax-parser
    [(⊔ τ1 τ2 ...)
     (for/fold ([τ ((current-type-eval) #'τ1)])
               ([τ2 (in-list (stx-map (current-type-eval) #'[τ2 ...]))])
       ((current-join) τ τ2))]))

(define-typed-syntax if
  [(_ e_tst e1 e2) ⇐ τ-expected ≫
   [⊢ e_tst ≫ e_tst- ⇒ _] ; Any non-false value is truthy.
   [⊢ e1 ≫ e1- ⇐ τ-expected]
   [⊢ e2 ≫ e2- ⇐ τ-expected]
   --------
   [⊢ (if- e_tst- e1- e2-)]]
  [(_ e_tst e1 e2) ⇐* USED vars-in ≫
   [⊢ e_tst ≫ e_tst- ⇒ _] ; Any non-false value is truthy.
   [⊢ e1 ≫ e1- ⇒ τ1]
   [⊢ e2 ≫ e2- ⇒ τ2]
   --------
   [⊢ (if- e_tst- e1- e2-) ⇒ (⊔ τ1 τ2)]])
