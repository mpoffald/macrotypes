#lang turnstile/lang

; a basic dependently-typed calculus
; - with inductive datatypes

; copied from dep-ind-fixed.rkt
; - extended with cur-style currying as the default

; this file is mostly same as dep-ind.rkt but define-datatype has some fixes:
; 1) params and indices must be applied separately
;   - for constructor (but not type constructor)
; 2) allows indices to depend on param
; 3) indices were not being inst with params
; 4) arg refs were using x instead of Cx from new expansion
; TODO: re-compute recur-x, ie recur-Cx

; Π  λ ≻ ⊢ ≫ → ∧ (bidir ⇒ ⇐) τ⊑ ⇑

(provide Type (rename-out [Type *])
;         Π → ∀ λ (rename-out [app #%app])
         (rename-out [Π/c Π] [→/c →] [∀/c ∀] [λ/c λ] [app/c #%app])
         = eq-refl eq-elim
         ann define-datatype define define-type-alias
)

;; TODO:
;; - map #%datum to S and Z
;; - rename define-type-alias to define
;; - add "assistant" part
;; - provide match and match/lambda so nat-ind can be fn
;;   - eg see https://gist.github.com/AndrasKovacs/6769513
;; - add dependent existential
;; - remove debugging code?

;; set (Type n) : (Type n+1)
;; Type = (Type 0)
(define-internal-type-constructor Type #:runtime)
(define-typed-syntax Type
  [:id ≫ --- [≻ (Type 0)]]
  [(_ n:exact-nonnegative-integer) ≫
   #:with n+1 (+ (syntax-e #'n) 1)
  -------------
  [≻ #,(syntax-property
        (syntax-property 
         #'(Type- 'n) ':
         (syntax-property
          #'(Type n+1)
          'orig
          (list #'(Type n+1))))
        'orig
        (list #'(Type n)))]])

(begin-for-syntax
  (define debug? #f)
  (define type-eq-debug? #f)
  (define debug-match? #f)
  (define debug-elim? #f)

  ;; TODO: fix `type` stx class
  ;; current-type and type stx class not working
  ;; for case where var has type that is previous var
  ;; that is not yet in tyenv
  ;; eg in (Π ([A : *][a : A]) ...)
  ;; expansion of 2nd type A will fail with unbound id err
  ;;
  ;; attempt 2
  ;; (define old-type? (current-type?))
  ;; (current-type?
  ;;  (lambda (t)
  ;;    (printf "t = ~a\n" (stx->datum t))
  ;;    (printf "ty = ~a\n" (stx->datum (typeof t)))
  ;;    (or (Type? (typeof t))
  ;;        (syntax-parse (typeof t)
  ;;          [((~literal Type-) n:exact-nonnegative-integer) #t]
  ;;          [_ #f]))))
  ;; attempt 1
  ;; (define old-type? (current-type?))
  ;; (current-type?
  ;;  (lambda (t) (or (#%type? t) (old-type? t))))


  (define old-relation (current-typecheck-relation))
  (current-typecheck-relation
   (lambda (t1 t2)
     (define res
       ;; expand (Type n) if unexpanded
       (or (syntax-parse t1
             [((~literal Type) n)
              (typecheck? ((current-type-eval) t1) t2)]
             [_ #f])
           (old-relation t1 t2)))
     (when type-eq-debug?
       (pretty-print (stx->datum t1))
       (pretty-print (stx->datum t2))
       (printf "res: ~a\n" res))
     res))
  ;; used to attach type after app/eval
  ;; but not all apps will have types, eg
  ;; - internal type representation
  ;; - intermediate elim terms
  (define (maybe-assign-type e t)
    (if (syntax-e t) (assign-type e t) e)))

(define-internal-type-constructor → #:runtime) ; equiv to Π with no uses on rhs
(define-internal-binding-type ∀ #:runtime)     ; equiv to Π with Type for all params

;; Π expands into combination of internal →- and ∀-
;; uses "let*" syntax where X_i is in scope for τ_i+1 ...
;; TODO: add tests to check this
(define-typed-syntax (Π ([X:id : τ_in] ...) τ_out) ≫
  [[X ≫ X- : τ_in] ... ⊢ [τ_out ≫ τ_out- ⇒ tyoutty]
                         [τ_in  ≫ τ_in-  ⇒ tyinty] ...]
  ;; check that types have type (Type _)
  ;; must re-expand since (Type n) will have type unexpanded (Type n+1)
  #:with ((~Type _) ...) (stx-map (current-type-eval) #'(tyoutty tyinty ...))
  -------
  [⊢ (∀- (X- ...) (→- τ_in- ... τ_out-)) ⇒ Type]
  #;[⊢ #,#`(∀- (X- ...)
             #,(assign-type
                #'(→- τ_in- ... τ_out-)
                #'#%type)) ⇒ #%type])

;; abbrevs for Π
;; (→ τ_in τ_out) == (Π (unused : τ_in) τ_out)
(define-simple-macro (→ τ_in ... τ_out)
  #:with (X ...) (generate-temporaries #'(τ_in ...))
  (Π ([X : τ_in] ...) τ_out))
;; (∀ (X) τ) == (∀ ([X : Type]) τ)
(define-simple-macro (∀ (X ...)  τ)
  (Π ([X : Type] ...) τ))

;; pattern expanders
(begin-for-syntax
  (define-syntax ~Π
    (pattern-expander
     (syntax-parser
       [(_ ([x:id : τ_in] ... (~and (~literal ...) ooo)) τ_out)
        #'(~∀ (x ... ooo) (~→ τ_in ... ooo τ_out))]
       [(_ ([x:id : τ_in] ...)  τ_out)
        #'(~∀ (x ...) (~→ τ_in ... τ_out))])))
  (define-syntax ~Π/c
    (pattern-expander
     (syntax-parser
       ;; [(_ ([x:id : τ_in] ... (~and (~literal ...) ooo)) τ_out)
       ;;  #'(~∀ (x ... ooo) (~→ τ_in ... ooo τ_out))]
       [(_ t) #'t]
       [(_ [x (~datum :) ty] (~and (~literal ...) ooo) t_out)
        #'(~and TMP
                (~parse ([x ty] ooo t_out)
                        (let L ([ty #'TMP][xtys empty])
                             (syntax-parse ty
                               ;[debug #:do[(display "debug:")(pretty-print (stx->datum #'debug))]#:when #f #'(void)]
                               [(~Π ([x : τ_in]) rst) (L #'rst (cons #'[x τ_in] xtys))]
                               [t_out (reverse (cons #'t_out xtys))]))))]
       [(_ (~and xty [x:id : τ_in]) . rst)
        #'(~Π (xty) (~Π/c . rst))]))))

;; equality -------------------------------------------------------------------
(define-internal-type-constructor =)
(define-typed-syntax (= t1 t2) ≫
  [⊢ t1 ≫ t1- ⇒ ty]
  [⊢ t2 ≫ t2- ⇐ ty]
  ;; #:do [(printf "t1: ~a\n" (stx->datum #'t1-))
  ;;       (printf "t2: ~a\n" (stx->datum #'t2-))]
;  [t1- τ= t2-]
  ---------------------
  [⊢ (=- t1- t2-) ⇒ Type])

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
  [⊢ P ≫ P- ⇐ (→ ty Type)]
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
   [[x ≫ x- : τ_in] ... ⊢ #,(substs #'(x ...) #'(y ...) #'e) ≫ e- ⇐ τ_out]
   ---------
   [⊢ (λ- (x- ...) e-)]]
  ;; both expected ty and annotations
  [(_ ([y:id : τ_in*] ...) e) ⇐ (~Π ([x:id : τ_in] ...) τ_out) ≫
;  [(_ ([y:id : τy_in:type] ...) e) ⇐ (~Π ([x:id : τ_in] ...) τ_out) ≫
   #:fail-unless (stx-length=? #'(y ...) #'(x ...))
                 "function's arity does not match expected type"
   [⊢ τ_in* ≫ τ_in** ⇐ Type] ...
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

;; helps debug which terms (app/evals) do not have types, eg
;; - → in internal type representation
;; - intermediate elim terms
(define-for-syntax false-tys 0)

;; TODO: need app/eval/c

;; TODO: fix orig after subst, for err msgs
;; app/eval should not try to ty check anymore
(define-syntax app/eval
  (syntax-parser
    #;[(_ f . args) #:do[(printf "app/evaling ")
                       (printf "f: ~a\n" (stx->datum #'f))
                       (printf "args: ~a\n" (stx->datum #'args))]
     #:when #f #'void]
    [(_ f:id (_ matcher) (_ _ . args))
     #:do[(when debug-match?
            (printf "potential delayed match ~a ~a\n"
                  (stx->datum #'matcher)
                  (stx->datum #'args)))]
     #:with ty (typeof this-syntax)
     ;; TODO: use pat expander instead
     #:with (_ m/d . _) (local-expand #'(#%app match/delayed 'dont 'care) 'expression null)
     #:when (free-identifier=? #'m/d #'f)
     #:do[(when debug-match? (printf "matching\n"))]
     ;; TODO: need to attach type?
     #;[
          (unless (syntax-e #'ty)
            (displayln 3)
            (displayln #'ty)
            (set! false-tys (add1 false-tys))
            (displayln false-tys))]
     (maybe-assign-type #'(matcher . args) (typeof this-syntax))]
    ;; TODO: apply to only lambda args or all args?
    [(_ (~and f ((~literal #%plain-lambda) (x ...) e)) e_arg ...)
     #:do[(when debug?
            (printf "apping: ~a\n" (stx->datum #'f))
            (printf "args\n")
            (pretty-print (stx->datum #'(e_arg ...))))]
;     #:with (~Π ([X : _] ...) τ_out) (typeof #'f) ; must re-subst in type
     ;; TODO: need to replace all #%app- in this result with app/eval again
     ;; and then re-expand
;     #:with ((~literal #%plain-app) newf . newargs) #'e
 ;    #:do[(displayln #'newf)(displayln #'newargs)(displayln (stx-car #'e+))]
     #:with r-app (datum->syntax (if (identifier? #'e) #'e (stx-car #'e)) '#%app)
     ;; TODO: is this assign-type needed only for tests?
     ;; eg, see id tests in dep2-peano.rkt
     #:with ty (typeof this-syntax)
     #:do[(when debug?
            (define ttt (typeof this-syntax))
            (define ttt2 (and ttt
                              (substs #'(app/eval e_arg ...) #'(r-app x ...) ttt free-identifier=?)))
            (define ttt3 (and ttt2
                              (local-expand ttt2 'expression null)))
            (printf "expected type\n")
            (pretty-print (stx->datum ttt))
            (pretty-print (stx->datum ttt2))
            (pretty-print (stx->datum ttt3)))]
     #:with e-inst (substs #'(app/eval e_arg ...) #'(r-app x ...) #'e free-identifier=?)
     ;; some apps may not have type (eg in internal reps)
     #:with e+ (if (syntax-e #'ty)
                   (assign-type
                    #'e-inst
                    (local-expand
;                     (substs #'(app/eval e_arg ...) #'(r-app x ...) #'ty free-identifier=?)
                     ;; TODO: this is needed, which means there are some uneval'ed matches
                     ;; but is this the right place?
                     ;; eg, it wasnt waiting on any arg
                     ;; so that mean it could have been evaled but wasnt at some point
                     (substs #'(app/eval) #'(r-app) #'ty free-identifier=?)
                     'expression null))
                   #'e-inst)
     #:do[(when debug?
            (displayln "res:--------------------")
            (pretty-print (stx->datum #'e+))
            ;; (displayln "actual type:")
            ;; (pretty-print (stx->datum (typeof #'e+)))
            (displayln "new type:")
            (pretty-print (stx->datum (typeof #'e+)))
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
     #;[(when (not (syntax-e #'ty))
            (displayln 1)
            (displayln (stx->datum this-syntax))
            (displayln #'ty)
            (set! false-tys (add1 false-tys))
            (displayln false-tys))]
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
     #:with ty (typeof this-syntax)
     #;[(unless (syntax-e #'ty)
            (displayln 2)
            (displayln (stx->datum this-syntax))
            (displayln #'ty)
            (displayln (syntax-property this-syntax '::))
            (set! false-tys (add1 false-tys))
            (displayln false-tys))]
     (syntax-parse #'f+
       [((~literal #%plain-lambda) . _)
        (maybe-assign-type #'(app/eval f+ . args+) #'ty)]
       [_
        ;(maybe-assign-type
         #'(#%app- f+ . args+)
         ;#'ty)
        ])]))
     
;; TODO: fix orig after subst
(define-typed-syntax app
  [(_ e_fn e_arg ...) ≫
   #:do[(when debug?
          (displayln "TYPECHECKING")
          (pretty-print (stx->datum this-syntax)))]
   
;   #:do[(printf "applying (1) ~a\n" (stx->datum #'e_fn))]
;   [⊢ e_fn ≫ (~and e_fn- (_ (x:id ...) e ~!)) ⇒ (~Π ([X : τ_inX] ...) τ_outX)]
   [⊢ e_fn ≫ e_fn- ⇒ (~Π ([X : τ_in] ...) τ_out)]
   #:fail-unless (stx-length=? #'[τ_in ...] #'[e_arg ...])
                 (num-args-fail-msg #'e_fn #'[τ_in ...] #'[e_arg ...])
   ;; #:do[(displayln "expecting app args")
   ;;      (pretty-print (stx->datum #'(τ_in ...)))]
   ;; [⊢ e_arg ≫ _ ⇒ ty2] ... ; typechecking args
   ;; #:do[(displayln "got")
   ;;      (pretty-print (stx->datum #'(ty2 ...)))
   ;;      (pretty-print (stx->datum (stx-map typeof #'(ty2 ...))))]
   [⊢ e_arg ≫ e_arg- ⇐ τ_in] ... ; typechecking args
   -----------------------------
   [⊢ (app/eval e_fn- e_arg- ...) ⇒ #,(substs #'(e_arg- ...) #'(X ...) #'τ_out)]])

(define-typed-syntax (ann e (~datum :) τ) ≫
  [⊢ e ≫ e- ⇐ τ]
  --------
  [⊢ e- ⇒ τ])

;; ----------------------------------------------------------------------------
;; auto-currying λ and #%app and Π
;; - requires annotations for now
;; TODO: add other cases?
(define-syntax (λ/c stx)
  (syntax-parse stx
    [(_ e) #'e]
    [(_ x . rst) #'(λ (x) (λ/c . rst))]))

(define-syntax (app/c stx)
  (syntax-parse stx
    [(_ e) #'e]
    [(_ f e . rst) #'(app/c (app f e) . rst)]))

(define-syntax (app/eval/c stx)
  (syntax-parse stx
    [(_ e) #'e]
    [(_ f e . rst) #'(app/eval/c (app/eval f e) . rst)]))

(define-syntax (Π/c stx)
  (syntax-parse stx
    [(_ t) #'t]
    [(_ (~and xty [x:id (~datum :) τ]) . rst) #'(Π (xty) (Π/c . rst))]))

;; abbrevs for Π/c
;; (→ τ_in τ_out) == (Π (unused : τ_in) τ_out)
(define-simple-macro (→/c τ_in ... τ_out)
  #:with (X ...) (generate-temporaries #'(τ_in ...))
  (Π/c [X : τ_in] ... τ_out))
;; (∀ (X) τ) == (∀ ([X : Type]) τ)
(define-simple-macro (∀/c X ...  τ)
  (Π/c [X : Type] ... τ))

;; pattern expanders
(begin-for-syntax
  (define-syntax ~plain-app/c
    (pattern-expander
     (syntax-parser
       [(_ f) #'f]
       [(_ f e . rst)
        #'(~plain-app/c ((~literal #%plain-app) f e) . rst)]))))


;; untyped
(define-syntax (λ/c- stx)
  (syntax-parse stx
    [(_ () e) #'e]
    [(_ (x . rst) e) #'(λ- (x) (λ/c- rst e))]))

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

;; TODO: delete this?
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


(define-typed-syntax (unsafe-assign-type e (~datum :) τ) ≫ --- [⊢ e ⇒ τ])

;; TmpTy is a placeholder for undefined names
(struct TmpTy- ())
(define-syntax TmpTy
  (syntax-parser
    [:id (assign-type #'TmpTy- #'Type)]
    [(_ . args) (assign-type #'(#%app TmpTy- . args) #'Type)]))
(begin-for-syntax (define/with-syntax TmpTy+ (expand/df #'TmpTy)))

(struct match/delayed (name args) #:transparent)

;; helper syntax fns
(begin-for-syntax
  ;; drops first n bindings in Π type
  (define (prune t n)
    (if (zero? n)
        t
        (syntax-parse t
          [(~Π ([_ : _]) t1)
           (prune #'t1 (sub1 n))])))
  ;; x+τss = (([x τ] ...) ...)
  ;; returns subset of each (x ...) that is recursive, ie τ = TY
  (define (find-recur TY x+τss)
    (stx-map
     (λ (x+τs)
       (stx-filtermap
        (syntax-parser [(x τ) (and (free-id=? #'τ TY) #'x)])
        x+τs))
     x+τss))
  ;; x+τss = (([x τ] ...) ...)
  ;; returns subset of each (x ...) that is recursive, ie τ = (TY . args)
  ;; along with the indices needed by each recursive x
  ;; - ASSUME: the needed indices are first `num-is` arguments in x+τss
  ;; - ASSUME: the recursive arg has type (TY . args) where TY is unexpanded
  (define (find-recur/i TY num-is x+τss)
    (stx-map
     (λ (x+τs)
       (define xs (stx-map stx-car x+τs))
       (stx-filtermap
        (syntax-parser
          [(x (t . _)) (and (free-id=? #'t TY) (cons #'x (stx-take xs num-is)))]
          [_ #f])
        x+τs))
     x+τss))
  )

;; use this macro to expand e, which contains references to unbound X
(define-syntax (with-unbound stx)
  (syntax-parse stx
    [(_ X:id e)
     ;swap in a tmp (bound) id `TmpTy` for unbound X
     #:with e/tmp (subst #'TmpTy #'X #'e)
     ;; expand with the tmp id
     (expand/df #'e/tmp)]))
(define-syntax (drop-params stx)
  (syntax-parse stx
    [(_ (A ...) τ)
     (prune #'τ (stx-length #'(A ...)))]))
;; must be used with with-unbound
(begin-for-syntax
  (define-syntax ~unbound
    (pattern-expander
     (syntax-parser
       [(_ X:id pat)
        ;; un-subst tmp id in expanded stx with type X
        #'(~and TMP (~parse pat (subst #'X #'TmpTy+ #'TMP free-id=?)))])))
    ; subst τ for TmpTy+ in e, if (bound-id=? x y), when it has usage (#%app TmpTy+ . args)
  (define (subst-tmp τ x e [cmp bound-identifier=?])
    (syntax-parse e
      [((~literal #%plain-app) y . rst)
       #:when (cmp #'y #'TmpTy+)
       (transfer-stx-props #`(#,τ . rst) (merge-type-tags (syntax-track-origin τ e #'y)))]
      [(esub ...)
       #:with res (stx-map (λ (e1) (subst-tmp τ x e1 cmp)) #'(esub ...))
       (transfer-stx-props #'res e #:ctx e)]
      [_ e]))
  (define-syntax ~unbound/tycon
    (pattern-expander
     (syntax-parser
       [(_ X:id pat)
        ;; un-subst tmp id in expanded stx with type constructor X
        #'(~and TMP (~parse pat (subst-tmp #'X #'TmpTy+ #'TMP free-id=?)))])))
  ;; matches constructor pattern (C x ...) where C matches literally
  (define-syntax ~Cons
    (pattern-expander
     (syntax-parser
       [(_ (C x ...))
        #'(~and TMP
                (~parse (~plain-app/c C-:id x ...) (expand/df #'TMP))
                (~parse (_ C+ . _) (expand/df #'(C)))
                (~fail #:unless (free-id=? #'C- #'C+)))])))
)
     
(define-typed-syntax define-datatype
  ;; simple datatypes, eg Nat -------------------------------------------------
  ;; - ie, `TY` is an id with no params or indices
  [(_ TY:id (~datum :) τ:id [C:id (~datum :) τC] ...) ≫
   ;; need with-unbound and ~unbound bc `TY` name still undefined here
   [⊢ (with-unbound TY τC) ≫ (~unbound TY (~Π/c [x : τin] ... _)) ⇐ Type] ...
   ;; ---------- pre-define some pattern variables for cleaner output:
   ;; recursive args of each C; where (xrec ...) ⊆ (x ...)
   #:with ((xrec ...) ...) (find-recur #'TY #'(([x τin] ...) ...))
   ;; struct defs
   #:with (C/internal ...) (generate-temporaries #'(C ...))
   ;; elim methods and method types
   #:with (m ...) (generate-temporaries #'(C ...))
   #:with (m- ...) (generate-temporaries #'(m ...))
   #:with (τm ...) (generate-temporaries #'(m ...))
   #:with elim-TY (format-id #'TY "elim-~a" #'TY)
   #:with eval-TY (format-id #'TY "eval-~a" #'TY)
   #:with TY/internal (generate-temporary #'TY)
   --------
   [≻ (begin-
        ;; define `TY`, eg "Nat", as a valid type
;        (define-base-type TY : κ) ; dont use bc uses '::, and runtime errs
        (struct TY/internal () #:prefab)
        (define-typed-syntax TY
          [_:id ≫ --- [⊢ #,(syntax-property #'(TY/internal) 'elim-name #'elim-TY) ⇒ τ]])
        ;; define structs for `C` constructors
        (struct C/internal (x ...) #:transparent) ...
        (define C (unsafe-assign-type C/internal : τC)) ...
        ;; elimination form
        (define-typerule (elim-TY v P m ...) ≫
          [⊢ v ≫ v- ⇐ TY]
          [⊢ P ≫ P- ⇐ (→ TY Type)] ; prop / motive
          ;; each `m` can consume 2 sets of args:
          ;; 1) args of the constructor `x` ... 
          ;; 2) IHs for each `x` that has type `TY`
          #:with (τm ...) #'((Π/c [x : τin] ...
                              (→/c (app/c P- xrec) ... (app/c P- (app/c C x ...)))) ...)
          [⊢ m ≫ m- ⇐ τm] ...
          -----------
          [⊢ (eval-TY v- P- m- ...) ⇒ (app/c P- v-)])
        ;; eval the elim redexes
        (define-syntax eval-TY
          (syntax-parser
            #;[(_ . args) ; uncomment for help with debugging
             #:do[(printf "trying to match:\n~a\n" (stx->datum #'args))]
             #:when #f #'void]
            [(_ (~Cons (C x ...)) P m ...)
             #'(app/eval/c m x ... (eval-TY xrec P m ...) ...)] ...
            ;; else generate a "delayed" term
            ;; must be #%app-, not #%plain-app, ow match will not dispatch properly
            [(_ . args) #'(#%app- match/delayed 'eval-TY (void . args))])))]]
  ;; --------------------------------------------------------------------------
  ;; defines inductive type family `TY`, with:
  ;; - params A ...
  ;; - indices i ...
  ;; - ie, TY is a type constructor with type (Π [A : τA] ... [i τi] ... τ)
  ;; --------------------------------------------------------------------------
  [(_ TY:id [A:id (~datum :) τA] ... (~datum :) ; params
            [i:id (~datum :) τi] ... ; indices
            (~datum ->) τ
   [C:id (~datum :) τC] ...) ≫
   ; need to expand `τC` but `TY` is still unbound so use tmp id
   [⊢ (with-unbound TY τC) ≫ (~unbound/tycon TY (~Π/c [A+i+x : τA+i+x] ... τout)) ⇐ Type] ...
   ;; split τC args into params and others
   ;; TODO: check that τA matches τCA (but cant do it in isolation bc they may refer to other params?)
   #:with ((([CA τCA] ...)
            ([i+x τin] ...)) ...)
          (stx-map
           (λ (x+τs) (stx-split-at x+τs (stx-length #'(A ...))))
           #'(([A+i+x τA+i+x] ...) ...))

   ;; - each (xrec ...) is subset of (x ...) that are recur args,
   ;; ie, they are not fresh ids
   ;; - each xrec is accompanied with irec ...,
   ;;   which are the indices in i+x ... needed by xrec
   ;; ASSUME: the indices are the first (stx-length (i ...)) args in i+x ...
   ;; ASSUME: indices cannot have type (TY ...), they are not recursive
   ;;         (otherwise, cannot include indices in args to find-recur/i)
   #:with (((xrec irec ...) ...) ...)
          (find-recur/i #'TY (stx-length #'(i ...)) #'(([i+x τin] ...) ...))

   ;; ---------- pre-generate other patvars; makes nested macros below easier to read
   #:with (A- ...) (generate-temporaries #'(A ...))
   #:with (i- ...) (generate-temporaries #'(i ...))
   ;; inst'ed τin and τout (with A ...)
   #:with ((τin/A ...) ...) (stx-map generate-temporaries #'((τin ...) ...))
   #:with (τout/A ...) (generate-temporaries #'(C ...))
   ; τoutA matches the A and τouti matches the i in τout/A,
   ; - ie τout/A = (TY τoutA ... τouti ...)
   ; - also, τoutA refs (ie bound-id=) CA and τouti refs i in i+x ...
   #:with ((τoutA ...) ...) (stx-map (lambda _ (generate-temporaries #'(A ...))) #'(C ...))
   #:with ((τouti ...) ...) (stx-map (lambda _ (generate-temporaries #'(i ...))) #'(C ...))
   ;; differently named `i`, to match type of P
   #:with (j ...) (generate-temporaries #'(i ...))
   ; dup (A ...) C times, again for ellipses matching
   #:with ((A*C ...) ...) (stx-map (lambda _ #'(A ...)) #'(C ...))
   #:with (C/internal ...) (generate-temporaries #'(C ...))
   #:with (m ...) (generate-temporaries #'(C ...))
   #:with (m- ...) (generate-temporaries #'(C ...))
   #:with TY- (mk-- #'TY)
   #:with TY-patexpand (mk-~ #'TY)
   #:with elim-TY (format-id #'TY "elim-~a" #'TY)
   #:with eval-TY (format-id #'TY "match-~a" #'TY)
   #:with (τm ...) (generate-temporaries #'(m ...))
   ;; these are all the generated definitions that implement the define-datatype
   #:with OUTPUT-DEFS
    #'(begin-
        ;; define the type
        (define-internal-type-constructor TY)
        ;; τi refs A ... but dont need to explicitly inst τi with A ...
        ;; due to reuse of A ... as patvars
        (define-typed-syntax (TY A ... i ...) ≫
          [⊢ A ≫ A- ⇐ τA] ...
          [⊢ i ≫ i- ⇐ τi] ...
          ----------
          [⊢ #,(syntax-property #'(TY- A- ... i- ...) 'elim-name #'elim-TY) ⇒ τ])

        ;; define structs for constructors
        ;; TODO: currently i's are included in struct fields; separate i's from i+x's
        (struct C/internal (xs) #:transparent) ...
        ;; TODO: this define should be a macro instead?
        ;; must use internal list, bc Racket is not auto-currying
        (define C (unsafe-assign-type
                   (λ/c- (A ... i+x ...) (C/internal (list i+x ...)))
                   : τC)) ...
        ;; define eliminator-form elim-TY
        ;; v = target
        ;; - infer A ... from v
        ;; P = motive
        ;; - is a (curried) fn that consumes:
        ;;   - indices i ... with type τi
        ;;   - and TY A ... i ... 
        ;;     - where A ... args is A ... inferred from v
        ;;     - and τi also instantiated with A ...
        ;; - output is a type
        ;; m = branches
        ;; - each is a fn that consumes:
        ;;   - maybe indices i ... (if they are needed by args)
        ;;   - constructor args
        ;;     - inst with A ... inferred from v
        ;;   - maybe IH for recursive args
        (define-typed-syntax (elim-TY v P m ...) ≫
          ;; target, infers A ...
          [⊢ v ≫ v- ⇒ (TY-patexpand A ... i ...)]
          
          #:do[(when debug-elim?
                 (displayln "inferred A:")
                 (displayln (stx->datum #'(A ...)))
                 (displayln "inferred i:")
                 (displayln (stx->datum #'(i ...))))]

          ;; inst τin and τout with inferred A ...
          ;; - unlike in the TY def, must explicitly instantiate here
          ;; bc these types reference a different binder, ie CA instead of A
          ;; - specifically, replace CA ... with the inferred A ... params
          ;; - don't need to instantiate τi ... bc they already reference A,
          ;;   which we reused as the pattern variable above
          #:with ((τin/A ... τout/A) ...)
                 (stx-map
                  (λ (As τs) (substs #'(A ...) As τs))
                  #'((CA ...) ...)
                  #'((τin ... τout) ...))
          
          #:do[(when debug-elim?
                 (displayln "τin/A:")
                 (displayln (stx->datum #'((τin/A ...) ...)))
                 (displayln "τout/A:")
                 (displayln (stx->datum #'(τout/A ...))))]

          ;; prop / motive
          #:do[(when debug-elim?
                 (displayln "type of motive:")
                 (displayln
                  (stx->datum
                   #'(Π ([j : τi] ...) (→ (TY A ... j ...) Type)))))]

          ;; τi here is τi above, instantiated with A ... from v-
          [⊢ P ≫ P- ⇐ (Π/c [j : τi] ... (→ (TY A ... j ...) Type))]

          ;; get the params and indices in τout/A
          ;; - dont actually need τoutA, except to find τouti
          ;; - τouti dictates what what "index" args P should be applied to
          ;;   in each method output type
          ;;     ie, it is the (app P- τouti ...) below
          ;;   It is the index, "unified" with its use in τout/A
          ;;   Eg, for empty indexed list, for index n, τouti = 0
          ;;       for non-empt indx list, for index n, τouti = (Succ 0)
          ;; ASSUMING: τoutA has shape (TY . args) (ie, unexpanded)
          #:with (((~literal TY) τoutA ... τouti ...) ...) #'(τout/A ...)

          #:do[(when debug-elim?
                 (displayln "inferred τoutA:")
                 (displayln (stx->datum #'((τoutA ...) ...)))
                 (displayln "inferred τouti:")
                 (displayln (stx->datum #'((τouti ...) ...))))]

          ;; each m is curried fn consuming 3 (possibly empty) sets of args:
          ;; 1,2) i+x  - indices of the tycon, and args of each constructor `C`
          ;;             the indices may not be included, when not needed by the xs
          ;; 3) IHs - for each xrec ... (which are a subset of i+x ...)
          #:with (τm ...)
                 #'((Π/c [i+x : τin/A] ... ; constructor args ; ASSUME: i+x includes indices
                         (→/c (app/c P- irec ... xrec) ... ; IHs
                              (app/c P- τouti ... (app/c C A*C ... i+x ...)))) ...)
                 
          #:do[(when debug-elim?
                 (displayln "τms:")
                 ;; (displayln "actual method types:")
                 ;; (pretty-print (stx->datum #'(τm ...)))
                 (displayln "expected method types:")
                 (pretty-print (stx->datum #'(τm ...)))
                 (displayln "expected method types (expanded):")
                 (stx-map 
                  (λ(c) (pretty-print (stx->datum ((current-type-eval) c))))
                  #'(τm ...)))]

          [⊢ m ≫ m- ⇐ τm] ...
          -----------
          [⊢ (eval-TY v- P- m- ...) ⇒ (app/c P- i ... v-)])

        ;; implements reduction of eliminator redexes
        (define-syntax eval-TY
          (syntax-parser
            #;[(_ . args) ;; uncomment to help debugging
             #:do[(displayln "trying to match:")(pretty-print (stx->datum #'args))]
             #:when #f #'(void)]
            [(_ (~Cons (C CA ... i+x ...)) P m ...)
             #`(app/eval/c m i+x ... (eval-TY xrec P m ...) ...)] ...
            ;; else, generate a "delayed" term
            ;; must be #%app-, not #%plain-app, ow match will not dispatch properly
            [(_ . args) #'(#%app- match/delayed 'eval-TY (void . args))])))
   ;; DEBUG: of generated defs
;   #:do[(pretty-print (stx->datum #'OUTPUT-DEFS))]
   --------
   [≻ OUTPUT-DEFS]])

