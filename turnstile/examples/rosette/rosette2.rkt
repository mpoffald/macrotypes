#lang turnstile
(extends "../stlc.rkt"
  #:except #%app →)
(reuse #%datum #:from "../stlc+union.rkt")
(reuse define-type-alias #:from "../stlc+reco+var.rkt")
(reuse define-named-type-alias #:from "../stlc+union.rkt")
(reuse void list #:from "../stlc+cons.rkt")

(provide Any Nothing
         CU U
         C→ → (for-syntax ~C→ C→?)
         Ccase-> ; TODO: symbolic case-> not supported yet
         CListof CVectorof CParamof ; TODO: symbolic Param not supported yet
         CUnit Unit
         CNegInt NegInt
         CZero Zero
         CPosInt PosInt
         CNat Nat
         CInt Int
         CFloat Float
         CNum Num
         CFalse CTrue CBool Bool
         CString String
         CStx ; symblic Stx not supported
         ;; BV types
         CBV BV
         CBVPred BVPred
         )

(require
 (prefix-in ro: rosette)
 (only-in "../stlc+union.rkt" define-named-type-alias prune+sort current-sub?)
 (prefix-in C
   (combine-in
    (only-in "../stlc+union+case.rkt"
             PosInt Zero NegInt Float True False String [U U*] U*? [case-> case->*] → →?)
    (only-in "../stlc+cons.rkt" Unit [List Listof])))
 (only-in "../stlc+union+case.rkt" [~U* ~CU*] [~case-> ~Ccase->] [~→ ~C→])
 (only-in "../stlc+cons.rkt" [~List ~CListof])
 (only-in "../stlc+reco+var.rkt" [define stlc:define] define-primop)
 (rename-in "rosette-util.rkt" [bitvector? lifted-bitvector?]))

;; copied from rosette.rkt
(define-simple-macro (define-rosette-primop op:id : ty)
  (begin-
    (require (only-in rosette [op op]))
    (define-primop op : ty)))

;; ---------------------------------
;; Concrete and Symbolic union types

(begin-for-syntax
  (define (concrete? t)
    (not (or (Any? t) (U*? t)))))

(define-base-types Any CBV CStx CSymbol)
;; CVectorof includes all vectors
;; CIVectorof includes only immutable vectors
;; CMVectorof includes only mutable vectors
(define-type-constructor CIVectorof #:arity = 1)
(define-type-constructor CMVectorof #:arity = 1)
(define-named-type-alias (CVectorof X) (CU (CIVectorof X) (CMVectorof X)))

(define-syntax (CU stx)
  (syntax-parse stx
    [(_ . tys)
     #:with tys+ (stx-map (current-type-eval) #'tys)
     #:fail-unless (stx-andmap concrete? #'tys+)
                   "CU requires concrete types"
     #'(CU* . tys+)]))

(define-named-type-alias Nothing (CU))

;; internal symbolic union constructor
(define-type-constructor U* #:arity >= 0)

;; user-facing symbolic U constructor: flattens and prunes
(define-syntax (U stx)
  (syntax-parse stx
    [(_ . tys)
     ;; canonicalize by expanding to U*, with only (sorted and pruned) leaf tys
     #:with ((~or (~U* ty1- ...) (~CU* ty2- ...) ty3-) ...) (stx-map (current-type-eval) #'tys)
     #:with tys- (prune+sort #'(ty1- ... ... ty2- ... ... ty3- ...))
     #'(U* . tys-)]))

;; ---------------------------------
;; case-> and Ccase->

;; Ccase-> must check that its subparts are concrete → types
(define-syntax (Ccase-> stx)
  (syntax-parse stx
    [(_ . tys)
     #:with tys+ (stx-map (current-type-eval) #'tys)
     #:fail-unless (stx-andmap C→? #'tys+)
                   "CU require concrete arguments"
     #'(Ccase->* . tys+)]))

;; TODO: What should case-> do when given symbolic function
;; types? Should it transform (case-> (U (C→ τ ...)) ...)
;; into (U (Ccase-> (C→ τ ...) ...)) ? What makes sense here?


;; ---------------------------------
;; Symbolic versions of types

(begin-for-syntax
  (define (add-pred stx pred)
    (set-stx-prop/preserved stx 'pred pred))
  (define (get-pred stx)
    (syntax-property stx 'pred)))

(define-syntax-parser add-predm
  [(_ stx pred) (add-pred #'stx #'pred)])

(define-named-type-alias NegInt (add-predm (U CNegInt) negative-integer?))
(define-named-type-alias Zero (add-predm (U CZero) zero-integer?))
(define-named-type-alias PosInt (add-predm (U CPosInt) positive-integer?))
(define-named-type-alias Float (U CFloat))
(define-named-type-alias String (U CString))
(define-named-type-alias Unit (add-predm (U CUnit) ro:void?))
(define-named-type-alias (CParamof X) (Ccase-> (C→ X)
                                               (C→ X CUnit)))

(define-syntax →
  (syntax-parser
    [(_ ty ...+) 
     (add-orig #'(U (C→ ty ...)) this-syntax)]))

(define-syntax define-symbolic-named-type-alias
  (syntax-parser
    [(_ Name:id Cτ:expr #:pred p?)
     #:with Cτ+ ((current-type-eval) #'Cτ)
     #:fail-when (and (not (concrete? #'Cτ+)) #'Cτ+)
                 "should be a concrete type"
     #:with CName (format-id #'Name "C~a" #'Name #:source #'Name)
     #'(begin-
         (define-named-type-alias CName Cτ)
         (define-named-type-alias Name (add-predm (U CName) p?)))]))

(define-symbolic-named-type-alias Bool (CU CFalse CTrue) #:pred ro:boolean?)
(define-symbolic-named-type-alias Nat (CU CZero CPosInt) #:pred nonnegative-integer?)
(define-symbolic-named-type-alias Int (CU CNegInt CNat) #:pred ro:integer?)
(define-symbolic-named-type-alias Num (CU CFloat CInt) #:pred ro:real?)

;; ---------------------------------
;; define-symbolic

(define-typed-syntax define-symbolic
  [(_ x:id ...+ pred : ty:type) ≫
   ;; TODO: still unsound
   [⊢ [pred ≫ pred- ⇐ : (C→ ty.norm Bool)]]
   #:with (y ...) (generate-temporaries #'(x ...))
   --------
   [_ ≻ (begin-
          (define-syntax- x (make-rename-transformer (⊢ y : ty.norm))) ...
          (ro:define-symbolic y ... pred-))]])

(define-typed-syntax define-symbolic*
  [(_ x:id ...+ pred : ty:type) ≫
   ;; TODO: still unsound
   [⊢ [pred ≫ pred- ⇐ : (C→ ty.norm Bool)]]
   #:with (y ...) (generate-temporaries #'(x ...))
   --------
   [_ ≻ (begin-
          (define-syntax- x (make-rename-transformer (⊢ y : ty.norm))) ...
          (ro:define-symbolic* y ... pred-))]])

;; TODO: support internal definition contexts
(define-typed-syntax let-symbolic
  [(_ ([(x:id ...+) pred : ty:type]) e) ≫
   [⊢ [pred ≫ pred- ⇐ : (C→ ty.norm Bool)]]
   [([x ≫ x- : ty.norm] ...) ⊢ [e ≫ e- ⇒ τ_out]]
   --------
   [⊢ [_ ≫ (ro:let-values
            ([(x- ...) (ro:let ()
                         (ro:define-symbolic x ... pred-)
                         (ro:values x ...))])
            e-) ⇒ : τ_out]]])
(define-typed-syntax let-symbolic*
  [(_ ([(x:id ...+) pred : ty:type]) e) ≫
   [⊢ [pred ≫ pred- ⇐ : (C→ ty.norm Bool)]]
   [([x ≫ x- : ty.norm] ...) ⊢ [e ≫ e- ⇒ τ_out]]
   --------
   [⊢ [_ ≫ (ro:let-values
            ([(x- ...) (ro:let ()
                         (ro:define-symbolic* x ... pred-)
                         (ro:values x ...))])
            e-) ⇒ : τ_out]]])

;; ---------------------------------
;; assert, assert-type

(define-typed-syntax assert
  [(_ e) ≫
   [⊢ [e ≫ e- ⇒ : _]]
   --------
   [⊢ [_ ≫ (ro:assert e-) ⇒ : CUnit]]]
  [(_ e m) ≫
   [⊢ [e ≫ e- ⇒ : _]]
   [⊢ [m ≫ m- ⇐ : (CU CString (C→ Nothing))]]
   --------
   [⊢ [_ ≫ (ro:assert e- m-) ⇒ : CUnit]]])

(define-typed-syntax assert-type #:datum-literals (:)
  [(_ e : ty:type) ≫
   [⊢ [e ≫ e- ⇒ : _]]
   #:with pred (get-pred #'ty.norm)
   --------
   [⊢ [_ ≫ (ro:#%app assert-pred e- pred) ⇒ : ty.norm]]])  


;; ---------------------------------
;; Racket forms

;; TODO: many of these implementations are copied code, with just the macro
;; output changed to use the ro: version. 
;; Is there a way to abstract this? macro mixin?

(define-typed-syntax define #:datum-literals (: -> →)
  [(_ x:id e) ≫
   --------
   [_ ≻ (stlc:define x e)]]
  [(_ (f [x : ty] ... (~or → ->) ty_out) e ...+) ≫
;   [⊢ [e ≫ e- ⇒ : ty_e]]
   #:with f- (generate-temporary #'f)
   --------
   [_ ≻ (begin-
          (define-syntax- f (make-rename-transformer (⊢ f- : (C→ ty ... ty_out))))
          (ro:define f- (stlc:λ ([x : ty] ...) (ann (begin e ...) : ty_out))))]])

;; ---------------------------------
;; quote

(define-typed-syntax quote
  [(_ x:id) ≫
   --------
   [⊢ [_ ≫ (quote- x) ⇒ : CSymbol]]]
  [(_ (x:id ...)) ≫
   --------
   [⊢ [_ ≫ (quote- (x ...)) ⇒ : (CListof CSymbol)]]])

;; ---------------------------------
;; Function Application

;; copied from rosette.rkt
(define-typed-syntax app #:export-as #%app
  [(_ e_fn e_arg ...) ≫
   [⊢ [e_fn ≫ e_fn- ⇒ : (~C→ ~! τ_in ... τ_out)]]
   #:with e_fn/progsrc- (replace-stx-loc #'e_fn- #'e_fn)
   #:fail-unless (stx-length=? #'[τ_in ...] #'[e_arg ...])
   (num-args-fail-msg #'e_fn #'[τ_in ...] #'[e_arg ...])
   [⊢ [e_arg ≫ e_arg- ⇐ : τ_in] ...]
   --------
   ;; TODO: use e_fn/progsrc- (currently causing "cannot use id tainted in macro trans" err)
   [⊢ [_ ≫ (ro:#%app e_fn/progsrc- e_arg- ...) ⇒ : τ_out]]]
  [(_ e_fn e_arg ...) ≫
   [⊢ [e_fn ≫ e_fn- ⇒ : (~Ccase-> ~! . (~and ty_fns ((~C→ . _) ...)))]]
   #:with e_fn/progsrc- (replace-stx-loc #'e_fn- #'e_fn)
   [⊢ [e_arg ≫ e_arg- ⇒ : τ_arg] ...]
   #:with τ_out
   (for/first ([ty_f (stx->list #'ty_fns)]
               #:when (syntax-parse ty_f
                        [(~C→ τ_in ... τ_out)
                         (and (stx-length=? #'(τ_in ...) #'(e_arg ...))
                              (typechecks? #'(τ_arg ...) #'(τ_in ...)))]))
     (syntax-parse ty_f [(~C→ _ ... t_out) #'t_out]))
   #:fail-unless (syntax-e #'τ_out)
   ; use (failing) typechecks? to get err msg
   (syntax-parse #'ty_fns
     [((~C→ τ_in ... _) ...)
      (let* ([τs_expecteds #'((τ_in ...) ...)]
             [τs_given #'(τ_arg ...)]
             [expressions #'(e_arg ...)])
        (format (string-append "type mismatch\n"
                               "  expected one of:\n"
                               "    ~a\n"
                               "  given: ~a\n"
                               "  expressions: ~a")
         (string-join
          (stx-map
           (lambda (τs_expected)
             (string-join (stx-map type->str τs_expected) ", "))
           τs_expecteds)
          "\n    ")
           (string-join (stx-map type->str τs_given) ", ")
           (string-join (map ~s (stx-map syntax->datum expressions)) ", ")))])
   --------
   [⊢ [_ ≫ (ro:#%app e_fn/progsrc- e_arg- ...) ⇒ : τ_out]]]
  [(_ e_fn e_arg ...) ≫
   [⊢ [e_fn ≫ e_fn- ⇒ : (~CU* τ_f ...)]]
   #:with e_fn/progsrc- (replace-stx-loc #'e_fn- #'e_fn)
   [⊢ [e_arg ≫ e_arg- ⇒ : τ_arg] ...]
   #:with (f a ...) (generate-temporaries #'(e_fn e_arg ...))
   [([f ≫ _ : τ_f] [a ≫ _ : τ_arg] ...)
    ⊢ [(app f a ...) ≫ _ ⇒ : τ_out]]
   ...
   --------
   [⊢ [_ ≫ (ro:#%app e_fn/progsrc- e_arg- ...) ⇒ : (CU τ_out ...)]]]
  [(_ e_fn e_arg ...) ≫
   [⊢ [e_fn ≫ e_fn- ⇒ : (~U* τ_f ...)]]
   #:with e_fn/progsrc- (replace-stx-loc #'e_fn- #'e_fn)
   [⊢ [e_arg ≫ e_arg- ⇒ : τ_arg] ...]
   #:with (f a ...) (generate-temporaries #'(e_fn e_arg ...))
   [([f ≫ _ : τ_f] [a ≫ _ : τ_arg] ...)
    ⊢ [(app f a ...) ≫ _ ⇒ : τ_out]]
   ...
   --------
   [⊢ [_ ≫ (ro:#%app e_fn/progsrc- e_arg- ...) ⇒ : (U τ_out ...)]]])

;; ---------------------------------
;; if

(define-typed-syntax if
  [(_ e_tst e1 e2) ≫
   [⊢ [e_tst ≫ e_tst- ⇒ : ty_tst]]
   #:when (concrete? #'ty_tst)
   [⊢ [e1 ≫ e1- ⇒ : ty1]]
   [⊢ [e2 ≫ e2- ⇒ : ty2]]
   #:when (and (concrete? #'ty1) (concrete? #'ty2))
   --------
   [⊢ [_ ≫ (ro:if e_tst- e1- e2-) ⇒ : (CU ty1 ty2)]]]
  [(_ e_tst e1 e2) ≫
   [⊢ [e_tst ≫ e_tst- ⇒ : _]]
   [⊢ [e1 ≫ e1- ⇒ : ty1]]
   [⊢ [e2 ≫ e2- ⇒ : ty2]]
   --------
   [⊢ [_ ≫ (ro:if e_tst- e1- e2-) ⇒ : (U ty1 ty2)]]])
   
;; ---------------------------------
;; let, etc (copied from ext-stlc.rkt)

(define-typed-syntax let
  [(let ([x e] ...) e_body) ⇐ : τ_expected ≫
   [⊢ [e ≫ e- ⇒ : τ_x] ...]
   [() ([x ≫ x- : τ_x] ...) ⊢ [e_body ≫ e_body- ⇐ : τ_expected]]
   --------
   [⊢ [_ ≫ (ro:let ([x- e-] ...) e_body-) ⇐ : _]]]
  [(let ([x e] ...) e_body) ≫
   [⊢ [e ≫ e- ⇒ : τ_x] ...]
   [() ([x ≫ x- : τ_x] ...) ⊢ [e_body ≫ e_body- ⇒ : τ_body]]
   --------
   [⊢ [_ ≫ (ro:let ([x- e-] ...) e_body-) ⇒ : τ_body]]])

; dont need to manually transfer expected type
; result template automatically propagates properties
; - only need to transfer expected type when local expanding an expression
;   - see let/tc
(define-typed-syntax let*
  [(let* () e_body) ≫
   --------
   [_ ≻ e_body]]
  [(let* ([x e] [x_rst e_rst] ...) e_body) ≫
   --------
   [_ ≻ (let ([x e]) (let* ([x_rst e_rst] ...) e_body))]])

;; --------------------
;; begin

(define-typed-syntax begin
  [(begin e_unit ... e) ⇐ : τ_expected ≫
   [⊢ [e_unit ≫ e_unit- ⇒ : _] ...]
   [⊢ [e ≫ e- ⇐ : τ_expected]]
   --------
   [⊢ [_ ≫ (ro:begin e_unit- ... e-) ⇐ : _]]]
  [(begin e_unit ... e) ≫
   [⊢ [e_unit ≫ e_unit- ⇒ : _] ...]
   [⊢ [e ≫ e- ⇒ : τ_e]]
   --------
   [⊢ [_ ≫ (ro:begin e_unit- ... e-) ⇒ : τ_e]]])

;; ---------------------------------
;; vector

(define-typed-syntax vector
  [(_ e ...) ≫
   [⊢ [e ≫ e- ⇒ : τ] ...]
   --------
   [⊢ [_ ≫ (ro:vector e- ...) ⇒ : #,(if (stx-andmap concrete? #'(τ ...))
                                        #'(CMVectorof (CU τ ...))
                                        #'(CMVectorof (U τ ...)))]]])
(define-typed-syntax vector-immutable
  [(_ e ...) ≫
   [⊢ [e ≫ e- ⇒ : τ] ...]
   --------
   [⊢ [_ ≫ (ro:vector-immutable e- ...) ⇒ : (if (stx-andmap concrete? #'(τ ...))
                                                #'(CIVectorof (CU τ ...))
                                                #'(CIVectorof (U τ ...)))]]])
;; ---------------------------------
;; Types for built-in operations

(define-rosette-primop equal? : (C→ Any Any Bool))
(define-rosette-primop eq? : (C→ Any Any Bool))
(define-rosette-primop error : (C→ (CU CString CSymbol) Nothing))

(define-rosette-primop pi : CNum)

(define-rosette-primop add1 : (Ccase-> (C→ CNegInt (CU CNegInt CZero))
                                       (C→ NegInt (U NegInt Zero))
                                       (C→ CZero CPosInt)
                                       (C→ Zero PosInt)
                                       (C→ CPosInt CPosInt)
                                       (C→ PosInt PosInt)
                                       (C→ CNat CPosInt)
                                       (C→ Nat PosInt)
                                       (C→ CInt CInt)
                                       (C→ Int Int)))
(define-rosette-primop sub1 : (Ccase-> (C→ CNegInt CNegInt)
                                       (C→ NegInt NegInt)
                                       (C→ CZero CNegInt)
                                       (C→ Zero NegInt)
                                       (C→ CPosInt CNat)
                                       (C→ PosInt Nat)
                                       (C→ CNat CInt)
                                       (C→ Nat Int)
                                       (C→ CInt CInt)
                                       (C→ Int Int)))
(define-rosette-primop + : (Ccase-> (C→ CNat CNat CNat)
                                    (C→ CNat CNat CNat CNat)
                                    (C→ CNat CNat CNat CNat CNat)
                                    (C→ Nat Nat Nat)
                                    (C→ Nat Nat Nat Nat)
                                    (C→ Nat Nat Nat Nat Nat)
                                    (C→ CInt CInt CInt)
                                    (C→ CInt CInt CInt CInt)
                                    (C→ CInt CInt CInt CInt CInt)
                                    (C→ Int Int Int)
                                    (C→ Int Int Int Int)
                                    (C→ Int Int Int Int Int)
                                    (C→ CNum CNum CNum)
                                    (C→ CNum CNum CNum CNum)
                                    (C→ CNum CNum CNum CNum CNum)
                                    (C→ Num Num Num)
                                    (C→ Num Num Num Num)
                                    (C→ Num Num Num Num Num)))
(define-rosette-primop * : (Ccase-> (C→ CNat CNat CNat)
                                    (C→ CNat CNat CNat CNat)
                                    (C→ CNat CNat CNat CNat CNat)
                                    (C→ Nat Nat Nat)
                                    (C→ Nat Nat Nat Nat)
                                    (C→ Nat Nat Nat Nat Nat)
                                    (C→ CInt CInt CInt)
                                    (C→ CInt CInt CInt CInt)
                                    (C→ CInt CInt CInt CInt CInt)
                                    (C→ Int Int Int)
                                    (C→ Int Int Int Int)
                                    (C→ Int Int Int Int Int)
                                    (C→ CNum CNum CNum)
                                    (C→ CNum CNum CNum CNum)
                                    (C→ CNum CNum CNum CNum CNum)
                                    (C→ Num Num Num)
                                    (C→ Num Num Num Num)
                                    (C→ Num Num Num Num Num)))
(define-rosette-primop = : (Ccase-> (C→ CNum CNum CBool)
                                    (C→ Num Num Bool)))
(define-rosette-primop < : (Ccase-> (C→ CNum CNum CBool)
                                    (C→ Num Num Bool)))
(define-rosette-primop > : (Ccase-> (C→ CNum CNum CBool)
                                    (C→ Num Num Bool)))
(define-rosette-primop <= : (Ccase-> (C→ CNum CNum CBool)
                                     (C→ Num Num Bool)))
(define-rosette-primop >= : (Ccase-> (C→ CNum CNum CBool)
                                     (C→ Num Num Bool)))

(define-rosette-primop abs : (Ccase-> (C→ CPosInt CPosInt)
                                      (C→ PosInt PosInt)
                                      (C→ CZero CZero)
                                      (C→ Zero Zero)
                                      (C→ CNegInt CPosInt)
                                      (C→ NegInt PosInt)
                                      (C→ CInt CInt)
                                      (C→ Int Int)
                                      (C→ CNum CNum)
                                      (C→ Num Num)))

(define-rosette-primop not : (C→ Any Bool))
(define-rosette-primop false? : (C→ Any Bool))

;; TODO: fix types of these predicates
(define-rosette-primop boolean? : (C→ Any Bool))
(define-rosette-primop integer? : (C→ Any Bool))
(define-rosette-primop real? : (C→ Any Bool))
(define-rosette-primop positive? : (Ccase-> (C→ CNum CBool)
                                            (C→ Num Bool)))

;; rosette-specific
(define-rosette-primop asserts : (C→ (CListof Bool)))
(define-rosette-primop clear-asserts! : (C→ CUnit))

;; ---------------------------------
;; BV Types and Operations

;; this must be a macro in order to support Racket's overloaded set/get
;; parameter patterns
(define-typed-syntax current-bitwidth
  [_:id ≫
   --------
   [⊢ [_ ≫ ro:current-bitwidth ⇒ : (CParamof (CU CFalse CPosInt))]]]
  [(_) ≫
   --------
   [⊢ [_ ≫ (ro:current-bitwidth) ⇒ : (CU CFalse CPosInt)]]]
  [(_ e) ≫
   [⊢ [e ≫ e- ⇐ : (CU CFalse CPosInt)]]
   --------
   [⊢ [_ ≫ (ro:current-bitwidth e-) ⇒ : CUnit]]])

(define-named-type-alias BV (add-predm (U CBV) bv?))
(define-symbolic-named-type-alias BVPred (C→ BV Bool) #:pred lifted-bitvector?)

(define-rosette-primop bv : (Ccase-> (C→ CInt CBVPred CBV)
                                     (C→ CInt CPosInt CBV)))
(define-rosette-primop bv? : (C→ Any Bool))
(define-rosette-primop bitvector : (C→ CPosInt CBVPred))
(define-rosette-primop bitvector? : (C→ Any Bool))

(define-rosette-primop bveq : (C→ BV BV Bool))
(define-rosette-primop bvslt : (C→ BV BV Bool))
(define-rosette-primop bvult : (C→ BV BV Bool))
(define-rosette-primop bvsle : (C→ BV BV Bool))
(define-rosette-primop bvule : (C→ BV BV Bool))
(define-rosette-primop bvsgt : (C→ BV BV Bool))
(define-rosette-primop bvugt : (C→ BV BV Bool))
(define-rosette-primop bvsge : (C→ BV BV Bool))
(define-rosette-primop bvuge : (C→ BV BV Bool))

(define-rosette-primop bvnot : (C→ BV BV))

(define-rosette-primop bvand : (C→ BV BV BV))
(define-rosette-primop bvor : (C→ BV BV BV))
(define-rosette-primop bvxor : (C→ BV BV BV))

(define-rosette-primop bvshl : (C→ BV BV BV))
(define-rosette-primop bvlshr : (C→ BV BV BV))
(define-rosette-primop bvashr : (C→ BV BV BV))
(define-rosette-primop bvneg : (C→ BV BV))

(define-rosette-primop bvadd : (C→ BV BV BV))
(define-rosette-primop bvsub : (C→ BV BV BV))
(define-rosette-primop bvmul : (C→ BV BV BV))

(define-rosette-primop bvsdiv : (C→ BV BV BV))
(define-rosette-primop bvudiv : (C→ BV BV BV))
(define-rosette-primop bvsrem : (C→ BV BV BV))
(define-rosette-primop bvurem : (C→ BV BV BV))
(define-rosette-primop bvsmod : (C→ BV BV BV))

(define-rosette-primop concat : (C→ BV BV BV))
(define-rosette-primop extract : (C→ Int Int BV BV))
(define-rosette-primop sign-extend : (C→ BV CBVPred BV))
(define-rosette-primop zero-extend : (C→ BV BVPred BV))

(define-rosette-primop bitvector->integer : (C→ BV Int))
(define-rosette-primop bitvector->natural : (C→ BV Nat))
(define-rosette-primop integer->bitvector : (C→ Int BVPred BV))

(define-rosette-primop bitvector-size : (C→ CBVPred CPosInt))


;; ---------------------------------
;; Logic operators

(define-rosette-primop ! : (C→ Bool Bool))
(define-rosette-primop <=> : (C→ Bool Bool Bool))

(define-typed-syntax &&
  [(_ e ...) ≫
   [⊢ [e ≫ e- ⇐ : Bool] ...]
   --------
   [⊢ [_ ≫ (ro:&& e- ...) ⇒ : Bool]]])
(define-typed-syntax ||
  [(_ e ...) ≫
   [⊢ [e ≫ e- ⇐ : Bool] ...]
   --------
   [⊢ [_ ≫ (ro:|| e- ...) ⇒ : Bool]]])

;; ---------------------------------
;; solver forms

(define-base-types CSolution CPict)

(define-rosette-primop core : (C→ Any Any))
(define-rosette-primop sat? : (C→ Any Bool))
(define-rosette-primop unsat? : (C→ Any Bool))
(define-rosette-primop unsat : (Ccase-> (C→ CSolution)
                                        (C→ (CListof Bool) CSolution)))
(define-rosette-primop forall : (C→ (CListof Any) Bool Bool))
(define-rosette-primop exists : (C→ (CListof Any) Bool Bool))

(define-typed-syntax verify
  [(_ e) ≫
   [⊢ [e ≫ e- ⇒ : _]]
   --------
   [⊢ [_ ≫ (ro:verify e-) ⇒ : CSolution]]]
  [(_ #:assume ae #:guarantee ge) ≫
   [⊢ [ae ≫ ae- ⇒ : _]]
   [⊢ [ge ≫ ge- ⇒ : _]]
   --------
   [⊢ [_ ≫ (ro:verify #:assume ae- #:guarantee ge-) ⇒ : CSolution]]])

(define-typed-syntax evaluate
  [(_ v s) ≫
   [⊢ [v ≫ v- ⇒ : ty]]
   [⊢ [s ≫ s- ⇐ : CSolution]]
   --------
   [⊢ [_ ≫ (ro:evaluate v- s-) ⇒ : ty]]])


(define-typed-syntax synthesize
  [(_ #:forall ie #:guarantee ge) ≫
   [⊢ [ie ≫ ie- ⇐ : (CListof Any)]]
   [⊢ [ge ≫ ge- ⇒ : _]]
   --------
   [⊢ [_ ≫ (ro:synthesize #:forall ie- #:guarantee ge-) ⇒ : CSolution]]]
  [(_ #:forall ie #:assume ae #:guarantee ge) ≫
   [⊢ [ie ≫ ie- ⇐ : (CListof Any)]]
   [⊢ [ae ≫ ae- ⇒ : _]]
   [⊢ [ge ≫ ge- ⇒ : _]]
   --------
   [⊢ [_ ≫ (ro:synthesize #:forall ie- #:assume ae- #:guarantee ge-) ⇒ : CSolution]]])

(define-typed-syntax solve
  [(_ e) ≫
   [⊢ [e ≫ e- ⇒ : _]]
   --------
   [⊢ [_ ≫ (ro:solve e-) ⇒ : CSolution]]])

;; ---------------------------------
;; Subtyping

(begin-for-syntax
  (define (sub? t1 t2)
    ; need this because recursive calls made with unexpanded types
   ;; (define τ1 ((current-type-eval) t1))
   ;; (define τ2 ((current-type-eval) t2))
    ;; (printf "t1 = ~a\n" (syntax->datum t1))
    ;; (printf "t2 = ~a\n" (syntax->datum t2))
    (or 
     (Any? t2)
     ((current-type=?) t1 t2)
     (syntax-parse (list t1 t2)
       [((~CListof ty1) (~CListof ty2))
        ((current-sub?) #'ty1 #'ty2)]
       ;; vectors, only immutable vectors are invariant
       [((~CIVectorof . tys1) (~CIVectorof . tys2))
        (stx-andmap (current-sub?) #'tys1 #'tys2)]
       ; 2 U types, subtype = subset
       [((~CU* . ts1) _)
        (for/and ([t (stx->list #'ts1)])
          ((current-sub?) t t2))]
       [((~U* . ts1) _)
        (and
         (not (concrete? t2))
         (for/and ([t (stx->list #'ts1)])
           ((current-sub?) t t2)))]
       ; 1 U type, 1 non-U type. subtype = member
       [(_ (~CU* . ts2))
        #:when (not (or (U*? t1) (CU*? t1)))
        (for/or ([t (stx->list #'ts2)])
          ((current-sub?) t1 t))]
       [(_ (~U* . ts2))
        #:when (not (or (U*? t1) (CU*? t1)))
        (for/or ([t (stx->list #'ts2)])
          ((current-sub?) t1 t))]
       ; 2 case-> types, subtype = subset
       [(_ (~Ccase-> . ts2))
        (for/and ([t (stx->list #'ts2)])
          ((current-sub?) t1 t))]
       ; 1 case-> , 1 non-case->
       [((~Ccase-> . ts1) _)
        (for/or ([t (stx->list #'ts1)])
          ((current-sub?) t t2))]
       [((~C→ s1 ... s2) (~C→ t1 ... t2))
        (and (subs? #'(t1 ...) #'(s1 ...))
             ((current-sub?) #'s2 #'t2))]
       [_ #f])))
  (current-sub? sub?)
  (current-typecheck-relation sub?)
  (define (subs? τs1 τs2)
    (and (stx-length=? τs1 τs2)
         (stx-andmap (current-sub?) τs1 τs2))))