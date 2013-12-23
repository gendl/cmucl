;;; -*- Package: ARM -*-
;;;
;;; **********************************************************************
;;; This code was written as part of the CMU Common Lisp project at
;;; Carnegie Mellon University, and has been placed in the public domain.
;;;
(ext:file-comment
  "$Header: src/compiler/arm/alloc.lisp $")
;;;
;;; **********************************************************************
;;;
;;; Allocation VOPs for the SPARC port.
;;;
;;; Written by William Lott.
;;; 

(in-package "ARM")
(intl:textdomain "cmucl-arm-vm")

;;;; Dynamic-Extent.

;;;
;;; Take an arg where to move the stack pointer instead of returning
;;; it via :results, because the former generates a single move.
;;;
(define-vop (%dynamic-extent-start)
  (:args (saved-stack-pointer :scs (any-reg control-stack)))
  (:results)
  (:policy :safe)
  (:generator 0
    (emit-not-implemented)))

(define-vop (%dynamic-extent-end)
  (:args (saved-stack-pointer :scs (any-reg control-stack)))
  (:results)
  (:policy :safe)
  (:generator 0
    (emit-not-implemented)))

;;;; LIST and LIST*

(define-vop (list-or-list*)
  (:args (things :more t))
  (:temporary (:scs (descriptor-reg) :type list) ptr)
  (:temporary (:scs (descriptor-reg)) temp)
  (:temporary (:scs (descriptor-reg) :type list :to (:result 0) :target result)
	      res)
  (:temporary (:scs (non-descriptor-reg)) alloc-temp)
  (:info num dynamic-extent)
  (:results (result :scs (descriptor-reg)))
  (:variant-vars star)
  (:policy :safe)
  (:generator 0
    (emit-not-implemented)))

(define-vop (list list-or-list*)
  (:variant nil))

(define-vop (list* list-or-list*)
  (:variant t))


;;;; Special purpose inline allocators.

(define-vop (allocate-code-object)
  (:args (boxed-arg :scs (any-reg))
	 (unboxed-arg :scs (any-reg)))
  (:results (result :scs (descriptor-reg)))
  (:temporary (:scs (non-descriptor-reg)) ndescr)
  (:temporary (:scs (non-descriptor-reg)) size)
  (:temporary (:scs (any-reg) :from (:argument 0)) boxed)
  (:temporary (:scs (non-descriptor-reg) :from (:argument 1)) unboxed)
  (:generator 100
    (emit-not-implemented)))

(define-vop (make-fdefn)
  (:args (name :scs (descriptor-reg) :to :eval))
  (:temporary (:scs (non-descriptor-reg)) temp)
  (:results (result :scs (descriptor-reg) :from :argument))
  (:policy :fast-safe)
  (:translate make-fdefn)
  (:generator 37
    (emit-not-implemented)))


(define-vop (make-closure)
  (:args (function :to :save :scs (descriptor-reg)))
  (:info length dynamic-extent)
  (:temporary (:scs (non-descriptor-reg)) temp)
  (:results (result :scs (descriptor-reg)))
  (:generator 10
    (emit-not-implemented)))

;;; The compiler likes to be able to directly make value cells.
;;; 
(define-vop (make-value-cell)
  (:args (value :to :save :scs (descriptor-reg any-reg)))
  (:temporary (:scs (non-descriptor-reg)) temp)
  (:results (result :scs (descriptor-reg)))
  (:generator 10
    (emit-not-implemented)))



;;;; Automatic allocators for primitive objects.

(define-vop (make-unbound-marker)
  (:args)
  (:results (result :scs (any-reg)))
  (:generator 1
    (inst li result unbound-marker-type)))

(define-vop (fixed-alloc)
  (:args)
  (:info name words type lowtag dynamic-extent)
  (:ignore name)
  (:results (result :scs (descriptor-reg)))
  (:temporary (:scs (non-descriptor-reg)) temp)
  (:generator 4
    (with-fixed-allocation (result temp type words :lowtag lowtag :stack-p dynamic-extent)
      )))

(define-vop (var-alloc)
  (:args (extra :scs (any-reg)))
  (:arg-types positive-fixnum)
  (:info name words type lowtag)
  (:ignore name)
  (:results (result :scs (descriptor-reg)))
  (:temporary (:scs (any-reg)) bytes)
  (:temporary (:scs (non-descriptor-reg)) header)
  (:temporary (:scs (any-reg)) temp)
  (:generator 6
    (emit-not-implemented)))
