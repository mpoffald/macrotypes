#lang turnstile/lang

; second attempt at a basic dependently-typed calculus
; initially copied from dep.rkt

; Π  λ ≻ ⊢ ≫ → ∧ (bidir ⇒ ⇐) τ⊑

(provide (rename-out [#%type *])
         Π → ∀
         = eq-refl eq-elim
         Nat (rename-out [Zero Z][Succ S]) nat-ind #;nat-rec
         λ (rename-out [app #%app]) ann
         define define-type-alias
)

;; TODO:
;; - map #%datum to S and Z
;; - rename define-type-alias to define
;; - add "assistant" part
;; - provide match and match/lambda so nat-ind can be fn
;;   - eg see https://gist.github.com/AndrasKovacs/6769513
;; - add dependent existential
;; - remove debugging code?

;; #;(begin-for-syntax
;;   (define old-ty= (current-type=?))
;;   (current-type=?
;;    (λ (t1 t2)
;;      (displayln (stx->datum t1))
;;      (displayln (stx->datum t2))
;;      (old-ty= t1 t2)))
;;   (current-typecheck-relation (current-type=?)))

;(define-syntax-category : kind) ; defines #%kind for #%type

;; set Type : Type
;; alternatively, could define new base type Type,
;; and make #%type typecheck with Type
(begin-for-syntax
  (define debug? #f)
  (define type-eq-debug? #f)
  (define debug-match? #f)

  ;; TODO: fix `type` stx class
  ;; (define old-type? (current-type?))
  ;; (current-type?
  ;;  (lambda (t) (or (#%type? t) (old-type? t))))
  (define old-relation (current-typecheck-relation))
  (current-typecheck-relation
   (lambda (t1 t2)
     (when type-eq-debug?
       (pretty-print (stx->datum t1))
       (pretty-print (stx->datum t2)))
     ;; assumed #f can only come from (typeof #%type)
     ;; (so this wont work when interacting with untyped code)
     (or (and (false? (syntax-e t1)) (#%type? t2)) ; assign Type : Type
         (old-relation t1 t2)))))
(define-for-syntax Type ((current-type-eval) #'#%type))

(define-internal-type-constructor →) ; equiv to Π with no uses on rhs
(define-internal-binding-type ∀)     ; equiv to Π with #%type for all params

;; Π expands into combination of internal →- and ∀-
;; uses "let*" syntax where X_i is in scope for τ_i+1 ...
;; TODO: add tests to check this
(define-typed-syntax (Π ([X:id : τ_in] ...) τ_out) ≫
  ;; TODO: check that τ_in and τ_out have #%type?
  [[X ≫ X- : τ_in] ... ⊢ [τ_out ≫ τ_out- ⇐ #%type] [τ_in ≫ τ_in- ⇐ #%type] ...]
  -------
  [⊢ (∀- (X- ...) (→- τ_in- ... τ_out-)) ⇒ #%type])

;; abbrevs for Π
;; (→ τ_in τ_out) == (Π (unused : τ_in) τ_out)
(define-simple-macro (→ τ_in ... τ_out)
  #:with (X ...) (generate-temporaries #'(τ_in ...))
  (Π ([X : τ_in] ...) τ_out))
;; (∀ (X) τ) == (∀ ([X : #%type]) τ)
(define-simple-macro (∀ (X ...)  τ)
  (Π ([X : #%type] ...) τ))

;; pattern expanders
(begin-for-syntax
  (define-syntax ~Π
    (pattern-expander
     (syntax-parser
       [(_ ([x:id : τ_in] ... (~and (~literal ...) ooo)) τ_out)
        #'(~∀ (x ... ooo) (~→ τ_in ... ooo τ_out))]
       [(_ ([x:id : τ_in] ...)  τ_out)
        #'(~∀ (x ...) (~→ τ_in ... τ_out))]))))

;; equality -------------------------------------------------------------------
(define-internal-type-constructor =)
(define-typed-syntax (= t1 t2) ≫
  [⊢ t1 ≫ t1- ⇒ ty]
  [⊢ t2 ≫ t2- ⇐ ty]
  ;; #:do [(printf "t1: ~a\n" (stx->datum #'t1-))
  ;;       (printf "t2: ~a\n" (stx->datum #'t2-))]
;  [t1- τ= t2-]
  ---------------------
  [⊢ (=- t1- t2-) ⇒ #%type])

;; Q: what is the operational meaning of eq-refl?
(define-typed-syntax (eq-refl e) ≫
  [⊢ e ≫ e- ⇒ _]
  ----------
  [⊢ (#%app- void-) ⇒ (= e- e-)])

;; eq-elim: t : T
;;          P : (T -> Type)
;;          pt : (P t)
;;          w : T
;;          peq : (= t w)
;;       -> (P w)
(define-typed-syntax (eq-elim t P pt w peq) ≫
  [⊢ t ≫ t- ⇒ ty]
  [⊢ P ≫ P- ⇐ (→ ty #%type)]
  [⊢ pt ≫ pt- ⇐ (app P- t-)]
  [⊢ w ≫ w- ⇐ ty]
  [⊢ peq ≫ peq- ⇐ (= t- w-)]
  --------------
  [⊢ pt- ⇒ (app P- w-)])

;; lambda and #%app -----------------------------------------------------------

;; TODO: fix `type` stx class
(define-typed-syntax λ
  ;; expected ty only
  [(_ (y:id ...) e) ⇐ (~Π ([x:id : τ_in] ... ) τ_out) ≫
   ;; must use free-identifier=? to work with prove/define and `?`
   [[x ≫ x- : τ_in] ... ⊢ #,(substs #'(x ...) #'(y ...) #'e free-identifier=?) ≫ e- ⇐ τ_out]
   ---------
   [⊢ (λ- (x- ...) e-)]]
  ;; both expected ty and annotations
  [(_ ([y:id : τ_in*] ...) e) ⇐ (~Π ([x:id : τ_in] ...) τ_out) ≫
;  [(_ ([y:id : τy_in:type] ...) e) ⇐ (~Π ([x:id : τ_in] ...) τ_out) ≫
   #:fail-unless (stx-length=? #'(y ...) #'(x ...))
                 "function's arity does not match expected type"
   [⊢ τ_in* ≫ τ_in** ⇐ #%type] ...
;   #:when (typechecks? (stx-map (current-type-eval) #'(τ_in* ...))
   #:when (typechecks? #'(τ_in** ...) #'(τ_in ...))
;   #:when (typechecks? #'(τy_in.norm ...) #'(τ_in ...))
;   [τy_in τ= τ_in] ...
   [[x ≫ x- : τ_in] ... ⊢ #,(substs #'(x ...) #'(y ...) #'e) ≫ e- ⇐ τ_out]
   -------
   [⊢ (λ- (x- ...) e-)]]
  ;; annotations only
  [(_ ([x:id : τ_in] ...) e) ≫
   [[x ≫ x- : τ_in] ... ⊢ [e ≫ e- ⇒ τ_out] [τ_in ≫ τ_in- ⇒ _] ...]
   -------
   [⊢ (λ- (x- ...) e-) ⇒ (Π ([x- : τ_in-] ...) τ_out)]])

;; ;; classes for matching number literals
;; (begin-for-syntax
;;   (define-syntax-class nat
;;     (pattern (~or n:exact-nonnegative-integer (_ n:exact-nonnegative-integer))
;;              #:attr val
;;              #'n))
;;   (define-syntax-class nats
;;     (pattern (n:nat ...) #:attr vals #'(n.val ...)))
;;   ; extract list of quoted numbers
;;   (define stx->nat (syntax-parser [n:nat (stx-e #'n.val)]))
;;   (define (stx->nats stx) (stx-map stx->nat stx))
;;   (define (stx+ ns) (apply + (stx->nats ns)))
;;   (define (delta op-stx args)
;;     (syntax-parse op-stx
;;       [(~literal +-) (stx+ args)]
;;       [(~literal zero?-) (apply zero? (stx->nats args))])))

;; TODO: fix orig after subst, for err msgs
;; app/eval should not try to ty check anymore
(define-syntax app/eval
  (syntax-parser
    #;[(_ f . args) #:do[(printf "app/evaling ")
                       (printf "f: ~a\n" (stx->datum #'f))
                       (printf "args: ~a\n" (stx->datum #'args))]
     #:when #f #'void]
    [(_ f:id n P zc sc)
     #:with (_ m/d . _) (local-expand #'(#%app match/delayed 'do 'nt 'ca 're) 'expression null)
     #:when (free-identifier=? #'m/d #'f)
     ;; TODO: need to attach type?
     #'(match/nat n P zc sc)]
    ;; TODO: apply to only lambda args or all args?
    [(_ (~and f ((~literal #%plain-lambda) (x ...) e)) e_arg ...)
     #:do[(when debug?
            (printf "apping: ~a\n" (stx->datum #'f))
            (printf "args\n")
            (pretty-print (stx->datum #'(e_arg ...)))
            (printf "expected type\n")
            (pretty-print (stx->datum (typeof this-syntax))))]
;     #:with (~Π ([X : _] ...) τ_out) (typeof #'f) ; must re-subst in type
     ;; TODO: need to replace all #%app- in this result with app/eval again
     ;; and then re-expand
;     #:with ((~literal #%plain-app) newf . newargs) #'e
 ;    #:do[(displayln #'newf)(displayln #'newargs)(displayln (stx-car #'e+))]
     #:with r-app (datum->syntax (if (identifier? #'e) #'e (stx-car #'e)) '#%app)
     ;; TODO: is this assign-type needed only for tests?
     ;; eg, see id tests in dep2-peano.rkt
     #:with ty (typeof this-syntax)
     #:with e-inst (substs #'(app/eval e_arg ...) #'(r-app x ...) #'e free-identifier=?)
     ;; some apps may not have type (eg in internal reps)
     #:with e+ (if (syntax-e #'ty) (assign-type #'e-inst #'ty) #'e-inst)
     #:do[(when debug?
            (displayln "res:--------------------")
            (pretty-print (stx->datum #'e+))
            ;; (displayln "actual type:")
            ;; (pretty-print (stx->datum (typeof #'e+)))
            ;; (displayln "new type:")
            ;; (pretty-print (stx->datum (substs #'(e_arg ...) #'(X ...) (typeof #'e+))))
            ;; (displayln "res expanded:------------------------")
            ;; (pretty-print
            ;;  (stx->datum (local-expand (substs #'(e_arg ...) #'(x ...) #'e) 'expression null)))
            (displayln "res app/eval re-expanding-----------------------"))]
     #:with ((~literal let-values) () ((~literal let-values) () e++))
            (local-expand
             #'(let-syntax (#;[app (make-rename-transformer #'app/eval)]
                            #;[x (make-variable-like-transformer #'e_arg)]) e+)
                 'expression null)
     #:do[(when debug?
            (pretty-print (stx->datum #'e++))
;            (pretty-print (stx->datum (typeof #'e++)))
            #;(local-expand
             #'(let-syntax ([app (make-rename-transformer #'app/eval)]
                            #;[x (make-variable-like-transformer #'e_arg)]) e+)
             'expression null))]
     #'e++ #;(substs #'(e_arg ...) #'(x ...) #'e)]
    [(_ f . args)
    #:do[(when debug?
           (printf "not apping\n")
           (pretty-print (stx->datum #'f))
           (displayln "args")
           (pretty-print (stx->datum #'args)))]
     #:with f+ (expand/df #'f)
     #:with args+ (stx-map expand/df #'args)
     ;; TODO: need to attach type?
;     #:with ty (typeof this-syntax)
     (syntax-parse #'f+
       [((~literal #%plain-lambda) . _)
        #'(app/eval f+ . args+)]
       [_
        #'(#%app- f+ . args+)])]))
     
;; TODO: fix orig after subst
(define-typed-syntax app
  ;; matching, ; TODO: where to put this?
  #;[(_ f:id . args) ≫
   #:with (_ m/d . _) (local-expand #'(match/delayed 1 2 3 4) 'expression null)
   #:when (free-identifier=? #'m/d #'f)
   ------------
   [≻ (match/nat . args)]]
  [(_ e_fn e_arg ...) ≫
   #:do[(when debug?
          (displayln "TYPECHECKING")
          (pretty-print (stx->datum this-syntax)))]
;   #:do[(printf "applying (1) ~a\n" (stx->datum #'e_fn))]
;   [⊢ e_fn ≫ (~and e_fn- (_ (x:id ...) e ~!)) ⇒ (~Π ([X : τ_inX] ...) τ_outX)]
   [⊢ e_fn ≫ e_fn- ⇒ (~Π ([X : τ_in] ...) τ_out)]
;   #:do[(printf "applying (1) ~a\n" (stx->datum #'e_fn-))]
   #:fail-unless (stx-length=? #'[τ_in ...] #'[e_arg ...])
                 (num-args-fail-msg #'e_fn #'[τ_in ...] #'[e_arg ...])
   [⊢ e_arg ≫ e_arg- ⇐ τ_in] ... ; typechecking args
   -----------------------------
   [⊢ (app/eval e_fn- e_arg- ...) ⇒ #,(substs #'(e_arg- ...) #'(X ...) #'τ_out)]])
   
#;(define-typed-syntax #%app
  [(_ e_fn e_arg ...) ≫ ; apply lambda
   #:do[(printf "applying (1) ~a\n" (stx->datum #'e_fn))]
   [⊢ e_fn ≫ (~and e_fn- (_ (x:id ...) e ~!)) ⇒ (~Π ([X : τ_inX] ...) τ_outX)]
   #:do[(printf "e_fn-: ~a\n" (stx->datum #'e_fn-))
        (printf "args: ~a\n" (stx->datum #'(e_arg ...)))]
   #:fail-unless (stx-length=? #'[τ_inX ...] #'[e_arg ...])
                 (num-args-fail-msg #'e_fn #'[τ_inX ...] #'[e_arg ...])
   [⊢ e_arg ≫ e_argX- ⇒ ty-argX] ... ; typechecking args must be fold; do in 2 steps
   #:do[(define (ev e)
          (syntax-parse e
;            [_ #:do[(printf "eval: ~a\n" (stx->datum e))] #:when #f #'(void)]
            [(~or _:id
;                  ((~literal #%plain-lambda) . _)
                  (~= _ _)
                  ~Nat
                  ((~literal quote) _))
             e]
            ;; handle nums
            [((~literal #%plain-app)
              (~and op (~or (~literal +-) (~literal zero?-)))
              . args:nats)
             #`#,(delta #'op #'args.vals)]
            [((~literal #%plain-app) (~and f ((~literal #%plain-lambda) . b)) . rst)
             (expand/df #`(#%app f . #,(stx-map ev #'rst)))]
            [(x ...)
             ;; #:do[(printf "t before: ~a\n" (typeof e))
             ;;      (printf "t after: ~a\n" (typeof #`#,(stx-map ev #'(x ...))))]
             (syntax-property #`#,(stx-map ev #'(x ...)) ': (typeof e))]
            [_  e] ; other literals
            #;[es (stx-map L #'es)]))]
   #:with (ty-arg ...)
          (stx-map
           (λ (t) (ev (substs #'(e_argX- ...) #'(X ...) t)))
           #'(ty-argX ...))
   #:with (e_arg- ...) (stx-map (λ (e t) (assign-type e t)) #'(e_argX- ...) #'(ty-arg ...))
   #:with (τ_in ... τ_out)
          (stx-map
           (λ (t) (ev (substs #'(e_arg- ...) #'(X ...) t)))
           #'(τ_inX ... τ_outX))
;   #:do[(printf "vars: ~a\n" #'(X ...))]
;   #:when (stx-andmap (λ (t1 t2)(displayln (stx->datum t1)) (displayln (stx->datum t2)) (displayln (typecheck? t1 t2)) #;(typecheck? t1 t2)) #'(ty-arg ...) #'(τ_in ...))
   ;; #:do[(stx-map
   ;;       (λ (tx t) (printf "ty_in inst: \n~a\n~a\n" (stx->datum tx) (stx->datum t)))
   ;;       #'(τ_inX ...)          #'(τ_in ...))]
;   [⊢ e_arg- ≫ _ ⇐ τ_in] ...
    #:do[(printf "res e =\n~a\n" (stx->datum (substs #'(e_arg- ...) #'(x ...) #'e)))
         (printf "res t = ~a\n" (stx->datum (substs #'(e_arg- ...) #'(X ...) #'τ_out)))]
   #:with res-e (let L ([e (substs #'(e_arg- ...) #'(x ...) #'e)]) ; eval
                  (syntax-parse e
                    [(~or _:id
                          ((~literal #%plain-lambda) . _)
                          (~Π ([_ : _] ...) _)
                          (~= _ _)
                          ~Nat)
                     e]
                    ;; handle nums
                    [((~literal #%plain-app)
                      (~and op (~or (~literal +-) (~literal zero?-)))
                      . args:nats)
                     #`#,(delta #'op #'args.vals)]
                    [((~literal #%plain-app) . rst)
                     (expand/df #`(#%app . #,(stx-map L #'rst)))]
                    [_ e] ; other literals
                    #;[es (stx-map L #'es)]))
   ;; #:with res-ty (syntax-parse (substs #'(e_arg- ...) #'(X ...) #'τ_out)
   ;;                 [((~literal #%plain-app) . rst) (expand/df #'(#%app . rst))]
   ;;                 [other-ty #'other-ty])
   --------
   [⊢ res-e #;#,(substs #'(e_arg- ...) #'(x ...) #'e) ⇒ τ_out
            #;#,(substs #'(e_arg- ...) #'(X ...) #'τ_out)]]
  [(_ e_fn e_arg ... ~!) ≫ ; apply var
;   #:do[(printf "applying (2) ~a\n" (stx->datum #'e_fn))]
   [⊢ e_fn ≫ e_fn- ⇒ ty-fn]
;   #:do[(printf "e_fn- ty: ~a\n" (stx->datum #'ty-fn))]
   [⊢ e_fn ≫ _ ⇒ (~Π ([X : τ_inX] ...) τ_outX)]
;   #:do[(printf "e_fn- no: ~a\n" (stx->datum #'e_fn-))
;        (printf "args: ~a\n" (stx->datum #'(e_arg ...)))]
   ;; #:with e_fn- (syntax-parse #'e_fn*
   ;;                [((~literal #%plain-app) . rst) (expand/df #'(#%app . rst))]
   ;;                [other #'other])
   #:fail-unless (stx-length=? #'[τ_inX ...] #'[e_arg ...])
                 (num-args-fail-msg #'e_fn #'[τ_inX ...] #'[e_arg ...])
   [⊢ e_arg ≫ e_argX- ⇒ ty-argX] ... ; typechecking args must be fold; do in 2 steps
   #:do[(define (ev e)
          (syntax-parse e
;            [_ #:do[(printf "eval: ~a\n" (stx->datum e))] #:when #f #'(void)]
            [(~or _:id
;                  ((~literal #%plain-lambda) . _)
                  (~= _ _)
                  ~Nat
                  ((~literal quote) _))
             e]
            ;; handle nums
            [((~literal #%plain-app)
              (~and op (~or (~literal +-) (~literal zero?-)))
              . args:nats)
             #`#,(delta #'op #'args.vals)]
            [((~literal #%plain-app) (~and f ((~literal #%plain-lambda) . b)) . rst)
             (expand/df #`(#%app f . #,(stx-map ev #'rst)))]
            [(x ...)
             ;; #:do[(printf "t before: ~a\n" (typeof e))
             ;;      (printf "t after: ~a\n" (typeof #`#,(stx-map ev #'(x ...))))]
             (syntax-property #`#,(stx-map ev #'(x ...)) ': (typeof e))]
            [_  e] ; other literals
            #;[es (stx-map L #'es)]))]
   #:with (ty-arg ...)
          (stx-map
           (λ (t) (ev (substs #'(e_argX- ...) #'(X ...) t)))
           #'(ty-argX ...))
   #:with (e_arg- ...) (stx-map (λ (e t) (assign-type e t)) #'(e_argX- ...) #'(ty-arg ...))
   #:with (τ_in ... τ_out)
          (stx-map
           (λ (t) (ev (substs #'(e_arg- ...) #'(X ...) t)))
           #'(τ_inX ... τ_outX))
   ;; #:do[(printf "vars: ~a\n" #'(X ...))]
;  #:when (stx-andmap (λ (e t1 t2)(displayln (stx->datum e))(displayln (stx->datum t1)) (displayln (stx->datum t2)) (displayln (typecheck? t1 t2)) #;(typecheck? t1 t2)) #'(e_arg ...)#'(ty-arg ...) #'(τ_in ...))
   ;; #:do[(stx-map
   ;;       (λ (tx t) (printf "ty_in inst: \n~a\n~a\n" (stx->datum tx) (stx->datum t)))
   ;;       #'(τ_inX ...)          #'(τ_in ...))]
;   [⊢ e_arg ≫ _ ⇐ τ_in] ...
;  #:do[(printf "res e2 =\n~a\n" (stx->datum #'(#%app- e_fn- e_arg- ...)))
;       (printf "res t2 = ~a\n" (stx->datum (substs #'(e_arg- ...) #'(X ...) #'τ_out)))]
   ;; #:with res-e (syntax-parse #'e_fn-
   ;;                [((~literal #%plain-lambda) . _) (expand/df #'(#%app e_fn- e_arg- ...))]
   ;;                [other #'(#%app- e_fn- e_arg- ...)])
   --------
   [⊢ (#%app- e_fn- e_arg- ...) ⇒ τ_out
      #;#,(expand/df (substs #'(e_arg- ...) #'(X ...) #'τ_out))]])

(define-typed-syntax (ann e (~datum :) τ) ≫
  [⊢ e ≫ e- ⇐ τ]
  --------
  [⊢ e- ⇒ τ])

;; (define-typed-syntax (if e1 e2 e3) ≫
;;   [⊢ e1 ≫ e1- ⇒ _]
;;   [⊢ e2 ≫ e2- ⇒ ty]
;;   [⊢ e3 ≫ e3- ⇒ _]
;;   #:do[(displayln #'(e1 e2 e3))]
;;   --------------
;;   [⊢ (#%app- void-) ⇒ ty])

;; top-level ------------------------------------------------------------------
;; TODO: shouldnt need define-type-alias, should be same as define
(define-syntax define-type-alias
  (syntax-parser
    [(_ alias:id τ);τ:any-type)
     #'(define-syntax- alias
         (make-variable-like-transformer #'τ))]
    #;[(_ (f:id x:id ...) ty)
     #'(define-syntax- (f stx)
         (syntax-parse stx
           [(_ x ...)
            #:with τ:any-type #'ty
            #'τ.norm]))]))

(define-typed-syntax define
  [(_ x:id (~datum :) τ e:expr) ≫
   [⊢ e ≫ e- ⇐ τ]
   #:with y (generate-temporary #'x)
   #:with y+props (transfer-props #'e- #'y #:except '(origin))
   --------
   [≻ (begin-
        (define-syntax x (make-rename-transformer #'y+props))
        (define- y e-))]]
  [(_ x:id e) ≫
   ;This won't work with mutually recursive definitions
   [⊢ e ≫ e- ⇒ _]
   #:with y (generate-temporary #'x)
   #:with y+props (transfer-props #'e- #'y #:except '(origin))
   --------
   [≻ (begin-
        (define-syntax x (make-rename-transformer #'y+props))
        (define- y e-))]]
  #;[(_ (f [x (~datum :) ty] ... (~or (~datum →) (~datum ->)) ty_out) e ...+) ≫
   #:with f- (add-orig (generate-temporary #'f) #'f)
   --------
   [≻ (begin-
        (define-syntax- f
          (make-rename-transformer (⊢ f- : (→ ty ... ty_out))))
        (define- f-
          (stlc+lit:λ ([x : ty] ...)
            (stlc+lit:ann (begin e ...) : ty_out))))]])


;; peano nums -----------------------------------------------------------------
(define-base-type Nat)

(struct Z () #:transparent)
(struct S (n) #:transparent)

(define-typed-syntax Zero
  [_:id ≫ --- [⊢ (Z) ⇒ Nat]])

(define-typed-syntax (Succ n) ≫
  [⊢ n ≫ n- ⇐ Nat]
  -----------
  [⊢ (S n-) ⇒ Nat])
#;(define-typed-syntax (sub1 n) ≫
  [⊢ n ≫ n- ⇐ Nat]
  #:do[(displayln #'n-)]
  -----------
  [⊢ (#%app- -- n- 1) ⇒ Nat])

;; generalized recursor over natural nums
;; (cases dispatched in #%app)
;; (define- (nat-ind- P z s n) (#%app- void))
;; (define-syntax nat-ind
;;   (make-variable-like-transformer
;;    (assign-type 
;;     #'nat-ind-
;;     #'(Π ([P : (→ Nat #%type)]
;;           [z : (app P Zero)]
;;           [s : (Π ([k : Nat]) (→ (app P k) (app P (Succ k))))]
;;           [n : Nat])
;;          (app P n)))))

#;(define-type-alias nat-ind
  (λ ([P : (→ Nat #%type)]
      [z : (P Z)]
      [s : (Π ([k : Nat]) (→ (P k) (P (S k))))]
      [n : Nat])
    #'(#%app- nat-ind- P z s n)))
(struct match/delayed (n P zc sc))
#;(define-syntax match/eval
  (syntax-parser
    [(_ n zc sc) #:do[(printf "matching: ~a\n" (stx->datum #'n))] #:when #f #'(void)]
    [(_ ((~literal #%plain-app) z0:id) zc sc) 
     #:with (_ z1) (local-expand #'(Z) 'expression null)
     #:when (free-identifier=? #'z0 #'z1)
     #'zc]
    [(_ ((~literal #%plain-app) s0:id m) zc sc)
     #:with (_ s1 . _) (local-expand #'(S 'dont-care) 'expression null)
     #:when (free-identifier=? #'s0 #'s1)
     #:when (displayln 2)
     #`(app sc (nat-rec #,(typeof #'zc) zc sc m))]
    [(_ n zc sc) #'(match/delayed n zc sc)]))

;; this is an "eval" form; should not do any more type checking
;; otherwise, will get type errs some some subexprs may still have uninst tys
;; eg, zc and sc were typechecked with paramaterized P instead of inst'ed P
(define-syntax match/nat
  (syntax-parser
    [(_ n P zc sc)
     #:do[(when debug-match?
            (printf "match/nating: ~a\n" (stx->datum #'(n P zc sc)))
            #;(printf "zc ty: ~a\n" (stx->datum (typeof #'zc)))
            #;(printf "sc ty: ~a\n" (stx->datum (typeof #'sc))))]
     #:when #f #'(void)]
    [(_ (~and n ((~literal #%plain-app) z0:id)) P zc sc)
     #:with (_ z1) (local-expand #'(#%app Z) 'expression null)
     #:when (free-identifier=? #'z0 #'z1)
     #:do [(when debug-match? (displayln 'zc))]
     ;; #:when (printf "match eval res zero ety: ~a\n" (stx->datum (typeof this-syntax)))
     ;; #:when (printf "match eval res zero ty: ~a\n" (stx->datum (typeof #'zc)))
     (assign-type #'zc #'(app/eval P n))]
    [(_ (~and n ((~literal #%plain-app) s0:id m)) P zc sc)
     #:with (_ s1 . _) (local-expand #'(#%app S 'dont-care) 'expression null)
     #:when (free-identifier=? #'s0 #'s1)
     #:with (~Π ([_ : _] ...) τ_out) (typeof #'sc)
     #:do[(when debug-match? (displayln 'sc))]
     ;; #:when (printf "match eval res succ ety: ~a\n" (stx->datum (typeof this-syntax)))
     ;; #:when (printf "match eval res succ ty: ~a\n" (stx->datum (typeof #'sc)))
     ;; #:when (printf "match eval res succ ty: ~a\n" (stx->datum (typeof #'(app/eval (app/eval sc m) (match/nat m P zc sc)))))
;     #`(app sc m (nat-rec #,(typeof #'zc) zc sc m))]
;     #:with ty (typeof this-syntax)
     (assign-type
      #`(app/eval #,(assign-type #'(app/eval sc m) #'τ_out) (match/nat m P zc sc))
      #'(app/eval P n))
  ;   #'res
 ;    (if (syntax-e #'ty) (assign-type #'res #'ty) #'res)
     #;(assign-type #`(app/eval #,(assign-type #'(app/eval sc m) #'τ_out) (match/nat m P zc sc)) (typeof this-syntax))]
    [(_ n P zc sc)
     #:do[(when debug-match?  (displayln "delay match"))]
     (assign-type #'(#%app match/delayed n P zc sc) #'(app/eval P n))]))
#;(define-typed-syntax (nat-rec ty zc sc n) ≫
  [⊢ ty ≫ ty- ⇐ #%type]
  [⊢ zc ≫ zc- ⇐ ty-] ; zero case
  [⊢ sc ≫ sc- ⇐ (→ ty- ty-)] ; succ case
  [⊢ n ≫ n- ⇐ Nat]
  ;; #:with res
  ;;   (syntax-parse #'n-
  ;;    [aaa #:do[(printf "matching: ~a\n" (stx->datum #'aaa))] #:when #f #'(void)]
  ;;    [((~literal #%plain-app) (~literal Z)) #'zc-]
  ;;    [((~literal #%plain-app) (~literal S) m) #'(app sc- (nat-rec zc- sc- m))])
  --------------------
;  [⊢ (match/eval n- zc- sc-) ⇒ ty-])
  [⊢ (match/nat n-
                zc-
                (λ ([n-1 : Nat][rec : ty-])
                  (sc- rec)))
     ⇒ ty-])
  
(define-typed-syntax (nat-ind P z s n) ≫
  [⊢ P ≫ P- ⇐ (→ Nat #%type)]
  [⊢ z ≫ z- ⇐ (app P- Zero)] ; zero 
  [⊢ s ≫ s- ⇐ (Π ([k : Nat]) (→ (app P- k) (app P- (Succ k))))] ; succ
  [⊢ n ≫ n- ⇐ Nat]
  ;; #:with res (if (typecheck? #'n- (expand/df #'Z))
  ;;                #'z-
  ;;                #'(s- (nat-ind P- z- s- (sub1 n-))))
  ----------------
  [⊢ (match/nat n-
                P-
                z-
                s-
                #;(λ ([n-1 : Nat][rec : (app P- n-)])
                  (app s- n-1 rec #;(nat-ind P- z- s- n-1))))
     ⇒ (app P- n-)])
;  [≻ (P- d-)])

;; proof assistant

(provide prove ? refine)

(struct ?? ())
(define-for-syntax ?+ (stx-cadr (local-expand #'(??) 'expression null)))

(define-typed-syntax ?
  [(_ ty) ≫
   #:with x (generate-temporary)
   #:do[(current-hole #'x)]
   -----
   [⊢ #,?+ ⇒ ty]]
  [_:id ⇐ ty ≫
   #:with x (generate-temporary)
   #:do[(current-hole #'x)]
   -----
   [⊢ #,?+]])

(begin-for-syntax
  (define current-ty (make-parameter #f))
  (define current-hole (make-parameter #f))
  (define current-expr (make-parameter #f))
  (define (update-expr e)
    (set-expr (subst e ?+ (current-expr) free-identifier=?)))
  (define (set-expr e)
    (current-expr e)
    (printf "current proof: ~a\n" (stx->datum (current-expr))))
  (define (mk-hole)
    (current-hole (generate-temporary))
    (current-hole)))


(define-syntax prove
  (syntax-parser
    [(_ ty)
     #:do[(current-ty ((current-type-eval) #'ty))]
     #:when (local-expand #'(? ty) 'expression null)
     #:do[(set-expr #'?)] 
     #'(void)]))

(define-typed-syntax refine
  [(_ e) ≫
   #:do[(printf "refining with: ~a\n" (stx->datum #'e))]
   #:with ty (current-ty)
   #:with e0 (subst #'e #'? (current-expr) free-identifier=?)
   [⊢ e0 ≫ e0- ⇐ ty]
   #:do [(displayln "ok.")
         (set-expr #'e0)
         (let ([x (generate-temporary)])
           (when ((current-type=?) #'e0 (subst #'x #'? #'e0 free-identifier=?))
               (displayln "qed.")))]
   -------
   [⊢ (void) ⇒ ty]])
