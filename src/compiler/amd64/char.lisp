;;; -*- Mode: LISP; Syntax: Common-Lisp; Base: 10; Package: x86 -*-
;;;
;;; **********************************************************************
;;; This code was written as part of the CMU Common Lisp project at
;;; Carnegie Mellon University, and has been placed in the public domain.
;;; If you want to use this code or any part of CMU Common Lisp, please contact
;;; Scott Fahlman or slisp-group@cs.cmu.edu.
;;;
(ext:file-comment
 "$Header: src/compiler/amd64/char.lisp $")
;;;
;;; **********************************************************************
;;; 
;;; This file contains the x86 VM definition of character operations.
;;;
;;; Written by Rob MacLachlan
;;; Converted for the MIPS R2000 by Christopher Hoover.
;;; And then to the SPARC by William Lott.
;;; And then to the x86, again by William.
;;;
;;; Debugged by Paul F. Werkowski, June-95.
;;; Enhancements/debugging by Douglas T. Crosher 1996,1997.
;;;

(in-package :amd64)


;;;; Moves and coercions:

;;; Move a tagged char to an untagged representation.
;;;
(define-vop (move-to-base-char)
  (:args (x :scs (any-reg control-stack) :target y))
  (:results (y :scs (base-char-reg)))
  (:note _N"character untagging")
  (:generator 1
    (move y x)
    (inst shr y type-bits)))
;;;
(define-move-vop move-to-base-char :move
  (any-reg control-stack) (base-char-reg))


;;; Move an untagged char to a tagged representation.
;;;
(define-vop (move-from-base-char)
  (:args (x :scs (base-char-reg base-char-stack) :target y))
  (:results (y :scs (any-reg descriptor-reg)))
  (:note _N"character tagging")
  (:generator 1
    (move y x)
    (inst shl y type-bits)
    (inst or y base-char-type)))

;;;
(define-move-vop move-from-base-char :move
  (base-char-reg base-char-stack) (any-reg descriptor-reg))

;;; Move untagged base-char values.
;;;
(define-vop (base-char-move)
  (:args (x :target y
	    :scs (base-char-reg)
	    :load-if (not (location= x y))))
  (:results (y :scs (base-char-reg base-char-stack)
	       :load-if (not (location= x y))))
  (:note _N"character move")
  (:effects)
  (:affected)
  (:generator 0
    (move y x)))
;;;
(define-move-vop base-char-move :move
  (base-char-reg) (base-char-reg base-char-stack))


;;; Move untagged base-char arguments/return-values.
;;;
(define-vop (move-base-char-argument)
  (:args (x :target y
	    :scs (base-char-reg))
	 (fp :scs (any-reg)
	     :load-if (not (sc-is y base-char-reg))))
  (:results (y))
  (:note _N"character arg move")
  (:generator 0
    (sc-case y
      (base-char-reg
       (move y x))
      (base-char-stack
       (storew x fp (- (1+ (tn-offset y))))))))
;;;
(define-move-vop move-base-char-argument :move-argument
  (any-reg base-char-reg) (base-char-reg))


;;; Use standard MOVE-ARGUMENT + coercion to move an untagged base-char
;;; to a descriptor passing location.
;;;
(define-move-vop move-argument :move-argument
  (base-char-reg) (any-reg descriptor-reg))



;;;; Other operations:

(define-vop (char-code)
  (:translate char-code)
  (:policy :fast-safe)
  (:args (ch :scs (base-char-reg base-char-stack) :target res))
  (:arg-types base-char)
  (:results (res :scs (unsigned-reg)))
  (:result-types positive-fixnum)
  (:generator 1
    (move res ch)))

(define-vop (code-char)
  (:translate code-char)
  (:policy :fast-safe)
  (:args (code :scs (unsigned-reg control-stack) :target res))
  (:arg-types positive-fixnum)
  (:results (res :scs (base-char-reg)))
  (:result-types base-char)
  (:generator 1
    (move res code)))


;;; Comparison of base-chars.
;;;
(define-vop (base-char-compare)
  (:args (x :scs (base-char-reg base-char-stack))
	 (y :scs (base-char-reg)
	    :load-if (not (and (sc-is x base-char-reg)
			       (sc-is y base-char-stack)))))
  (:arg-types base-char base-char)
  (:conditional)
  (:info target not-p)
  (:policy :fast-safe)
  (:note _N"inline comparison")
  (:variant-vars condition not-condition)
  (:generator 3
    (inst cmp x y)
    (inst jmp (if not-p not-condition condition) target)))

(define-vop (fast-char=/base-char base-char-compare)
  (:translate char=)
  (:variant :e :ne))

(define-vop (fast-char</base-char base-char-compare)
  (:translate char<)
  (:variant :b :nb))

(define-vop (fast-char>/base-char base-char-compare)
  (:translate char>)
  (:variant :a :na))

(define-vop (base-char-compare-c)
  (:args (x :scs (base-char-reg)))
  (:arg-types base-char (:constant base-char))
  (:conditional)
  (:info target not-p y)
  (:policy :fast-safe)
  (:note _N"inline comparison")
  (:variant-vars condition not-condition)
  (:generator 2
    (inst cmp x (char-code y))
    (inst jmp (if not-p not-condition condition) target)))

(define-vop (fast-char=-c/base-char base-char-compare-c)
  (:translate char=)
  (:variant :eq :ne))

(define-vop (fast-char<-c/base-char base-char-compare-c)
  (:translate char<)
  (:variant :b :nb))

(define-vop (fast-char>-c/base-char base-char-compare-c)
  (:translate char>)
  (:variant :a :na))

