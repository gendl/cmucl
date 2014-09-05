;;; -*- Package: SPARC -*-
;;;
;;; **********************************************************************
;;; This code was written as part of the CMU Common Lisp project at
;;; Carnegie Mellon University, and has been placed in the public domain.
;;;
(ext:file-comment
  "$Header: src/compiler/sparc/float.lisp $")
;;;
;;; **********************************************************************
;;;
;;; This file contains floating point support for the MIPS.
;;;
;;; Written by Rob MacLachlan
;;; Sparc conversion by William Lott.
;;; Complex-float and long-float support by Douglas Crosher 1998.
;;;
(in-package "SPARC")
(intl:textdomain "cmucl-sparc-vm")


;;;; Move functions:

(define-move-function (load-single 1) (vop x y)
  ((single-stack) (single-reg))
  (inst ldf y (current-nfp-tn vop) (* (tn-offset x) vm:word-bytes)))

(define-move-function (store-single 1) (vop x y)
  ((single-reg) (single-stack))
  (inst stf x (current-nfp-tn vop) (* (tn-offset y) vm:word-bytes)))


(define-move-function (load-double 2) (vop x y)
  ((double-stack) (double-reg))
  (let ((nfp (current-nfp-tn vop))
	(offset (* (tn-offset x) vm:word-bytes)))
    (inst lddf y nfp offset)))

(define-move-function (store-double 2) (vop x y)
  ((double-reg) (double-stack))
  (let ((nfp (current-nfp-tn vop))
	(offset (* (tn-offset y) vm:word-bytes)))
    (inst stdf x nfp offset)))

;;; The offset may be an integer or a TN in which case it will be
;;; temporarily modified but is restored if restore-offset is true.
;;;
(defun load-long-reg (reg base offset &optional (restore-offset t))
  (if (backend-featurep :sparc-v9)
      (inst ldqf reg base offset)
      (let ((reg0 (make-random-tn :kind :normal
				  :sc (sc-or-lose 'double-reg *backend*)
				  :offset (tn-offset reg)))
	    (reg2 (make-random-tn :kind :normal
				  :sc (sc-or-lose 'double-reg *backend*)
				  :offset (+ 2 (tn-offset reg)))))
	(cond ((integerp offset)
	       (inst lddf reg0 base offset)
	       (inst lddf reg2 base (+ offset (* 2 vm:word-bytes))))
	      (t
	       (inst lddf reg0 base offset)
	       (inst add offset (* 2 vm:word-bytes))
	       (inst lddf reg2 base offset)
	       (when restore-offset
		 (inst sub offset (* 2 vm:word-bytes))))))))

#+long-float
(define-move-function (load-long 2) (vop x y)
  ((long-stack) (long-reg))
  (let ((nfp (current-nfp-tn vop))
	(offset (* (tn-offset x) vm:word-bytes)))
    (load-long-reg y nfp offset)))

;;; The offset may be an integer or a TN in which case it will be
;;; temporarily modified but is restored if restore-offset is true.
;;;
(defun store-long-reg (reg base offset &optional (restore-offset t))
  (if (backend-featurep :sparc-v9)
      (inst stqf reg base offset)
      (let ((reg0 (make-random-tn :kind :normal
				  :sc (sc-or-lose 'double-reg *backend*)
				  :offset (tn-offset reg)))
	    (reg2 (make-random-tn :kind :normal
				  :sc (sc-or-lose 'double-reg *backend*)
				  :offset (+ 2 (tn-offset reg)))))
	(cond ((integerp offset)
	       (inst stdf reg0 base offset)
	       (inst stdf reg2 base (+ offset (* 2 vm:word-bytes))))
	      (t
	       (inst stdf reg0 base offset)
	       (inst add offset (* 2 vm:word-bytes))
	       (inst stdf reg2 base offset)
	       (when restore-offset
		 (inst sub offset (* 2 vm:word-bytes))))))))

#+long-float
(define-move-function (store-long 2) (vop x y)
  ((long-reg) (long-stack))
  (let ((nfp (current-nfp-tn vop))
	(offset (* (tn-offset y) vm:word-bytes)))
    (store-long-reg x nfp offset)))


;;;; Move VOPs:

;;; Exploit the V9 double-float move instruction. This is conditional
;;; on the :sparc-v9 feature.
(defun move-double-reg (dst src)
  (cond ((backend-featurep :sparc-v9)
	 (unless (location= dst src)
	   (inst fmovd dst src)))
	(t
	 (dotimes (i 2)
	   (let ((dst (make-random-tn :kind :normal
				      :sc (sc-or-lose 'single-reg *backend*)
				      :offset (+ i (tn-offset dst))))
		 (src (make-random-tn :kind :normal
				      :sc (sc-or-lose 'single-reg *backend*)
				      :offset (+ i (tn-offset src)))))
	     (inst fmovs dst src))))))

;;; Exploit the V9 long-float move instruction. This is conditional
;;; on the :sparc-v9 feature.
(defun move-long-reg (dst src)
  (cond ((backend-featurep :sparc-v9)
	 (inst fmovq dst src))
	(t
	 (dotimes (i 4)
	   (let ((dst (make-random-tn :kind :normal
				      :sc (sc-or-lose 'single-reg *backend*)
				      :offset (+ i (tn-offset dst))))
		 (src (make-random-tn :kind :normal
				      :sc (sc-or-lose 'single-reg *backend*)
				      :offset (+ i (tn-offset src)))))
	     (inst fmovs dst src))))))

(macrolet ((frob (vop sc format)
	     `(progn
		(define-vop (,vop)
		  (:args (x :scs (,sc)
			    :target y
			    :load-if (not (location= x y))))
		  (:results (y :scs (,sc)
			       :load-if (not (location= x y))))
		  (:note _N"float move")
		  (:generator 0
		    (unless (location= y x)
		      ,@(ecase format
			  (:single `((inst fmovs y x)))
			  (:double `((move-double-reg y x)))
			  (:long `((move-long-reg y x)))))))
		(define-move-vop ,vop :move (,sc) (,sc)))))
  (frob single-move single-reg :single)
  (frob double-move double-reg :double)
  #+long-float
  (frob long-move long-reg :long))


(define-vop (move-from-float)
  (:args (x :to :save))
  (:results (y))
  (:note _N"float to pointer coercion")
  (:temporary (:scs (non-descriptor-reg)) ndescr)
  (:variant-vars format size type data)
  (:generator 13
    (with-fixed-allocation (y ndescr type size))
    (ecase format
      (:single
       (inst stf x y (- (* data vm:word-bytes) vm:other-pointer-type)))
      (:double
       (inst stdf x y (- (* data vm:word-bytes) vm:other-pointer-type)))
      (:long
       (store-long-reg x y (- (* data vm:word-bytes)
			      vm:other-pointer-type))))))

(macrolet ((frob (name sc &rest args)
	     `(progn
		(define-vop (,name move-from-float)
		  (:args (x :scs (,sc) :to :save))
		  (:results (y :scs (descriptor-reg)))
		  (:variant ,@args))
		(define-move-vop ,name :move (,sc) (descriptor-reg)))))
  (frob move-from-single single-reg :single
    vm:single-float-size vm:single-float-type vm:single-float-value-slot)
  (frob move-from-double double-reg :double
    vm:double-float-size vm:double-float-type vm:double-float-value-slot)
  #+long-float
  (frob move-from-long long-reg	:long
     vm:long-float-size vm:long-float-type vm:long-float-value-slot))

(macrolet ((frob (name sc format value)
	     `(progn
		(define-vop (,name)
		  (:args (x :scs (descriptor-reg)))
		  (:results (y :scs (,sc)))
		  (:note _N"pointer to float coercion")
		  (:generator 2
		    (inst ,(ecase format
			     (:single 'ldf)
			     (:double 'lddf))
			  y x
			  (- (* ,value vm:word-bytes) vm:other-pointer-type))))
		(define-move-vop ,name :move (descriptor-reg) (,sc)))))
  (frob move-to-single single-reg :single vm:single-float-value-slot)
  (frob move-to-double double-reg :double vm:double-float-value-slot))

#+long-float
(define-vop (move-to-long)
  (:args (x :scs (descriptor-reg)))
  (:results (y :scs (long-reg)))
  (:note _N"pointer to float coercion")
  (:generator 2
    (load-long-reg y x (- (* vm:long-float-value-slot vm:word-bytes)
			  vm:other-pointer-type))))
#+long-float
(define-move-vop move-to-long :move (descriptor-reg) (long-reg))

(macrolet ((frob (name sc stack-sc format)
	     `(progn
		(define-vop (,name)
		  (:args (x :scs (,sc) :target y)
			 (nfp :scs (any-reg)
			      :load-if (not (sc-is y ,sc))))
		  (:results (y))
		  (:note _N"float argument move")
		  (:generator ,(ecase format (:single 1) (:double 2))
		    (sc-case y
		      (,sc
		       (unless (location= x y)
			 ,@(ecase format
			     (:single '((inst fmovs y x)))
			     (:double '((move-double-reg y x))))))
		      (,stack-sc
		       (let ((offset (* (tn-offset y) vm:word-bytes)))
			 (inst ,(ecase format
				  (:single 'stf)
				  (:double 'stdf))
			       x nfp offset))))))
		(define-move-vop ,name :move-argument
		  (,sc descriptor-reg) (,sc)))))
  (frob move-single-float-argument single-reg single-stack :single)
  (frob move-double-float-argument double-reg double-stack :double))

#+long-float
(define-vop (move-long-float-argument)
  (:args (x :scs (long-reg) :target y)
	 (nfp :scs (any-reg) :load-if (not (sc-is y long-reg))))
  (:results (y))
  (:note _N"float argument move")
  (:generator 3
    (sc-case y
      (long-reg
       (unless (location= x y)
	 (move-long-reg y x)))
      (long-stack
       (let ((offset (* (tn-offset y) vm:word-bytes)))
	 (store-long-reg x nfp offset))))))
;;;
#+long-float
(define-move-vop move-long-float-argument :move-argument
  (long-reg descriptor-reg) (long-reg))


;;;; Complex float move functions

(defun complex-single-reg-real-tn (x)
  (make-random-tn :kind :normal :sc (sc-or-lose 'single-reg *backend*)
		  :offset (tn-offset x)))
(defun complex-single-reg-imag-tn (x)
  (make-random-tn :kind :normal :sc (sc-or-lose 'single-reg *backend*)
		  :offset (1+ (tn-offset x))))

(defun complex-double-reg-real-tn (x)
  (make-random-tn :kind :normal :sc (sc-or-lose 'double-reg *backend*)
		  :offset (tn-offset x)))
(defun complex-double-reg-imag-tn (x)
  (make-random-tn :kind :normal :sc (sc-or-lose 'double-reg *backend*)
		  :offset (+ (tn-offset x) 2)))

#+long-float
(defun complex-long-reg-real-tn (x)
  (make-random-tn :kind :normal :sc (sc-or-lose 'long-reg *backend*)
		  :offset (tn-offset x)))
#+long-float
(defun complex-long-reg-imag-tn (x)
  (make-random-tn :kind :normal :sc (sc-or-lose 'long-reg *backend*)
		  :offset (+ (tn-offset x) 4)))

#+double-double
(progn
(defun complex-double-double-reg-real-hi-tn (x)
  (make-random-tn :kind :normal :sc (sc-or-lose 'double-reg *backend*)
		  :offset (tn-offset x)))
(defun complex-double-double-reg-real-lo-tn (x)
  (make-random-tn :kind :normal :sc (sc-or-lose 'double-reg *backend*)
		  :offset (+ 2 (tn-offset x))))
(defun complex-double-double-reg-imag-hi-tn (x)
  (make-random-tn :kind :normal :sc (sc-or-lose 'double-reg *backend*)
		  :offset (+ 4 (tn-offset x))))
(defun complex-double-double-reg-imag-lo-tn (x)
  (make-random-tn :kind :normal :sc (sc-or-lose 'double-reg *backend*)
		  :offset (+ 6 (tn-offset x))))
)

(define-move-function (load-complex-single 2) (vop x y)
  ((complex-single-stack) (complex-single-reg))
  (let ((nfp (current-nfp-tn vop))
	(offset (* (tn-offset x) vm:word-bytes)))
    (let ((real-tn (complex-single-reg-real-tn y)))
      (inst ldf real-tn nfp offset))
    (let ((imag-tn (complex-single-reg-imag-tn y)))
      (inst ldf imag-tn nfp (+ offset vm:word-bytes)))))

(define-move-function (store-complex-single 2) (vop x y)
  ((complex-single-reg) (complex-single-stack))
  (let ((nfp (current-nfp-tn vop))
	(offset (* (tn-offset y) vm:word-bytes)))
    (let ((real-tn (complex-single-reg-real-tn x)))
      (inst stf real-tn nfp offset))
    (let ((imag-tn (complex-single-reg-imag-tn x)))
      (inst stf imag-tn nfp (+ offset vm:word-bytes)))))


(define-move-function (load-complex-double 4) (vop x y)
  ((complex-double-stack) (complex-double-reg))
  (let ((nfp (current-nfp-tn vop))
	(offset (* (tn-offset x) vm:word-bytes)))
    (let ((real-tn (complex-double-reg-real-tn y)))
      (inst lddf real-tn nfp offset))
    (let ((imag-tn (complex-double-reg-imag-tn y)))
      (inst lddf imag-tn nfp (+ offset (* 2 vm:word-bytes))))))

(define-move-function (store-complex-double 4) (vop x y)
  ((complex-double-reg) (complex-double-stack))
  (let ((nfp (current-nfp-tn vop))
	(offset (* (tn-offset y) vm:word-bytes)))
    (let ((real-tn (complex-double-reg-real-tn x)))
      (inst stdf real-tn nfp offset))
    (let ((imag-tn (complex-double-reg-imag-tn x)))
      (inst stdf imag-tn nfp (+ offset (* 2 vm:word-bytes))))))


#+long-float
(define-move-function (load-complex-long 5) (vop x y)
  ((complex-long-stack) (complex-long-reg))
  (let ((nfp (current-nfp-tn vop))
	(offset (* (tn-offset x) vm:word-bytes)))
    (let ((real-tn (complex-long-reg-real-tn y)))
      (load-long-reg real-tn nfp offset))
    (let ((imag-tn (complex-long-reg-imag-tn y)))
      (load-long-reg imag-tn nfp (+ offset (* 4 vm:word-bytes))))))

#+long-float
(define-move-function (store-complex-long 5) (vop x y)
  ((complex-long-reg) (complex-long-stack))
  (let ((nfp (current-nfp-tn vop))
	(offset (* (tn-offset y) vm:word-bytes)))
    (let ((real-tn (complex-long-reg-real-tn x)))
      (store-long-reg real-tn nfp offset))
    (let ((imag-tn (complex-long-reg-imag-tn x)))
      (store-long-reg imag-tn nfp (+ offset (* 4 vm:word-bytes))))))

#+double-double
(progn
(define-move-function (load-complex-double-double 4) (vop x y)
  ((complex-double-double-stack) (complex-double-double-reg))
  (let ((nfp (current-nfp-tn vop))
	(offset (* (tn-offset x) vm:word-bytes)))
    (let ((value-tn (complex-double-double-reg-real-hi-tn y)))
      (inst lddf value-tn nfp offset))
    (let ((value-tn (complex-double-double-reg-real-lo-tn y)))
      (inst lddf value-tn nfp (+ offset (* 2 vm:word-bytes))))
    (let ((value-tn (complex-double-double-reg-imag-hi-tn y)))
      (inst lddf value-tn nfp (+ offset (* 4 vm:word-bytes))))
    (let ((value-tn (complex-double-double-reg-imag-lo-tn y)))
      (inst lddf value-tn nfp (+ offset (* 6 vm:word-bytes))))))

(define-move-function (store-complex-double-double 4) (vop x y)
  ((complex-double-double-reg) (complex-double-double-stack))
  (let ((nfp (current-nfp-tn vop))
	(offset (* (tn-offset y) vm:word-bytes)))
    (let ((value-tn (complex-double-double-reg-real-hi-tn x)))
      (inst stdf value-tn nfp offset))
    (let ((value-tn (complex-double-double-reg-real-lo-tn x)))
      (inst stdf value-tn nfp (+ offset (* 2 vm:word-bytes))))
    (let ((value-tn (complex-double-double-reg-imag-hi-tn x)))
      (inst stdf value-tn nfp (+ offset (* 4 vm:word-bytes))))
    (let ((value-tn (complex-double-double-reg-imag-lo-tn x)))
      (inst stdf value-tn nfp (+ offset (* 6 vm:word-bytes))))))

)

;;;
;;; Complex float register to register moves.
;;;
(define-vop (complex-single-move)
  (:args (x :scs (complex-single-reg) :target y
	    :load-if (not (location= x y))))
  (:results (y :scs (complex-single-reg) :load-if (not (location= x y))))
  (:note _N"complex single float move")
  (:generator 0
     (unless (location= x y)
       ;; Note the complex-float-regs are aligned to every second
       ;; float register so there is not need to worry about overlap.
       (let ((x-real (complex-single-reg-real-tn x))
	     (y-real (complex-single-reg-real-tn y)))
	 (inst fmovs y-real x-real))
       (let ((x-imag (complex-single-reg-imag-tn x))
	     (y-imag (complex-single-reg-imag-tn y)))
	 (inst fmovs y-imag x-imag)))))
;;;
(define-move-vop complex-single-move :move
  (complex-single-reg) (complex-single-reg))

(define-vop (complex-double-move)
  (:args (x :scs (complex-double-reg)
	    :target y :load-if (not (location= x y))))
  (:results (y :scs (complex-double-reg) :load-if (not (location= x y))))
  (:note _N"complex double float move")
  (:generator 0
     (unless (location= x y)
       ;; Note the complex-float-regs are aligned to every second
       ;; float register so there is not need to worry about overlap.
       (let ((x-real (complex-double-reg-real-tn x))
	     (y-real (complex-double-reg-real-tn y)))
	 (move-double-reg y-real x-real))
       (let ((x-imag (complex-double-reg-imag-tn x))
	     (y-imag (complex-double-reg-imag-tn y)))
	 (move-double-reg y-imag x-imag)))))
;;;
(define-move-vop complex-double-move :move
  (complex-double-reg) (complex-double-reg))

#+long-float
(define-vop (complex-long-move)
  (:args (x :scs (complex-long-reg)
	    :target y :load-if (not (location= x y))))
  (:results (y :scs (complex-long-reg) :load-if (not (location= x y))))
  (:note _N"complex long float move")
  (:generator 0
     (unless (location= x y)
       ;; Note the complex-float-regs are aligned to every second
       ;; float register so there is not need to worry about overlap.
       (let ((x-real (complex-long-reg-real-tn x))
	     (y-real (complex-long-reg-real-tn y)))
	 (move-long-reg y-real x-real))
       (let ((x-imag (complex-long-reg-imag-tn x))
	     (y-imag (complex-long-reg-imag-tn y)))
	 (move-long-reg y-imag x-imag)))))
;;;
#+long-float
(define-move-vop complex-long-move :move
  (complex-long-reg) (complex-long-reg))

#+double-double
(define-vop (complex-double-double-move)
  (:args (x :scs (complex-double-double-reg)
	    :target y :load-if (not (location= x y))))
  (:results (y :scs (complex-double-double-reg) :load-if (not (location= x y))))
  (:note _N"complex double-double float move")
  (:generator 0
     (unless (location= x y)
       ;; Note the complex-float-regs are aligned to every second
       ;; float register so there is not need to worry about overlap.
       (let ((x-real (complex-double-double-reg-real-hi-tn x))
	     (y-real (complex-double-double-reg-real-hi-tn y)))
	 (move-double-reg y-real x-real))
       (let ((x-real (complex-double-double-reg-real-lo-tn x))
	     (y-real (complex-double-double-reg-real-lo-tn y)))
	 (move-double-reg y-real x-real))
       (let ((x-real (complex-double-double-reg-imag-hi-tn x))
	     (y-real (complex-double-double-reg-imag-hi-tn y)))
	 (move-double-reg y-real x-real))
       (let ((x-imag (complex-double-double-reg-imag-lo-tn x))
	     (y-imag (complex-double-double-reg-imag-lo-tn y)))
	 (move-double-reg y-imag x-imag)))))
;;;
#+double-double
(define-move-vop complex-double-double-move :move
  (complex-double-double-reg) (complex-double-double-reg))

;;;
;;; Move from a complex float to a descriptor register allocating a
;;; new complex float object in the process.
;;;
(define-vop (move-from-complex-single)
  (:args (x :scs (complex-single-reg) :to :save))
  (:results (y :scs (descriptor-reg)))
  (:temporary (:scs (non-descriptor-reg)) ndescr)
  (:note _N"complex single float to pointer coercion")
  (:generator 13
     (with-fixed-allocation (y ndescr vm:complex-single-float-type
			       vm:complex-single-float-size))
     (let ((real-tn (complex-single-reg-real-tn x)))
       (inst stf real-tn y (- (* vm:complex-single-float-real-slot
				 vm:word-bytes)
			      vm:other-pointer-type)))
     (let ((imag-tn (complex-single-reg-imag-tn x)))
       (inst stf imag-tn y (- (* vm:complex-single-float-imag-slot
				 vm:word-bytes)
			      vm:other-pointer-type)))))
;;;
(define-move-vop move-from-complex-single :move
  (complex-single-reg) (descriptor-reg))

(define-vop (move-from-complex-double)
  (:args (x :scs (complex-double-reg) :to :save))
  (:results (y :scs (descriptor-reg)))
  (:temporary (:scs (non-descriptor-reg)) ndescr)
  (:note _N"complex double float to pointer coercion")
  (:generator 13
     (with-fixed-allocation (y ndescr vm:complex-double-float-type
			       vm:complex-double-float-size))
     (let ((real-tn (complex-double-reg-real-tn x)))
       (inst stdf real-tn y (- (* vm:complex-double-float-real-slot
				  vm:word-bytes)
			       vm:other-pointer-type)))
     (let ((imag-tn (complex-double-reg-imag-tn x)))
       (inst stdf imag-tn y (- (* vm:complex-double-float-imag-slot
				  vm:word-bytes)
			       vm:other-pointer-type)))))
;;;
(define-move-vop move-from-complex-double :move
  (complex-double-reg) (descriptor-reg))

#+long-float
(define-vop (move-from-complex-long)
  (:args (x :scs (complex-long-reg) :to :save))
  (:results (y :scs (descriptor-reg)))
  (:temporary (:scs (non-descriptor-reg)) ndescr)
  (:note _N"complex long float to pointer coercion")
  (:generator 13
     (with-fixed-allocation (y ndescr vm:complex-long-float-type
			       vm:complex-long-float-size))
     (let ((real-tn (complex-long-reg-real-tn x)))
       (store-long-reg real-tn y (- (* vm:complex-long-float-real-slot
				       vm:word-bytes)
				    vm:other-pointer-type)))
     (let ((imag-tn (complex-long-reg-imag-tn x)))
       (store-long-reg imag-tn y (- (* vm:complex-long-float-imag-slot
				       vm:word-bytes)
				    vm:other-pointer-type)))))
;;;
#+long-float
(define-move-vop move-from-complex-long :move
  (complex-long-reg) (descriptor-reg))

#+double-double
(define-vop (move-from-complex-double-double)
  (:args (x :scs (complex-double-double-reg) :to :save))
  (:results (y :scs (descriptor-reg)))
  (:temporary (:scs (non-descriptor-reg)) ndescr)
  (:note _N"complex double-double float to pointer coercion")
  (:generator 13
     (with-fixed-allocation (y ndescr vm::complex-double-double-float-type
			       vm::complex-double-double-float-size))
     (let ((real-tn (complex-double-double-reg-real-hi-tn x)))
       (inst stdf real-tn y (- (* vm::complex-double-double-float-real-hi-slot
				  vm:word-bytes)
			       vm:other-pointer-type)))
     (let ((real-tn (complex-double-double-reg-real-lo-tn x)))
       (inst stdf real-tn y (- (* vm::complex-double-double-float-real-lo-slot
				  vm:word-bytes)
			       vm:other-pointer-type)))
     (let ((imag-tn (complex-double-double-reg-imag-hi-tn x)))
       (inst stdf imag-tn y (- (* vm::complex-double-double-float-imag-hi-slot
				  vm:word-bytes)
			       vm:other-pointer-type)))
     (let ((imag-tn (complex-double-double-reg-imag-lo-tn x)))
       (inst stdf imag-tn y (- (* vm::complex-double-double-float-imag-lo-slot
				  vm:word-bytes)
			       vm:other-pointer-type)))))
;;;
#+double-double
(define-move-vop move-from-complex-double-double :move
  (complex-double-double-reg) (descriptor-reg))

;;;
;;; Move from a descriptor to a complex float register
;;;
(define-vop (move-to-complex-single)
  (:args (x :scs (descriptor-reg)))
  (:results (y :scs (complex-single-reg)))
  (:note _N"pointer to complex float coercion")
  (:generator 2
    (let ((real-tn (complex-single-reg-real-tn y)))
      (inst ldf real-tn x (- (* complex-single-float-real-slot word-bytes)
			     other-pointer-type)))
    (let ((imag-tn (complex-single-reg-imag-tn y)))
      (inst ldf imag-tn x (- (* complex-single-float-imag-slot word-bytes)
			     other-pointer-type)))))
(define-move-vop move-to-complex-single :move
  (descriptor-reg) (complex-single-reg))

(define-vop (move-to-complex-double)
  (:args (x :scs (descriptor-reg)))
  (:results (y :scs (complex-double-reg)))
  (:note _N"pointer to complex float coercion")
  (:generator 2
    (let ((real-tn (complex-double-reg-real-tn y)))
      (inst lddf real-tn x (- (* complex-double-float-real-slot word-bytes)
			      other-pointer-type)))
    (let ((imag-tn (complex-double-reg-imag-tn y)))
      (inst lddf imag-tn x (- (* complex-double-float-imag-slot word-bytes)
			      other-pointer-type)))))
(define-move-vop move-to-complex-double :move
  (descriptor-reg) (complex-double-reg))

#+long-float
(define-vop (move-to-complex-long)
  (:args (x :scs (descriptor-reg)))
  (:results (y :scs (complex-long-reg)))
  (:note _N"pointer to complex float coercion")
  (:generator 2
    (let ((real-tn (complex-long-reg-real-tn y)))
      (load-long-reg real-tn x (- (* complex-long-float-real-slot word-bytes)
				  other-pointer-type)))
    (let ((imag-tn (complex-long-reg-imag-tn y)))
      (load-long-reg imag-tn x (- (* complex-long-float-imag-slot word-bytes)
				  other-pointer-type)))))
#+long-float
(define-move-vop move-to-complex-long :move
  (descriptor-reg) (complex-long-reg))

#+double-double
(define-vop (move-to-complex-double-double)
  (:args (x :scs (descriptor-reg)))
  (:results (y :scs (complex-double-double-reg)))
  (:note _N"pointer to complex double-double float coercion")
  (:generator 2
    (let ((real-tn (complex-double-double-reg-real-hi-tn y)))
      (inst lddf real-tn x (- (* complex-double-double-float-real-hi-slot word-bytes)
			      other-pointer-type)))
    (let ((real-tn (complex-double-double-reg-real-lo-tn y)))
      (inst lddf real-tn x (- (* complex-double-double-float-real-lo-slot word-bytes)
			      other-pointer-type)))
    (let ((imag-tn (complex-double-double-reg-imag-hi-tn y)))
      (inst lddf imag-tn x (- (* complex-double-double-float-imag-hi-slot word-bytes)
			      other-pointer-type)))
    (let ((imag-tn (complex-double-double-reg-imag-lo-tn y)))
      (inst lddf imag-tn x (- (* complex-double-double-float-imag-lo-slot word-bytes)
			      other-pointer-type)))))
#+double-double
(define-move-vop move-to-complex-double-double :move
  (descriptor-reg) (complex-double-double-reg))

;;;
;;; Complex float move-argument vop
;;;
(define-vop (move-complex-single-float-argument)
  (:args (x :scs (complex-single-reg) :target y)
	 (nfp :scs (any-reg) :load-if (not (sc-is y complex-single-reg))))
  (:results (y))
  (:note _N"complex single-float argument move")
  (:generator 1
    (sc-case y
      (complex-single-reg
       (unless (location= x y)
	 (let ((x-real (complex-single-reg-real-tn x))
	       (y-real (complex-single-reg-real-tn y)))
	   (inst fmovs y-real x-real))
	 (let ((x-imag (complex-single-reg-imag-tn x))
	       (y-imag (complex-single-reg-imag-tn y)))
	   (inst fmovs y-imag x-imag))))
      (complex-single-stack
       (let ((offset (* (tn-offset y) word-bytes)))
	 (let ((real-tn (complex-single-reg-real-tn x)))
	   (inst stf real-tn nfp offset))
	 (let ((imag-tn (complex-single-reg-imag-tn x)))
	   (inst stf imag-tn nfp (+ offset word-bytes))))))))
(define-move-vop move-complex-single-float-argument :move-argument
  (complex-single-reg descriptor-reg) (complex-single-reg))

(define-vop (move-complex-double-float-argument)
  (:args (x :scs (complex-double-reg) :target y)
	 (nfp :scs (any-reg) :load-if (not (sc-is y complex-double-reg))))
  (:results (y))
  (:note _N"complex double-float argument move")
  (:generator 2
    (sc-case y
      (complex-double-reg
       (unless (location= x y)
	 (let ((x-real (complex-double-reg-real-tn x))
	       (y-real (complex-double-reg-real-tn y)))
	   (move-double-reg y-real x-real))
	 (let ((x-imag (complex-double-reg-imag-tn x))
	       (y-imag (complex-double-reg-imag-tn y)))
	   (move-double-reg y-imag x-imag))))
      (complex-double-stack
       (let ((offset (* (tn-offset y) word-bytes)))
	 (let ((real-tn (complex-double-reg-real-tn x)))
	   (inst stdf real-tn nfp offset))
	 (let ((imag-tn (complex-double-reg-imag-tn x)))
	   (inst stdf imag-tn nfp (+ offset (* 2 word-bytes)))))))))
(define-move-vop move-complex-double-float-argument :move-argument
  (complex-double-reg descriptor-reg) (complex-double-reg))

#+long-float
(define-vop (move-complex-long-float-argument)
  (:args (x :scs (complex-long-reg) :target y)
	 (nfp :scs (any-reg) :load-if (not (sc-is y complex-long-reg))))
  (:results (y))
  (:note _N"complex long-float argument move")
  (:generator 2
    (sc-case y
      (complex-long-reg
       (unless (location= x y)
	 (let ((x-real (complex-long-reg-real-tn x))
	       (y-real (complex-long-reg-real-tn y)))
	   (move-long-reg y-real x-real))
	 (let ((x-imag (complex-long-reg-imag-tn x))
	       (y-imag (complex-long-reg-imag-tn y)))
	   (move-long-reg y-imag x-imag))))
      (complex-long-stack
       (let ((offset (* (tn-offset y) word-bytes)))
	 (let ((real-tn (complex-long-reg-real-tn x)))
	   (store-long-reg real-tn nfp offset))
	 (let ((imag-tn (complex-long-reg-imag-tn x)))
	   (store-long-reg imag-tn nfp (+ offset (* 4 word-bytes)))))))))

#+long-float
(define-move-vop move-complex-long-float-argument :move-argument
  (complex-long-reg descriptor-reg) (complex-long-reg))

#+double-double
(define-vop (move-complex-double-double-float-argument)
  (:args (x :scs (complex-double-double-reg) :target y)
	 (nfp :scs (any-reg) :load-if (not (sc-is y complex-double-double-reg))))
  (:results (y))
  (:note _N"complex double-double float argument move")
  (:generator 2
    (sc-case y
      (complex-double-double-reg
       (unless (location= x y)
	 (let ((x-real (complex-double-double-reg-real-hi-tn x))
	       (y-real (complex-double-double-reg-real-hi-tn y)))
	   (move-double-reg y-real x-real))
	 (let ((x-real (complex-double-double-reg-real-lo-tn x))
	       (y-real (complex-double-double-reg-real-lo-tn y)))
	   (move-double-reg y-real x-real))
	 (let ((x-imag (complex-double-double-reg-imag-hi-tn x))
	       (y-imag (complex-double-double-reg-imag-hi-tn y)))
	   (move-long-reg y-imag x-imag))
	 (let ((x-imag (complex-double-double-reg-imag-lo-tn x))
	       (y-imag (complex-double-double-reg-imag-lo-tn y)))
	   (move-long-reg y-imag x-imag))))
      (complex-double-double-stack
       (let ((offset (* (tn-offset y) word-bytes)))
	 (let ((real-tn (complex-double-double-reg-real-hi-tn x)))
	   (inst stdf real-tn nfp offset))
	 (let ((real-tn (complex-double-double-reg-real-lo-tn x)))
	   (inst stdf real-tn nfp (+ offset (* 2 word-bytes))))
	 (let ((imag-tn (complex-double-double-reg-imag-hi-tn x)))
	   (inst stdf imag-tn nfp (+ offset (* 4 word-bytes))))
	 (let ((imag-tn (complex-double-double-reg-imag-lo-tn x)))
	   (inst stdf imag-tn nfp (+ offset (* 6 word-bytes)))))))))

#+double-double
(define-move-vop move-complex-double-double-float-argument :move-argument
  (complex-double-double-reg descriptor-reg) (complex-double-double-reg))

(define-move-vop move-argument :move-argument
  (single-reg double-reg #+long-float long-reg #+double-double double-double-reg
   complex-single-reg complex-double-reg #+long-float complex-long-reg
   #+double-double complex-double-double-reg)
  (descriptor-reg))


;;;; Arithmetic VOPs:

(define-vop (float-op)
  (:args (x) (y))
  (:results (r))
  (:policy :fast-safe)
  (:note _N"inline float arithmetic")
  (:vop-var vop)
  (:save-p :compute-only))

(macrolet ((frob (name sc ptype)
	     `(define-vop (,name float-op)
		(:args (x :scs (,sc))
		       (y :scs (,sc)))
		(:results (r :scs (,sc)))
		(:arg-types ,ptype ,ptype)
		(:result-types ,ptype))))
  (frob single-float-op single-reg single-float)
  (frob double-float-op double-reg double-float)
  #+long-float
  (frob long-float-op long-reg long-float))

(macrolet ((frob (op sinst sname scost dinst dname dcost)
	     `(progn
		(define-vop (,sname single-float-op)
		  (:translate ,op)
		  (:generator ,scost
		    (inst ,sinst r x y)))
		(define-vop (,dname double-float-op)
		  (:translate ,op)
		  (:generator ,dcost
		    (inst ,dinst r x y))))))
  (frob + fadds +/single-float 2 faddd +/double-float 2)
  (frob - fsubs -/single-float 2 fsubd -/double-float 2)
  (frob * fmuls */single-float 4 fmuld */double-float 5)
  (frob / fdivs //single-float 12 fdivd //double-float 19))

#+long-float
(macrolet ((frob (op linst lname lcost)
	     `(define-vop (,lname long-float-op)
		  (:translate ,op)
		  (:generator ,lcost
		    (inst ,linst r x y)))))
  (frob + faddq +/long-float 2)
  (frob - fsubq -/long-float 2)
  (frob * fmulq */long-float 6)
  (frob / fdivq //long-float 20))


(macrolet ((frob (name inst translate sc type)
	     `(define-vop (,name)
		(:args (x :scs (,sc)))
		(:results (y :scs (,sc)))
		(:translate ,translate)
		(:policy :fast-safe)
		(:arg-types ,type)
		(:result-types ,type)
		(:note _N"inline float arithmetic")
		(:vop-var vop)
		(:save-p :compute-only)
		(:generator 1
		  (note-this-location vop :internal-error)
		  (inst ,inst y x)))))
  (frob abs/single-float fabss abs single-reg single-float)
  (frob %negate/single-float fnegs %negate single-reg single-float))

(defun negate-double-reg (dst src)
  (cond ((backend-featurep :sparc-v9)
	 (inst fnegd dst src))
	(t
	 ;; Negate the MS part of the numbers, then copy over the rest
	 ;; of the bits.
	 (inst fnegs dst src)
	 (let ((dst-odd (make-random-tn :kind :normal
					:sc (sc-or-lose 'single-reg *backend*)
					:offset (+ 1 (tn-offset dst))))
	       (src-odd (make-random-tn :kind :normal
					:sc (sc-or-lose 'single-reg *backend*)
					:offset (+ 1 (tn-offset src)))))
	   (inst fmovs dst-odd src-odd)))))

(defun abs-double-reg (dst src)
  (cond ((backend-featurep :sparc-v9)
	 (inst fabsd dst src))
	(t
	 ;; Abs the MS part of the numbers, then copy over the rest
	 ;; of the bits.
	 (inst fabss dst src)
	 (let ((dst-2 (make-random-tn :kind :normal
				      :sc (sc-or-lose 'single-reg *backend*)
				      :offset (+ 1 (tn-offset dst))))
	       (src-2 (make-random-tn :kind :normal
				      :sc (sc-or-lose 'single-reg *backend*)
				      :offset (+ 1 (tn-offset src)))))
	   (inst fmovs dst-2 src-2)))))

(define-vop (abs/double-float)
  (:args (x :scs (double-reg)))
  (:results (y :scs (double-reg)))
  (:translate abs)
  (:policy :fast-safe)
  (:arg-types double-float)
  (:result-types double-float)
  (:note _N"inline float arithmetic")
  (:vop-var vop)
  (:save-p :compute-only)
  (:generator 1
    (note-this-location vop :internal-error)
    (abs-double-reg y x)))

(define-vop (%negate/double-float)
  (:args (x :scs (double-reg)))
  (:results (y :scs (double-reg)))
  (:translate %negate)
  (:policy :fast-safe)
  (:arg-types double-float)
  (:result-types double-float)
  (:note _N"inline float arithmetic")
  (:vop-var vop)
  (:save-p :compute-only)
  (:generator 1
    (note-this-location vop :internal-error)
    (negate-double-reg y x)))

#+long-float
(define-vop (abs/long-float)
  (:args (x :scs (long-reg)))
  (:results (y :scs (long-reg)))
  (:translate abs)
  (:policy :fast-safe)
  (:arg-types long-float)
  (:result-types long-float)
  (:note _N"inline float arithmetic")
  (:vop-var vop)
  (:save-p :compute-only)
  (:generator 1
    (note-this-location vop :internal-error)
    (cond ((backend-featurep :sparc-v9)
	   (inst fabsq y x))
	  (t
	   (inst fabss y x)
	   (dotimes (i 3)
	     (let ((y-odd (make-random-tn
			   :kind :normal
			   :sc (sc-or-lose 'single-reg *backend*)
			   :offset (+ i 1 (tn-offset y))))
		   (x-odd (make-random-tn
			   :kind :normal
			   :sc (sc-or-lose 'single-reg *backend*)
			   :offset (+ i 1 (tn-offset x)))))
	       (inst fmovs y-odd x-odd)))))))

#+long-float
(define-vop (%negate/long-float)
  (:args (x :scs (long-reg)))
  (:results (y :scs (long-reg)))
  (:translate %negate)
  (:policy :fast-safe)
  (:arg-types long-float)
  (:result-types long-float)
  (:note _N"inline float arithmetic")
  (:vop-var vop)
  (:save-p :compute-only)
  (:generator 1
    (note-this-location vop :internal-error)
    (cond ((backend-featurep :sparc-v9)
	   (inst fnegq y x))
	  (t
	   (inst fnegs y x)
	   (dotimes (i 3)
	     (let ((y-odd (make-random-tn
			   :kind :normal
			   :sc (sc-or-lose 'single-reg *backend*)
			   :offset (+ i 1 (tn-offset y))))
		   (x-odd (make-random-tn
			   :kind :normal
			   :sc (sc-or-lose 'single-reg *backend*)
			   :offset (+ i 1 (tn-offset x)))))
	       (inst fmovs y-odd x-odd)))))))


;;;; Comparison:

(define-vop (float-compare)
  (:args (x) (y))
  (:conditional)
  (:info target not-p)
  (:variant-vars format yep nope)
  (:policy :fast-safe)
  (:note _N"inline float comparison")
  (:vop-var vop)
  (:save-p :compute-only)
  (:generator 3
    (note-this-location vop :internal-error)
    (ecase format
      (:single (inst fcmps x y))
      (:double (inst fcmpd x y))
      (:long (inst fcmpq x y)))
    ;; The SPARC V9 doesn't need an instruction between a
    ;; floating-point compare and a floating-point branch.
    (unless (backend-featurep :sparc-v9)
      (inst nop))
    (inst fb (if not-p nope yep) target)
    (inst nop)))

(macrolet ((frob (name sc ptype)
	     `(define-vop (,name float-compare)
		(:args (x :scs (,sc))
		       (y :scs (,sc)))
		(:arg-types ,ptype ,ptype))))
  (frob single-float-compare single-reg single-float)
  (frob double-float-compare double-reg double-float)
  #+long-float
  (frob long-float-compare long-reg long-float))

(macrolet ((frob (translate yep nope sname dname #+long-float lname)
	     `(progn
		(define-vop (,sname single-float-compare)
		  (:translate ,translate)
		  (:variant :single ,yep ,nope))
		(define-vop (,dname double-float-compare)
		  (:translate ,translate)
		  (:variant :double ,yep ,nope))
	        #+long-float
		(define-vop (,lname long-float-compare)
		  (:translate ,translate)
		  (:variant :long ,yep ,nope)))))
  (frob < :l :ge </single-float </double-float #+long-float </long-float)
  (frob > :g :le >/single-float >/double-float #+long-float >/long-float)
  (frob = :eq :ne eql/single-float eql/double-float #+long-float eql/long-float))

#+long-float
(deftransform eql ((x y) (long-float long-float))
  '(and (= (long-float-low-bits x) (long-float-low-bits y))
	(= (long-float-mid-bits x) (long-float-mid-bits y))
	(= (long-float-high-bits x) (long-float-high-bits y))
	(= (long-float-exp-bits x) (long-float-exp-bits y))))

#+double-double
(deftransform eql ((x y) (double-double-float double-double-float))
  '(and (eql (double-double-hi x) (double-double-hi y))
	(eql (double-double-lo x) (double-double-lo y))))


;;;; Conversion:

;; Tell the compiler about %%single-float and %%double-float.  Add
;; functions for byte-compiled code.
(macrolet
    ((frob (name type)
       `(progn
	  (defknown ,name ((signed-byte 32))
	    ,type)
	  (defun ,name (n)
	    (declare (type (signed-byte 32) n))
	    (,name n)))))
  (frob %%single-float single-float)
  (frob %%double-float double-float))

;; Sparc doesn't have an instruction to convert a 32-bit unsigned
;; integer to a float, but does have one for a 32-bit signed integer.
;; What we do here is break up the 32-bit number into 2 smaller
;; pieces.  Each of these are converted to a float, and the higher
;; order piece is scaled appropriately, and finally everything is
;; summed together.  The pieces are done in a way such that no
;; roundoff occurs.  The scaling should not produce any roundoff
;; either, since the scale factor is an exact power of two.  The final
;; sum will produce the correct rounded result.  (I think,)
;;
;; But need to be careful because we still want to call the VOP for
;; the small pieces, so we need the transform to give up if it's known
;; that the argument is smaller than a 32-bit unsigned integer.
(macrolet ((frob (name vop-trans limit unit)
	     `(progn
		(deftransform ,name ((n) ((unsigned-byte 32)))
		  ;; Should this be extended to a (unsigned-byte 53)?  We could.  Just
		  ;; take the low 31 bits, and the rest, and float them and combine
		  ;; them as before.
		  (when (csubtypep (c::continuation-type n)
				   (c::specifier-type '(unsigned-byte 31)))
		    ;; We want to give-up if we know the number can't have the
		    ;; MSB set.  The signed 32-bit vop can handle that.
		    (c::give-up))
		  `(+ (,',vop-trans (ldb (byte ,',limit 0) n))
		      (* (,',vop-trans (ldb (byte ,',(- 32 limit) ,',limit) n))
			 (scale-float ,',unit ,',limit))))
		;; Always convert %foo to %%foo for 32-bit signed values.
		(deftransform ,name ((n) ((signed-byte 32)))
		  `(,',vop-trans n)))))
  ;; If we break up the numbers into the low 12 bits and the high 20
  ;; bits, we can use a single AND instruction to get the low 12 bits.
  ;; This is a microoptimization for Sparc.  Otherwise, the only
  ;; constraint is that the pieces must be small enough to fit in the
  ;; desired float format without rounding.
  (frob %single-float %%single-float 12 1f0)
  (frob %double-float %%double-float 12 1f0))


(macrolet ((frob (name translate inst to-sc to-type)
	     `(define-vop (,name)
		(:args (x :scs (signed-reg) :target stack-temp
			  :load-if (not (sc-is x signed-stack))))
		(:temporary (:scs (single-stack) :from :argument) stack-temp)
		(:temporary (:scs (single-reg) :to :result :target y) temp)
		(:results (y :scs (,to-sc)))
		(:arg-types signed-num)
		(:result-types ,to-type)
		(:policy :fast-safe)
		(:note _N"inline float coercion")
		(:translate ,translate)
		(:vop-var vop)
		(:save-p :compute-only)
		(:generator 5
		  (let ((stack-tn
			 (sc-case x
			   (signed-reg
			    (inst st x
				  (current-nfp-tn vop)
				  (* (tn-offset temp) vm:word-bytes))
			    stack-temp)
			   (signed-stack
			    x))))
		    (inst ldf temp
			  (current-nfp-tn vop)
			  (* (tn-offset stack-tn) vm:word-bytes))
		    (note-this-location vop :internal-error)
		    (inst ,inst y temp))))))
  (frob %single-float/signed %%single-float fitos single-reg single-float)
  (frob %double-float/signed %%double-float fitod double-reg double-float)
  #+long-float
  (frob %long-float/signed %long-float fitoq long-reg long-float))

;; Sparc doesn't have an instruction to convert a 32-bit unsigned
;; integer to a float, but does have one for a 32-bit signed integer.
;; What we do here is break up the 32-bit number into 2 smaller
;; pieces.  Each of these are converted to a float, and the higher
;; order piece is scaled appropriately, and finally everything is
;; summed together.  The pieces are done in a way such that no
;; roundoff occurs.  The scaling should not produce any roundoff
;; either, since the scale factor is an exact power of two.  The final
;; sum will produce the correct rounded result.  (I think,)
;;
;; But need to be careful because we still want to call the VOP for
;; the small pieces, so we need the transform to give up if it's known
;; that the argument is smaller than a 32-bit unsigned integer.
(macrolet ((frob (name limit unit)
	     `(deftransform ,name ((n) ((unsigned-byte 32)))
		;; Should this be extended to a (unsigned-byte 53)?  We could.  Just
		;; take the low 31 bits, and the rest, and float them and combine
		;; them as before.
		(when (csubtypep (c::continuation-type n)
				 (c::specifier-type '(unsigned-byte 31)))
		  ;; We want to give-up if we know the number can't have the
		  ;; MSB set.  The signed 32-bit vop can handle that.
		  (c::give-up))
		`(+ (,',name (ldb (byte ,',limit 0) n))
		    (* (,',name (ldb (byte ,',(- 32 limit) ,',limit) n))
		       (scale-float ,',unit ,',limit))))))
  ;; If we break up the numbers into the low 12 bits and the high 20
  ;; bits, we can use a single AND instruction to get the low 12 bits.
  ;; This is a microoptimization for Sparc.  Otherwise, the only
  ;; constraint is that the pieces must be small enough to fit in the
  ;; desired float format without rounding.
  (frob %single-float 12 1f0)
  (frob %double-float 12 1f0))

(macrolet ((frob (name translate inst from-sc from-type to-sc to-type)
	     `(define-vop (,name)
		(:args (x :scs (,from-sc)))
		(:results (y :scs (,to-sc)))
		(:arg-types ,from-type)
		(:result-types ,to-type)
		(:policy :fast-safe)
		(:note _N"inline float coercion")
		(:translate ,translate)
		(:vop-var vop)
		(:save-p :compute-only)
		(:generator 2
		  (note-this-location vop :internal-error)
		  (inst ,inst y x)))))
  (frob %single-float/double-float %single-float fdtos
    double-reg double-float single-reg single-float)
  #+long-float
  (frob %single-float/long-float %single-float fqtos
    long-reg long-float single-reg single-float)
  (frob %double-float/single-float %double-float fstod
    single-reg single-float double-reg double-float)
  #+long-float
  (frob %double-float/long-float %double-float fqtod
    long-reg long-float double-reg double-float)
  #+long-float
  (frob %long-float/single-float %long-float fstoq
    single-reg single-float long-reg long-float)
  #+long-float
  (frob %long-float/double-float %long-float fdtoq
    double-reg double-float long-reg long-float))

(macrolet ((frob (trans from-sc from-type inst)
	     `(define-vop (,(symbolicate trans "/" from-type))
		(:args (x :scs (,from-sc) :target temp))
		(:temporary (:from (:argument 0) :sc single-reg) temp)
		(:temporary (:scs (signed-stack)) stack-temp)
		(:results (y :scs (signed-reg)
			     :load-if (not (sc-is y signed-stack))))
		(:arg-types ,from-type)
		(:result-types signed-num)
		(:translate ,trans)
		(:policy :fast-safe)
		(:note _N"inline float truncate")
		(:vop-var vop)
		(:save-p :compute-only)
		(:generator 5
		  (note-this-location vop :internal-error)
		  (inst ,inst temp x)
		  (sc-case y
		    (signed-stack
		     (inst stf temp (current-nfp-tn vop)
			   (* (tn-offset y) vm:word-bytes)))
		    (signed-reg
		     (inst stf temp (current-nfp-tn vop)
			   (* (tn-offset stack-temp) vm:word-bytes))
		     (inst ldsw y (current-nfp-tn vop)
			   (* (tn-offset stack-temp) vm:word-bytes))))))))
  (frob %unary-truncate single-reg single-float fstoi)
  (frob %unary-truncate double-reg double-float fdtoi)
  #+long-float
  (frob %unary-truncate long-reg long-float fqtoi)
  #-sun4
  (frob %unary-round single-reg single-float fstoir)
  #-sun4
  (frob %unary-round double-reg double-float fdtoir))

(define-vop (fast-unary-ftruncate/single-float)
  (:args (x :scs (single-reg)))
  (:arg-types single-float)
  (:results (r :scs (single-reg)))
  (:result-types single-float)
  (:policy :fast-safe)
  (:translate c::fast-unary-ftruncate)
  (:guard (not (backend-featurep :sparc-v9)))
  (:note _N"inline ftruncate")
  (:generator 2
    (inst fstoi r x)
    (inst fitos r r)))

(define-vop (fast-unary-ftruncate/double-float)
  (:args (x :scs (double-reg) :target r))
  (:arg-types double-float)
  (:results (r :scs (double-reg)))
  (:result-types double-float)
  (:policy :fast-safe)
  (:translate c::fast-unary-ftruncate)
  (:guard (not (backend-featurep :sparc-v9)))
  (:note _N"inline ftruncate")
  (:generator 2
    (inst fdtoi r x)
    (inst fitod r r)))

;; The V9 architecture can convert 64-bit integers.
(define-vop (v9-fast-unary-ftruncate/single-float)
  (:args (x :scs (single-reg)))
  (:arg-types single-float)
  (:results (r :scs (single-reg)))
  (:result-types single-float)
  (:temporary (:scs (double-reg)) temp)
  (:policy :fast-safe)
  (:translate c::fast-unary-ftruncate)
  (:guard (backend-featurep :sparc-v9))
  (:note _N"inline ftruncate")
  (:generator 2
    (inst fstox temp x)
    (inst fxtos r temp)))

(define-vop (v9-fast-unary-ftruncate/double-float)
  (:args (x :scs (double-reg) :target r))
  (:arg-types double-float)
  (:results (r :scs (double-reg)))
  (:result-types double-float)
  (:policy :fast-safe)
  (:translate c::fast-unary-ftruncate)
  (:guard (backend-featurep :sparc-v9))
  (:note _N"inline ftruncate")
  (:generator 2
    (inst fdtox r x)
    (inst fxtod r r)))

;; See Listing 2.2: Conversion from FP to int in in "CR-LIBM: A
;; library of correctly rounded elementary functions in
;; double-precision".
#+sun4
(deftransform %unary-round ((x) (float) (signed-byte 32))
   '(kernel:double-float-low-bits (+ x (+ (scale-float 1d0 52)
					  (scale-float 1d0 51)))))

(define-vop (make-single-float)
  (:args (bits :scs (signed-reg) :target res
	       :load-if (not (sc-is bits signed-stack))))
  (:results (res :scs (single-reg)
		 :load-if (not (sc-is res single-stack))))
  (:temporary (:scs (signed-reg) :from (:argument 0) :to (:result 0)) temp)
  (:temporary (:scs (signed-stack)) stack-temp)
  (:arg-types signed-num)
  (:result-types single-float)
  (:translate make-single-float)
  (:policy :fast-safe)
  (:vop-var vop)
  (:generator 4
    (sc-case bits
      (signed-reg
       (sc-case res
	 (single-reg
	  (inst st bits (current-nfp-tn vop)
		(* (tn-offset stack-temp) vm:word-bytes))
	  (inst ldf res (current-nfp-tn vop)
		(* (tn-offset stack-temp) vm:word-bytes)))
	 (single-stack
	  (inst st bits (current-nfp-tn vop)
		(* (tn-offset res) vm:word-bytes)))))
      (signed-stack
       (sc-case res
	 (single-reg
	  (inst ldf res (current-nfp-tn vop)
		(* (tn-offset bits) vm:word-bytes)))
	 (single-stack
	  (unless (location= bits res)
	    (inst ldsw temp (current-nfp-tn vop)
		  (* (tn-offset bits) vm:word-bytes))
	    (inst st temp (current-nfp-tn vop)
		  (* (tn-offset res) vm:word-bytes)))))))))

(define-vop (make-double-float)
  (:args (hi-bits :scs (signed-reg))
	 (lo-bits :scs (unsigned-reg)))
  (:results (res :scs (double-reg)
		 :load-if (not (sc-is res double-stack))))
  (:temporary (:scs (double-stack)) temp)
  (:arg-types signed-num unsigned-num)
  (:result-types double-float)
  (:translate make-double-float)
  (:policy :fast-safe)
  (:vop-var vop)
  (:generator 2
    (let ((stack-tn (sc-case res
		      (double-stack res)
		      (double-reg temp))))
      (inst st hi-bits (current-nfp-tn vop)
	    (* (tn-offset stack-tn) vm:word-bytes))
      (inst st lo-bits (current-nfp-tn vop)
	    (* (1+ (tn-offset stack-tn)) vm:word-bytes)))
    (when (sc-is res double-reg)
      (inst lddf res (current-nfp-tn vop)
	    (* (tn-offset temp) vm:word-bytes)))))

#+long-float
(define-vop (make-long-float)
    (:args (hi-bits :scs (signed-reg))
	   (lo1-bits :scs (unsigned-reg))
	   (lo2-bits :scs (unsigned-reg))
	   (lo3-bits :scs (unsigned-reg)))
  (:results (res :scs (long-reg)
		 :load-if (not (sc-is res long-stack))))
  (:temporary (:scs (long-stack)) temp)
  (:arg-types signed-num unsigned-num unsigned-num unsigned-num)
  (:result-types long-float)
  (:translate make-long-float)
  (:policy :fast-safe)
  (:vop-var vop)
  (:generator 2
    (let ((stack-tn (sc-case res
		      (long-stack res)
		      (long-reg temp))))
      (inst st hi-bits (current-nfp-tn vop)
	    (* (tn-offset stack-tn) vm:word-bytes))
      (inst st lo1-bits (current-nfp-tn vop)
	    (* (1+ (tn-offset stack-tn)) vm:word-bytes))
      (inst st lo2-bits (current-nfp-tn vop)
	    (* (+ 2 (tn-offset stack-tn)) vm:word-bytes))
      (inst st lo3-bits (current-nfp-tn vop)
	    (* (+ 3 (tn-offset stack-tn)) vm:word-bytes)))
    (when (sc-is res long-reg)
      (load-long-reg res (current-nfp-tn vop)
		     (* (tn-offset temp) vm:word-bytes)))))

(define-vop (single-float-bits)
  (:args (float :scs (single-reg descriptor-reg)
		:load-if (not (sc-is float single-stack))))
  (:results (bits :scs (signed-reg)
		  :load-if (or (sc-is float descriptor-reg single-stack)
			       (not (sc-is bits signed-stack)))))
  (:temporary (:scs (signed-stack)) stack-temp)
  (:arg-types single-float)
  (:result-types signed-num)
  (:translate single-float-bits)
  (:policy :fast-safe)
  (:vop-var vop)
  (:generator 4
    (sc-case bits
      (signed-reg
       (sc-case float
	 (single-reg
	  (inst stf float (current-nfp-tn vop)
		(* (tn-offset stack-temp) vm:word-bytes))
	  (inst ldsw bits (current-nfp-tn vop)
		(* (tn-offset stack-temp) vm:word-bytes)))
	 (single-stack
	  (inst ldsw bits (current-nfp-tn vop)
		(* (tn-offset float) vm:word-bytes)))
	 (descriptor-reg
	  (loadw bits float vm:single-float-value-slot
		 vm:other-pointer-type))))
      (signed-stack
       (sc-case float
	 (single-reg
	  (inst stf float (current-nfp-tn vop)
		(* (tn-offset bits) vm:word-bytes))))))))

(define-vop (double-float-high-bits)
  (:args (float :scs (double-reg descriptor-reg)
		:load-if (not (sc-is float double-stack))))
  (:results (hi-bits :scs (signed-reg)))
  (:temporary (:scs (double-stack)) stack-temp)
  (:arg-types double-float)
  (:result-types signed-num)
  (:translate double-float-high-bits)
  (:policy :fast-safe)
  (:vop-var vop)
  (:generator 5
    (sc-case float
      (double-reg
       (inst stdf float (current-nfp-tn vop)
	     (* (tn-offset stack-temp) vm:word-bytes))
       (inst ldsw hi-bits (current-nfp-tn vop)
	     (* (tn-offset stack-temp) vm:word-bytes)))
      (double-stack
       (inst ldsw hi-bits (current-nfp-tn vop)
	     (* (tn-offset float) vm:word-bytes)))
      (descriptor-reg
       (loadw hi-bits float vm:double-float-value-slot
	      vm:other-pointer-type)))))

(define-vop (double-float-low-bits)
  (:args (float :scs (double-reg descriptor-reg)
		:load-if (not (sc-is float double-stack))))
  (:results (lo-bits :scs (unsigned-reg)))
  (:temporary (:scs (double-stack)) stack-temp)
  (:arg-types double-float)
  (:result-types unsigned-num)
  (:translate double-float-low-bits)
  (:policy :fast-safe)
  (:vop-var vop)
  (:generator 5
    (sc-case float
      (double-reg
       (inst stdf float (current-nfp-tn vop)
	     (* (tn-offset stack-temp) vm:word-bytes))
       (inst ldsw lo-bits (current-nfp-tn vop)
	     (* (1+ (tn-offset stack-temp)) vm:word-bytes)))
      (double-stack
       (inst ldsw lo-bits (current-nfp-tn vop)
	     (* (1+ (tn-offset float)) vm:word-bytes)))
      (descriptor-reg
       (loadw lo-bits float (1+ vm:double-float-value-slot)
	      vm:other-pointer-type)))))

(define-vop (double-float-bits)
  (:args (float :scs (double-reg descriptor-reg)
		:load-if (not (sc-is float double-stack))))
  (:results (hi-bits :scs (signed-reg))
	    (lo-bits :scs (unsigned-reg)))
  (:temporary (:scs (double-stack)) stack-temp)
  (:arg-types double-float)
  (:result-types signed-num unsigned-num)
  (:translate kernel::double-float-bits)
  (:policy :fast-safe)
  (:vop-var vop)
  (:generator 5
    (sc-case float
      (double-reg
       (inst stdf float (current-nfp-tn vop)
	     (* (tn-offset stack-temp) vm:word-bytes))
       (inst ldsw hi-bits (current-nfp-tn vop)
	     (* (tn-offset stack-temp) vm:word-bytes))
       (inst ld lo-bits (current-nfp-tn vop)
	     (* (1+ (tn-offset stack-temp)) vm:word-bytes)))
      (double-stack
       (inst ldsw hi-bits (current-nfp-tn vop)
	     (* (tn-offset float) vm:word-bytes))
       (inst ld lo-bits (current-nfp-tn vop)
	     (* (1+ (tn-offset float)) vm:word-bytes)))
      (descriptor-reg
       (loadw hi-bits float vm:double-float-value-slot
	      vm:other-pointer-type)
       (loadw lo-bits float (1+ vm:double-float-value-slot)
	      vm:other-pointer-type)))))

#+long-float
(define-vop (long-float-exp-bits)
  (:args (float :scs (long-reg descriptor-reg)
		:load-if (not (sc-is float long-stack))))
  (:results (exp-bits :scs (signed-reg)))
  (:temporary (:scs (double-stack)) stack-temp)
  (:arg-types long-float)
  (:result-types signed-num)
  (:translate long-float-exp-bits)
  (:policy :fast-safe)
  (:vop-var vop)
  (:generator 5
    (sc-case float
      (long-reg
       (let ((float (make-random-tn :kind :normal
				    :sc (sc-or-lose 'double-reg *backend*)
				    :offset (tn-offset float))))
	 (inst stdf float (current-nfp-tn vop)
	       (* (tn-offset stack-temp) vm:word-bytes)))
       (inst ld exp-bits (current-nfp-tn vop)
	     (* (tn-offset stack-temp) vm:word-bytes)))
      (long-stack
       (inst ld exp-bits (current-nfp-tn vop)
	     (* (tn-offset float) vm:word-bytes)))
      (descriptor-reg
       (loadw exp-bits float vm:long-float-value-slot
	      vm:other-pointer-type)))))

#+long-float
(define-vop (long-float-high-bits)
  (:args (float :scs (long-reg descriptor-reg)
		:load-if (not (sc-is float long-stack))))
  (:results (high-bits :scs (unsigned-reg)))
  (:temporary (:scs (double-stack)) stack-temp)
  (:arg-types long-float)
  (:result-types unsigned-num)
  (:translate long-float-high-bits)
  (:policy :fast-safe)
  (:vop-var vop)
  (:generator 5
    (sc-case float
      (long-reg
       (let ((float (make-random-tn :kind :normal
				    :sc (sc-or-lose 'double-reg *backend*)
				    :offset (tn-offset float))))
	 (inst stdf float (current-nfp-tn vop)
	       (* (tn-offset stack-temp) vm:word-bytes)))
       (inst ld high-bits (current-nfp-tn vop)
	     (* (1+ (tn-offset stack-temp)) vm:word-bytes)))
      (long-stack
       (inst ld high-bits (current-nfp-tn vop)
	     (* (1+ (tn-offset float)) vm:word-bytes)))
      (descriptor-reg
       (loadw high-bits float (1+ vm:long-float-value-slot)
	      vm:other-pointer-type)))))

#+long-float
(define-vop (long-float-mid-bits)
  (:args (float :scs (long-reg descriptor-reg)
		:load-if (not (sc-is float long-stack))))
  (:results (mid-bits :scs (unsigned-reg)))
  (:temporary (:scs (double-stack)) stack-temp)
  (:arg-types long-float)
  (:result-types unsigned-num)
  (:translate long-float-mid-bits)
  (:policy :fast-safe)
  (:vop-var vop)
  (:generator 5
    (sc-case float
      (long-reg
       (let ((float (make-random-tn :kind :normal
				    :sc (sc-or-lose 'double-reg *backend*)
				    :offset (+ 2 (tn-offset float)))))
	 (inst stdf float (current-nfp-tn vop)
	       (* (tn-offset stack-temp) vm:word-bytes)))
       (inst ld mid-bits (current-nfp-tn vop)
	     (* (tn-offset stack-temp) vm:word-bytes)))
      (long-stack
       (inst ld mid-bits (current-nfp-tn vop)
	     (* (+ 2 (tn-offset float)) vm:word-bytes)))
      (descriptor-reg
       (loadw mid-bits float (+ 2 vm:long-float-value-slot)
	      vm:other-pointer-type)))))

#+long-float
(define-vop (long-float-low-bits)
  (:args (float :scs (long-reg descriptor-reg)
		:load-if (not (sc-is float long-stack))))
  (:results (lo-bits :scs (unsigned-reg)))
  (:temporary (:scs (double-stack)) stack-temp)
  (:arg-types long-float)
  (:result-types unsigned-num)
  (:translate long-float-low-bits)
  (:policy :fast-safe)
  (:vop-var vop)
  (:generator 5
    (sc-case float
      (long-reg
       (let ((float (make-random-tn :kind :normal
				    :sc (sc-or-lose 'double-reg *backend*)
				    :offset (+ 2 (tn-offset float)))))
	 (inst stdf float (current-nfp-tn vop)
	       (* (tn-offset stack-temp) vm:word-bytes)))
       (inst ld lo-bits (current-nfp-tn vop)
	     (* (1+ (tn-offset stack-temp)) vm:word-bytes)))
      (long-stack
       (inst ld lo-bits (current-nfp-tn vop)
	     (* (+ 3 (tn-offset float)) vm:word-bytes)))
      (descriptor-reg
       (loadw lo-bits float (+ 3 vm:long-float-value-slot)
	      vm:other-pointer-type)))))


;;;; Float mode hackery:

(deftype float-modes () '(unsigned-byte 32))
(defknown floating-point-modes () float-modes (flushable))
(defknown ((setf floating-point-modes)) (float-modes)
  float-modes)

(define-vop (floating-point-modes)
  (:results (res :scs (unsigned-reg)))
  (:result-types unsigned-num)
  (:translate floating-point-modes)
  (:policy :fast-safe)
  (:vop-var vop)
  (:temporary (:sc unsigned-stack) temp)
  (:generator 3
    (let ((nfp (current-nfp-tn vop)))
      (inst stfsr nfp (* word-bytes (tn-offset temp)))
      (loadw res nfp (tn-offset temp))
      (inst nop))))

#+nil
(define-vop (floating-point-modes)
  (:results (res :scs (unsigned-reg)))
  (:result-types unsigned-num)
  (:translate floating-point-modes)
  (:policy :fast-safe)
  (:vop-var vop)
  (:temporary (:sc double-stack) temp)
  (:generator 3
    (let* ((nfp (current-nfp-tn vop))
	   (offset (* 4 (tn-offset temp))))
      (inst stxfsr nfp offset)
      ;; The desired FP mode data is in the least significant 32
      ;; bits, which is stored at the next higher word in memory.
      (loadw res nfp (+ offset 4))
      ;; Is this nop needed? (toy@rtp.ericsson.se)
      (inst nop))))

(define-vop (set-floating-point-modes)
  (:args (new :scs (unsigned-reg) :target res))
  (:results (res :scs (unsigned-reg)))
  (:arg-types unsigned-num)
  (:result-types unsigned-num)
  (:translate (setf floating-point-modes))
  (:policy :fast-safe)
  (:temporary (:sc unsigned-stack) temp)
  (:vop-var vop)
  (:generator 3
    (let ((nfp (current-nfp-tn vop)))
      (storew new nfp (tn-offset temp))
      (inst ldfsr nfp (* word-bytes (tn-offset temp)))
      (move res new))))

#+nil
(define-vop (set-floating-point-modes)
  (:args (new :scs (unsigned-reg) :target res))
  (:results (res :scs (unsigned-reg)))
  (:arg-types unsigned-num)
  (:result-types unsigned-num)
  (:translate (setf floating-point-modes))
  (:policy :fast-safe)
  (:temporary (:sc double-stack) temp)
  (:temporary (:sc unsigned-reg) my-fsr)
  (:vop-var vop)
  (:generator 3
    (let ((nfp (current-nfp-tn vop))
	  (offset (* word-bytes (tn-offset temp))))
      (pseudo-atomic ()
        ;; Get the current FSR, so we can get the new %fcc's
        (inst stxfsr nfp offset)
	(inst ldx my-fsr nfp offset)
	;; Carefully merge in the new mode bits with the rest of the
	;; FSR.  This is only needed if we care about preserving the
	;; high 32 bits of the FSR, which contain the additional
	;; %fcc's on the sparc V9.  If not, we don't need this, but we
	;; do need to make sure that the unused bits are written as
	;; zeroes, according the the V9 architecture manual.
	(inst signx new)
	(inst srlx my-fsr 32)
	(inst sllx my-fsr 32)
	(inst or my-fsr new)
	;; Save it back and load it into the fsr register
	(inst stx my-fsr nfp offset)
	(inst ldxfsr nfp offset)
	(move res new)))))

#+nil
(define-vop (set-floating-point-modes)
  (:args (new :scs (unsigned-reg) :target res))
  (:results (res :scs (unsigned-reg)))
  (:arg-types unsigned-num)
  (:result-types unsigned-num)
  (:translate (setf floating-point-modes))
  (:policy :fast-safe)
  (:temporary (:sc double-stack) temp)
  (:temporary (:sc unsigned-reg) my-fsr)
  (:vop-var vop)
  (:generator 3
    (let ((nfp (current-nfp-tn vop))
	  (offset (* word-bytes (tn-offset temp))))
      (inst stx new nfp offset)
      (inst ldxfsr nfp offset)
      (move res new))))


;;;; Special functions.

#-long-float
(define-vop (fsqrt)
  (:args (x :scs (double-reg)))
  (:results (y :scs (double-reg)))
  (:translate %sqrt)
  (:policy :fast-safe)
  (:guard (or (backend-featurep :sparc-v7)
	      (backend-featurep :sparc-v8)
	      (backend-featurep :sparc-v9)))
  (:arg-types double-float)
  (:result-types double-float)
  (:note _N"inline float arithmetic")
  (:vop-var vop)
  (:save-p :compute-only)
  (:generator 1
    (note-this-location vop :internal-error)
    (inst fsqrtd y x)))

#+long-float
(define-vop (fsqrt-long)
  (:args (x :scs (long-reg)))
  (:results (y :scs (long-reg)))
  (:translate %sqrt)
  (:policy :fast-safe)
  (:arg-types long-float)
  (:result-types long-float)
  (:note _N"inline float arithmetic")
  (:vop-var vop)
  (:save-p :compute-only)
  (:generator 1
    (note-this-location vop :internal-error)
    (inst fsqrtq y x)))


;;;; Complex float VOPs

(define-vop (make-complex-single-float)
  (:translate complex)
  (:args (real :scs (single-reg) :target r
	       :load-if (not (location= real r)))
	 (imag :scs (single-reg) :to :save))
  (:arg-types single-float single-float)
  (:results (r :scs (complex-single-reg) :from (:argument 0)
	       :load-if (not (sc-is r complex-single-stack))))
  (:result-types complex-single-float)
  (:note _N"inline complex single-float creation")
  (:policy :fast-safe)
  (:vop-var vop)
  (:generator 5
    (sc-case r
      (complex-single-reg
       (let ((r-real (complex-single-reg-real-tn r)))
	 (unless (location= real r-real)
	   (inst fmovs r-real real)))
       (let ((r-imag (complex-single-reg-imag-tn r)))
	 (unless (location= imag r-imag)
	   (inst fmovs r-imag imag))))
      (complex-single-stack
       (let ((nfp (current-nfp-tn vop))
	     (offset (* (tn-offset r) vm:word-bytes)))
	 (unless (location= real r)
	   (inst stf real nfp offset))
	 (inst stf imag nfp (+ offset vm:word-bytes)))))))

(define-vop (make-complex-double-float)
  (:translate complex)
  (:args (real :scs (double-reg) :target r
	       :load-if (not (location= real r)))
	 (imag :scs (double-reg) :to :save))
  (:arg-types double-float double-float)
  (:results (r :scs (complex-double-reg) :from (:argument 0)
	       :load-if (not (sc-is r complex-double-stack))))
  (:result-types complex-double-float)
  (:note _N"inline complex double-float creation")
  (:policy :fast-safe)
  (:vop-var vop)
  (:generator 5
    (sc-case r
      (complex-double-reg
       (let ((r-real (complex-double-reg-real-tn r)))
	 (unless (location= real r-real)
	   (move-double-reg r-real real)))
       (let ((r-imag (complex-double-reg-imag-tn r)))
	 (unless (location= imag r-imag)
	   (move-double-reg r-imag imag))))
      (complex-double-stack
       (let ((nfp (current-nfp-tn vop))
	     (offset (* (tn-offset r) vm:word-bytes)))
	 (unless (location= real r)
	   (inst stdf real nfp offset))
	 (inst stdf imag nfp (+ offset (* 2 vm:word-bytes))))))))

#+long-float
(define-vop (make-complex-long-float)
  (:translate complex)
  (:args (real :scs (long-reg) :target r
	       :load-if (not (location= real r)))
	 (imag :scs (long-reg) :to :save))
  (:arg-types long-float long-float)
  (:results (r :scs (complex-long-reg) :from (:argument 0)
	       :load-if (not (sc-is r complex-long-stack))))
  (:result-types complex-long-float)
  (:note _N"inline complex long-float creation")
  (:policy :fast-safe)
  (:vop-var vop)
  (:generator 5
    (sc-case r
      (complex-long-reg
       (let ((r-real (complex-long-reg-real-tn r)))
	 (unless (location= real r-real)
	   (move-long-reg r-real real)))
       (let ((r-imag (complex-long-reg-imag-tn r)))
	 (unless (location= imag r-imag)
	   (move-long-reg r-imag imag))))
      (complex-long-stack
       (let ((nfp (current-nfp-tn vop))
	     (offset (* (tn-offset r) vm:word-bytes)))
	 (unless (location= real r)
	   (store-long-reg real nfp offset))
	 (store-long-reg imag nfp (+ offset (* 4 vm:word-bytes))))))))

(define-vop (complex-single-float-value)
  (:args (x :scs (complex-single-reg descriptor-reg) :target r
	    :load-if (not (sc-is x complex-single-stack))))
  (:arg-types complex-single-float)
  (:results (r :scs (single-reg)))
  (:result-types single-float)
  (:variant-vars slot)
  (:policy :fast-safe)
  (:vop-var vop)
  (:generator 3
    (sc-case x
      (complex-single-reg
       (let ((value-tn (ecase slot
			 (:real (complex-single-reg-real-tn x))
			 (:imag (complex-single-reg-imag-tn x)))))
	 (unless (location= value-tn r)
	   (inst fmovs r value-tn))))
      (complex-single-stack
       (inst ldf r (current-nfp-tn vop) (* (+ (ecase slot (:real 0) (:imag 1))
					      (tn-offset x))
					   vm:word-bytes)))
      (descriptor-reg
       (inst ldf r x (- (* (ecase slot
			     (:real vm::complex-single-float-real-slot)
			     (:imag vm::complex-single-float-imag-slot))
			   vm:word-bytes)
			vm:other-pointer-type))))))

(define-vop (realpart/complex-single-float complex-single-float-value)
  (:translate realpart)
  (:note _N"complex single float realpart")
  (:variant :real))

(define-vop (imagpart/complex-single-float complex-single-float-value)
  (:translate imagpart)
  (:note _N"complex single float imagpart")
  (:variant :imag))

(define-vop (complex-double-float-value)
  (:args (x :scs (complex-double-reg descriptor-reg) :target r
	    :load-if (not (sc-is x complex-double-stack))))
  (:arg-types complex-double-float)
  (:results (r :scs (double-reg)))
  (:result-types double-float)
  (:variant-vars slot)
  (:policy :fast-safe)
  (:vop-var vop)
  (:generator 3
    (sc-case x
      (complex-double-reg
       (let ((value-tn (ecase slot
			 (:real (complex-double-reg-real-tn x))
			 (:imag (complex-double-reg-imag-tn x)))))
	 (unless (location= value-tn r)
	   (move-double-reg r value-tn))))
      (complex-double-stack
       (inst lddf r (current-nfp-tn vop) (* (+ (ecase slot (:real 0) (:imag 2))
					       (tn-offset x))
					    vm:word-bytes)))
      (descriptor-reg
       (inst lddf r x (- (* (ecase slot
				 (:real vm::complex-double-float-real-slot)
				 (:imag vm::complex-double-float-imag-slot))
			       vm:word-bytes)
			    vm:other-pointer-type))))))

(define-vop (realpart/complex-double-float complex-double-float-value)
  (:translate realpart)
  (:note _N"complex double float realpart")
  (:variant :real))

(define-vop (imagpart/complex-double-float complex-double-float-value)
  (:translate imagpart)
  (:note _N"complex double float imagpart")
  (:variant :imag))

#+long-float
(define-vop (complex-long-float-value)
  (:args (x :scs (complex-long-reg) :target r
	    :load-if (not (sc-is x complex-long-stack))))
  (:arg-types complex-long-float)
  (:results (r :scs (long-reg)))
  (:result-types long-float)
  (:variant-vars slot)
  (:policy :fast-safe)
  (:vop-var vop)
  (:generator 4
    (sc-case x
      (complex-long-reg
       (let ((value-tn (ecase slot
			 (:real (complex-long-reg-real-tn x))
			 (:imag (complex-long-reg-imag-tn x)))))
	 (unless (location= value-tn r)
	   (move-long-reg r value-tn))))
      (complex-long-stack
       (load-long-reg r (current-nfp-tn vop)
		      (* (+ (ecase slot (:real 0) (:imag 4)) (tn-offset x))
			 vm:word-bytes))))))

#+long-float
(define-vop (realpart/complex-long-float complex-long-float-value)
  (:translate realpart)
  (:note _N"complex long float realpart")
  (:variant :real))

#+long-float
(define-vop (imagpart/complex-long-float complex-long-float-value)
  (:translate imagpart)
  (:note _N"complex long float imagpart")
  (:variant :imag))



;;;; Complex float arithmetic

;;; These vops are intended to optimize some complex float arithmetic
;;; by removing lots of redundant moves that the compiler currently
;;; inserts.  It seems the moves are generated because of the way
;;; unboxed complex floats are represented as pairs of registers.  The
;;; compiler doesn't think we can use the parts directly and therefore
;;; copies the parts to another register before operating on them.
;;;
;;; If we had a peephole optimizer, we could make it remove the
;;; redundant moves instead.

#+complex-fp-vops
(progn

;; Negate a complex
(macrolet
    ((frob (float-type fneg cost)
       (let* ((vop-name (symbolicate "%NEGATE/COMPLEX-" float-type))
	      (c-type (symbolicate "COMPLEX-" float-type "-FLOAT"))
	      (complex-reg (symbolicate "COMPLEX-" float-type "-REG"))
	      (real-tn (symbolicate "COMPLEX-" float-type "-REG-REAL-TN"))
	      (imag-tn (symbolicate "COMPLEX-" float-type "-REG-IMAG-TN")))
	 `(define-vop (,vop-name)
	    (:args (x :scs (,complex-reg)))
	    (:arg-types ,c-type)
	    (:results (r :scs (,complex-reg)))
	    (:result-types ,c-type)
	    (:policy :fast-safe)
	    (:note _N"inline complex float arithmetic")
	    (:translate %negate)
	    (:generator ,cost
	      (let ((xr (,real-tn x))
		    (xi (,imag-tn x))
		    (rr (,real-tn r))
		    (ri (,imag-tn r)))
		(,@fneg rr xr)
		(,@fneg ri xi)))))))
  (frob single (inst fnegs) 4)
  (frob double (negate-double-reg) 4))

;; Add and subtract for two complex arguments
(macrolet
    ((frob (op inst float-type cost)
       (let* ((vop-name (symbolicate (symbol-name op) "/COMPLEX-" float-type "-FLOAT"))
	      (c-type (symbolicate "COMPLEX-" float-type "-FLOAT"))
	      (complex-reg (symbolicate "COMPLEX-" float-type "-REG"))
	      (real-part (symbolicate "COMPLEX-" float-type "-REG-REAL-TN"))
	      (imag-part (symbolicate "COMPLEX-" float-type "-REG-IMAG-TN")))
	 `(define-vop (,vop-name)
	   (:args (x :scs (,complex-reg)) (y :scs (,complex-reg)))
	   (:results (r :scs (,complex-reg)))
	   (:arg-types ,c-type ,c-type)
	   (:result-types ,c-type)
	   (:policy :fast-safe)
	   (:note _N"inline complex float arithmetic")
	   (:translate ,op)
	   (:generator ,cost
	    (let ((xr (,real-part x))
		  (xi (,imag-part x))
		  (yr (,real-part y))
		  (yi (,imag-part y))
		  (rr (,real-part r))
		  (ri (,imag-part r)))
	      (inst ,inst rr xr yr)
	      (inst ,inst ri xi yi)))))))
  (frob + fadds single 4)
  (frob + faddd double 4)
  (frob - fsubs single 4)
  (frob - fsubd double 4))

;; Add and subtract a complex and a float

(macrolet
    ((frob (size op fop cost)
       (let ((vop-name (symbolicate "COMPLEX-" size "-FLOAT-"
				    op
				    "-" size "-FLOAT"))
	     (complex-reg (symbolicate "COMPLEX-" size "-REG"))
	     (real-reg (symbolicate size "-REG"))
	     (c-type (symbolicate "COMPLEX-" size "-FLOAT"))
	     (r-type (symbolicate size "-FLOAT"))
	     (real-part (symbolicate "COMPLEX-" size "-REG-REAL-TN"))
	     (imag-part (symbolicate "COMPLEX-" size "-REG-IMAG-TN"))
	     (load (ecase size
		     (single 'ldf)
		     (double 'lddf)))
	     (zero-sym (ecase size
			 (single '*fp-constant-0f0*)
			 (double '*fp-constant-0d0*)))
	     (slot (ecase size
		     (single vm:single-float-value-slot)
		     (double vm:double-float-value-slot))))
	 `(define-vop (,vop-name)
	      (:args (x :scs (,complex-reg))
	             (y :scs (,real-reg)))
	    (:results (r :scs (,complex-reg)))
	    (:arg-types ,c-type ,r-type)
	    (:result-types ,c-type)
	    (:policy :fast-safe)
	    (:temporary (:scs (,real-reg)) zero)
	    (:temporary (:scs (descriptor-reg)) zero-val)
	    (:note _N"inline complex float/float arithmetic")
	    (:translate ,op)
	    (:generator ,cost
	      (let ((xr (,real-part x))
		    (xi (,imag-part x))
		    (rr (,real-part r))
		    (ri (,imag-part r)))
		;; Load up the necessary floating-point zero that we
		;; need.  It would be nice if we could do something
		;; like xr-xr to get a floating-point zero, but that
		;; can cause spurious signals if xr is an infinity or
		;; NaN.
		(load-symbol-value zero-val ,zero-sym)
		(inst ,load zero zero-val (- (* ,slot vm:word-bytes)
					     vm:other-pointer-type))
		(inst ,fop rr xr y)
		(inst ,fop ri xi zero)))))))
  
  (frob single + fadds 2)
  (frob single - fsubs 2)
  (frob double + faddd 4)
  (frob double - fsubd 4))

;; Add a float and a complex
(macrolet
    ((frob (size fop cost)
       (let ((vop-name
	      (symbolicate size "-FLOAT-+-COMPLEX-" size "-FLOAT"))
	     (complex-reg (symbolicate "COMPLEX-" size "-REG"))
	     (real-reg (symbolicate size "-REG"))
	     (c-type (symbolicate "COMPLEX-" size "-FLOAT"))
	     (r-type (symbolicate size "-FLOAT"))
	     (real-part (symbolicate "COMPLEX-" size "-REG-REAL-TN"))
	     (imag-part (symbolicate "COMPLEX-" size "-REG-IMAG-TN"))
	     (load (ecase size
		     (single 'ldf)
		     (double 'lddf)))
	     (zero-sym (ecase size
			 (single '*fp-constant-0f0*)
			 (double '*fp-constant-0d0*)))
	     (slot (ecase size
		     (single vm:single-float-value-slot)
		     (double vm:double-float-value-slot))))
	 `(define-vop (,vop-name)
	      (:args (y :scs (,real-reg))
	             (x :scs (,complex-reg)))
	    (:results (r :scs (,complex-reg)))
	    (:arg-types ,r-type ,c-type)
	    (:result-types ,c-type)
	    (:temporary (:scs (,real-reg)) zero)
	    (:temporary (:scs (descriptor-reg)) zero-val)
	    (:policy :fast-safe)
	    (:note _N"inline complex float/float arithmetic")
	    (:translate +)
	    (:generator ,cost
	      (let ((xr (,real-part x))
		    (xi (,imag-part x))
		    (rr (,real-part r))
		    (ri (,imag-part r)))
		(load-symbol-value zero-val ,zero-sym)
		(inst ,load zero zero-val (- (* ,slot vm:word-bytes)
					     vm:other-pointer-type))
		(inst ,fop rr xr y)
		(inst ,fop ri xi zero)))))))
  (frob single fadds 1)
  (frob double faddd 2))

;; Subtract a complex from a float.
;;
(macrolet
    ((frob (size fop cost)
       (let ((vop-name (symbolicate size "-FLOAT---COMPLEX-" size "-FLOAT"))
	     (complex-reg (symbolicate "COMPLEX-" size "-REG"))
	     (real-reg (symbolicate size "-REG"))
	     (c-type (symbolicate "COMPLEX-" size "-FLOAT"))
	     (r-type (symbolicate size "-FLOAT"))
	     (real-part (symbolicate "COMPLEX-" size "-REG-REAL-TN"))
	     (imag-part (symbolicate "COMPLEX-" size "-REG-IMAG-TN"))
	     (load (ecase size
		     (single 'ldf)
		     (double 'lddf)))
	     (zero-sym (ecase size
			 (single '*fp-constant-0f0*)
			 (double '*fp-constant-0d0*)))
	     (slot (ecase size
		     (single vm:single-float-value-slot)
		     (double vm:double-float-value-slot))))
	 `(define-vop (,vop-name)
	      (:args (x :scs (,real-reg)) (y :scs (,complex-reg)))
	    (:results (r :scs (,complex-reg)))
	    (:arg-types ,r-type ,c-type)
	    (:result-types ,c-type)
	    (:temporary (:scs (,real-reg)) zero)
	    (:temporary (:scs (descriptor-reg)) zero-val)
	    (:policy :fast-safe)
	    (:note _N"inline complex float/float arithmetic")
	    (:translate -)
	    (:generator ,cost
	      (let ((yr (,real-part y))
		    (yi (,imag-part y))
		    (rr (,real-part r))
		    (ri (,imag-part r)))
		(load-symbol-value zero-val ,zero-sym)
		(inst ,load zero zero-val (- (* ,slot vm:word-bytes)
					     vm:other-pointer-type))
		(inst ,fop rr x yr)
		(inst ,fop ri zero yi)))))))

  (frob single fsubs 2)
  (frob double fsubd 2))

;; Multiply two complex numbers
(macrolet
    ((frob (size fmul fadd fsub mov cost)
       (let ((vop-name (symbolicate "*/COMPLEX-" size "-FLOAT"))
	     (complex-reg (symbolicate "COMPLEX-" size "-REG"))
	     (real-reg (symbolicate size "-REG"))
	     (c-type (symbolicate "COMPLEX-" size "-FLOAT"))
	     (real-part (symbolicate "COMPLEX-" size "-REG-REAL-TN"))
	     (imag-part (symbolicate "COMPLEX-" size "-REG-IMAG-TN")))
	 `(define-vop (,vop-name)
	    (:args (x :scs (,complex-reg))
	           (y :scs (,complex-reg)))
	    (:results (r :scs (,complex-reg)))
	    (:arg-types ,c-type ,c-type)
	    (:result-types ,c-type)
	    (:policy :fast-safe)
	    (:note _N"inline complex float multiplication")
	    (:translate *)
	    (:temporary (:scs (,real-reg)) p1 p2)
	    (:generator ,cost
	      (let ((xr (,real-part x))
		    (xi (,imag-part x))
		    (yr (,real-part y))
		    (yi (,imag-part y))
		    (rr (,real-part r))
		    (ri (,imag-part r)))
		;; Be careful because r might be packed into the same
		;; location as either x or y.  We have to be careful
		;; not to modify either x or y until all uses of x or
		;; y.
		(inst ,fmul p1 yr xr)	; p1 = xr*yr
		(inst ,fmul p2 xi yi)	; p2 = xi*yi
		(inst ,fsub p2 p1 p2)	; p2 = xr*yr - xi*yi
		(inst ,fmul p1 xr yi)	; p1 = xr*yi
		(inst ,fmul ri xi yr)	; ri = xi*yr
		(inst ,fadd ri ri p1)	; ri = xi*yr + xr*yi
		(,@mov rr p2)))))))

  (frob single fmuls fadds fsubs (inst fmovs) 6)
  (frob double fmuld faddd fsubd (move-double-reg) 6))

;; Multiply a complex by a float.  The case of float * complex is
;; handled by a deftransform to convert it to the complex*float case.
(macrolet
    ((frob (float-type fmul mov cost)
       (let* ((vop-name (symbolicate "COMPLEX-"
				     float-type
				     "-FLOAT-*-"
				     float-type
				     "-FLOAT"))
	      (vop-name-r (symbolicate float-type
				       "-FLOAT-*-COMPLEX-"
				       float-type
				       "-FLOAT"))
	      (complex-sc-type (symbolicate "COMPLEX-" float-type "-REG"))
	      (real-sc-type (symbolicate float-type "-REG"))
	      (c-type (symbolicate "COMPLEX-" float-type "-FLOAT"))
	      (r-type (symbolicate float-type "-FLOAT"))
	      (real-part (symbolicate "COMPLEX-" float-type "-REG-REAL-TN"))
	      (imag-part (symbolicate "COMPLEX-" float-type "-REG-IMAG-TN")))
	 `(progn
	   ;; Complex * float
	   (define-vop (,vop-name)
	     (:args (x :scs (,complex-sc-type))
	            (y :scs (,real-sc-type)))
	     (:results (r :scs (,complex-sc-type)))
	     (:arg-types ,c-type ,r-type)
	     (:result-types ,c-type)
	     (:policy :fast-safe)
	     (:note _N"inline complex float arithmetic")
	     (:translate *)
	     (:temporary (:scs (,real-sc-type)) temp)
	     (:generator ,cost
	      (let ((xr (,real-part x))
		    (xi (,imag-part x))
		    (rr (,real-part r))
		    (ri (,imag-part r)))
		(cond ((location= y rr)
		       (inst ,fmul temp xr y) ; xr * y
		       (inst ,fmul ri xi y) ; xi * yi
		       (,@mov rr temp))
		      (t
		       (inst ,fmul rr xr y)
		       (inst ,fmul ri xi y))))))
	   ;; Float * complex
	   (define-vop (,vop-name-r)
	     (:args (y :scs (,real-sc-type))
	            (x :scs (,complex-sc-type)))
	     (:results (r :scs (,complex-sc-type)))
	     (:arg-types ,r-type ,c-type)
	     (:result-types ,c-type)
	     (:policy :fast-safe)
	     (:note _N"inline complex float arithmetic")
	     (:translate *)
	     (:temporary (:scs (,real-sc-type)) temp)
	     (:generator ,cost
	      (let ((xr (,real-part x))
		    (xi (,imag-part x))
		    (rr (,real-part r))
		    (ri (,imag-part r)))
		(cond ((location= y rr)
		       (inst ,fmul temp xr y) ; xr * y
		       (inst ,fmul ri xi y) ; xi * yi
		       (,@mov rr temp))
		      (t
		       (inst ,fmul rr xr y)
		       (inst ,fmul ri xi y))))))))))
  (frob single fmuls (inst fmovs) 4)
  (frob double fmuld (move-double-reg) 4))


;; Divide a complex by a complex

;; Here's how we do a complex division
;;
;; Compute (xr + i*xi)/(yr + i*yi)
;;
;; Assume |yi| < |yr|.  Then
;;
;; (xr + i*xi)      (xr + i*xi)
;; ----------- = -----------------
;; (yr + i*yi)   yr*(1 + i*(yi/yr))
;;
;;               (xr + i*xi)*(1 - i*(yi/yr))
;;             = ---------------------------
;;                   yr*(1 + (yi/yr)^2)
;;
;;               (xr + (yi/yr)*xi) + i*(xi - (yi/yr)*xr)
;;             = --------------------------------------
;;                        yr + (yi/yr)*yi
;;
;;
;; We do the similar thing when |yi| > |yr|.  The result is
;;
;;     
;; (xr + i*xi)      (xr + i*xi)
;; ----------- = -----------------
;; (yr + i*yi)   yi*((yr/yi) + i)
;;
;;               (xr + i*xi)*((yr/yi) - i)
;;             = -------------------------
;;                  yi*((yr/yi)^2 + 1)
;;
;;               (xr*(yr/yi) + xi) + i*(xi*(yr/yi) - xr)
;;             = ---------------------------------------
;;                       yi + (yr/yi)*yr
;;

(macrolet
    ((frob (float-type fcmp fadd fsub fmul fdiv fabs cost)
       (let ((vop-name (symbolicate "//COMPLEX-" float-type "-FLOAT"))
	     (complex-reg (symbolicate "COMPLEX-" float-type "-REG"))
	     (real-reg (symbolicate float-type "-REG"))
	     (c-type (symbolicate "COMPLEX-" float-type "-FLOAT"))
	     (real-part (symbolicate "COMPLEX-" float-type "-REG-REAL-TN"))
	     (imag-part (symbolicate "COMPLEX-" float-type "-REG-IMAG-TN")))
	 `(define-vop (,vop-name)
	    (:args (x :scs (,complex-reg))
		   (y :scs (,complex-reg)))
	    (:results (r :scs (,complex-reg)))
	    (:arg-types ,c-type ,c-type)
	    (:result-types ,c-type)
	    (:policy :fast-safe)
	    (:note _N"inline complex float division")
	    (:translate /)
	    (:temporary (:sc ,real-reg) ratio)
	    (:temporary (:sc ,real-reg) den)
	    (:temporary (:sc ,real-reg) temp-r)
	    (:temporary (:sc ,real-reg) temp-i)
	    (:generator ,cost
	      (let ((xr (,real-part x))
		    (xi (,imag-part x))
		    (yr (,real-part y))
		    (yi (,imag-part y))
		    (rr (,real-part r))
		    (ri (,imag-part r))
		    (bigger (gen-label))
		    (done (gen-label)))
		(,@fabs ratio yr)
		(,@fabs den yi)
		(inst ,fcmp den ratio)
		(unless (backend-featurep :sparc-v9)
		  (inst nop))
		(inst fb :ge bigger)
		(inst nop)
		;; The case of |yi| <= |yr|
		(inst ,fdiv ratio yi yr) ; ratio = yi/yr
		(inst ,fmul den ratio yi)
		(inst ,fmul temp-r ratio xi)
		(inst ,fmul temp-i ratio xr)

		(inst ,fadd den den yr) ; den = yr + (yi/yr)*yi
		(inst ,fadd temp-r temp-r xr) ; temp-r = xr + (yi/yr)*xi
		(inst b done)
		(inst ,fsub temp-i xi temp-i) ; temp-i = xi - (yi/yr)*xr


		(emit-label bigger)
		;; The case of |yi| > |yr|
		(inst ,fdiv ratio yr yi) ; ratio = yr/yi
		(inst ,fmul den ratio yr)
		(inst ,fmul temp-r ratio xr)
		(inst ,fmul temp-i ratio xi)

		(inst ,fadd den den yi) ; den = yi + (yr/yi)*yr
		(inst ,fadd temp-r temp-r xi) ; temp-r = xi + xr*(yr/yi)

		(inst ,fsub temp-i temp-i xr) ; temp-i = xi*(yr/yi) - xr

		(emit-label done)

		(inst ,fdiv rr temp-r den)
		(inst ,fdiv ri temp-i den)
		))))))

  (frob single fcmps fadds fsubs fmuls fdivs (inst fabss) 15)
  (frob double fcmpd faddd fsubd fmuld fdivd (abs-double-reg) 15))


;; Divide a complex by a real
(macrolet
    ((frob (float-type fdiv fmov cost)
       (let* ((vop-name (symbolicate "COMPLEX-" float-type "-FLOAT-/-" float-type "-FLOAT"))
	      (complex-sc-type (symbolicate "COMPLEX-" float-type "-REG"))
	      (real-sc-type (symbolicate float-type "-REG"))
	      (c-type (symbolicate "COMPLEX-" float-type "-FLOAT"))
	      (r-type (symbolicate float-type "-FLOAT"))
	      (real-part (symbolicate "COMPLEX-" float-type "-REG-REAL-TN"))
	      (imag-part (symbolicate "COMPLEX-" float-type "-REG-IMAG-TN")))
	 `(define-vop (,vop-name)
	   (:args (x :scs (,complex-sc-type)) (y :scs (,real-sc-type)))
	   (:results (r :scs (,complex-sc-type)))
	   (:arg-types ,c-type ,r-type)
	   (:result-types ,c-type)
	   (:policy :fast-safe)
	   (:note _N"inline complex float arithmetic")
	   (:translate /)
	   (:temporary (:sc ,real-sc-type) tmp)
	   (:generator ,cost
	    (let ((xr (,real-part x))
		  (xi (,imag-part x))
		  (rr (,real-part r))
		  (ri (,imag-part r)))
	      (cond ((location= r y)
		     (inst ,fdiv tmp xr y)
		     (inst ,fdiv ri xi y)
		     (,@fmov rr tmp))
		    (t
		     (inst ,fdiv rr xr y) ; xr * y
		     (inst ,fdiv ri xi y) ; xi * yi
		     ))))))))
  (frob single fdivs (inst fmovs) 2)
  (frob double fdivd (move-double-reg) 2))

;; Divide a real by a complex

(macrolet
    ((frob (float-type fcmp fadd fmul fdiv fneg fabs cost)
       (let ((vop-name (symbolicate float-type "-FLOAT-/-COMPLEX-" float-type "-FLOAT"))
	     (complex-reg (symbolicate "COMPLEX-" float-type "-REG"))
	     (real-reg (symbolicate float-type "-REG"))
	     (r-type (symbolicate float-type "-FLOAT"))
	     (c-type (symbolicate "COMPLEX-" float-type "-FLOAT"))
	     (real-tn (symbolicate "COMPLEX-" float-type "-REG-REAL-TN"))
	     (imag-tn (symbolicate "COMPLEX-" float-type "-REG-IMAG-TN")))
	 `(define-vop (,vop-name)
	    (:args (x :scs (,real-reg))
		   (y :scs (,complex-reg)))
	    (:results (r :scs (,complex-reg)))
	    (:arg-types ,r-type ,c-type)
	    (:result-types ,c-type)
	    (:policy :fast-safe)
	    (:note _N"inline complex float division")
	    (:translate /)
	    (:temporary (:sc ,real-reg) ratio)
	    (:temporary (:sc ,real-reg) den)
	    (:generator ,cost
	      (let ((yr (,real-tn y))
		    (yi (,imag-tn y))
		    (rr (,real-tn r))
		    (ri (,imag-tn r))
		    (bigger (gen-label))
		    (done (gen-label)))
		(,@fabs ratio yr)
		(,@fabs den yi)
		(inst ,fcmp den ratio)
		(unless (backend-featurep :sparc-v9)
		  (inst nop))
		(inst fb :ge bigger)
		(inst nop)
		;; The case of |yi| <= |yr|
		(inst ,fdiv ratio yi yr) ; ratio = yi/yr
		(inst ,fmul den ratio yi)
		(inst ,fadd den den yr) ; den = yr + (yi/yr)*yi

		(inst ,fmul ri ratio x) ; ri = (yi/yr)*x
		(inst ,fdiv rr x den)	; rr = x/den
		(inst b done)
		(inst ,fdiv ri ri den) ; ri = (yi/yr)*x/den

		(emit-label bigger)
		;; The case of |yi| > |yr|
		(inst ,fdiv ratio yr yi) ; ratio = yr/yi
		(inst ,fmul den ratio yr)
		(inst ,fadd den den yi) ; den = yi + (yr/yi)*yr

		(inst ,fmul ri ratio x) ; ri = (yr/yi)*x
		(inst ,fdiv rr ri den) ; rr = (yr/yi)*x/den
		(inst ,fdiv ri x den) ; ri = x/den
		(emit-label done)

		(,@fneg ri ri)))))))

  (frob single fcmps fadds fmuls fdivs (inst fnegs) (inst fabss) 10)
  (frob double fcmpd faddd fmuld fdivd (negate-double-reg) (abs-double-reg) 10))

;; Conjugate of a complex number

(macrolet
    ((frob (float-type fneg fmov cost)
       (let ((vop-name (symbolicate "CONJUGATE/COMPLEX-" float-type "-FLOAT"))
	     (complex-reg (symbolicate "COMPLEX-" float-type "-REG"))
	     (c-type (symbolicate "COMPLEX-" float-type "-FLOAT"))
	     (real-part (symbolicate "COMPLEX-" float-type "-REG-REAL-TN"))
	     (imag-part (symbolicate "COMPLEX-" float-type "-REG-IMAG-TN")))
	 `(define-vop (,vop-name)
	    (:args (x :scs (,complex-reg)))
	    (:results (r :scs (,complex-reg)))
	    (:arg-types ,c-type)
	    (:result-types ,c-type)
	    (:policy :fast-safe)
	    (:note _N"inline complex conjugate")
	    (:translate conjugate)
	    (:generator ,cost
	      (let ((xr (,real-part x))
		    (xi (,imag-part x))
		    (rr (,real-part r))
		    (ri (,imag-part r)))
		(,@fneg ri xi)
		(unless (location= rr xr)
		  (,@fmov rr xr))))))))

  (frob single (inst fnegs) (inst fmovs) 4)
  (frob double (negate-double-reg) (move-double-reg) 4))

;; Compare a float with a complex or a complex with a float
#+nil
(macrolet
    ((frob (name name-r f-type c-type)
       `(progn
	 (defknown ,name (,f-type ,c-type) t)
	 (defknown ,name-r (,c-type ,f-type) t)
	 (defun ,name (x y)
	   (declare (type ,f-type x)
		    (type ,c-type y))
	   (,name x y))
	 (defun ,name-r (x y)
	   (declare (type ,c-type x)
		    (type ,f-type y))
	   (,name-r x y))
	 )))
  (frob %compare-complex-single-single %compare-single-complex-single
	single-float (complex single-float))
  (frob %compare-complex-double-double %compare-double-complex-double
	double-float (complex double-float)))
	   
#+nil
(macrolet
    ((frob (trans-1 trans-2 float-type fcmp fsub)
       (let ((vop-name
	      (symbolicate "COMPLEX-" float-type "-FLOAT-"
			   float-type "-FLOAT-COMPARE"))
	     (vop-name-r
	      (symbolicate float-type "-FLOAT-COMPLEX-"
			   float-type "-FLOAT-COMPARE"))
	     (complex-reg (symbolicate "COMPLEX-" float-type "-REG"))
	     (real-reg (symbolicate float-type "-REG"))
	     (c-type (symbolicate "COMPLEX-" float-type "-FLOAT"))
	     (r-type (symbolicate float-type "-FLOAT"))
	     (real-part (symbolicate "COMPLEX-" float-type "-REG-REAL-TN"))
	     (imag-part (symbolicate "COMPLEX-" float-type "-REG-IMAG-TN")))
	 `(progn
	    ;; (= float complex)
	    (define-vop (,vop-name)
	      (:args (x :scs (,real-reg))
		     (y :scs (,complex-reg)))
	      (:arg-types ,r-type ,c-type)
	      (:translate ,trans-1)
	      (:conditional)
	      (:info target not-p)
	      (:policy :fast-safe)
	      (:note _N"inline complex float/float comparison")
	      (:vop-var vop)
	      (:save-p :compute-only)
	      (:temporary (:sc ,real-reg) fp-zero)
	      (:guard (not (backend-featurep :sparc-v9)))
	      (:generator 6
	       (note-this-location vop :internal-error)
	       (let ((yr (,real-part y))
		     (yi (,imag-part y)))
		 ;; Set fp-zero to zero
		 (inst ,fsub fp-zero fp-zero fp-zero)
		 (inst ,fcmp x yr)
		 (inst nop)
		 (inst fb (if not-p :ne :eq) target #+sparc-v9 :fcc0 #+sparc-v9 :pn)
		 (inst ,fcmp yi fp-zero)
		 (inst nop)
		 (inst fb (if not-p :ne :eq) target #+sparc-v9 :fcc0 #+sparc-v9 :pn)
		 (inst nop))))
	    ;; (= complex float)
	    (define-vop (,vop-name-r)
	      (:args (y :scs (,complex-reg))
	             (x :scs (,real-reg)))
	      (:arg-types ,c-type ,r-type)
	      (:translate ,trans-2)
	      (:conditional)
	      (:info target not-p)
	      (:policy :fast-safe)
	      (:note _N"inline complex float/float comparison")
	      (:vop-var vop)
	      (:save-p :compute-only)
	      (:temporary (:sc ,real-reg) fp-zero)
	      (:guard (not (backend-featurep :sparc-v9)))
	      (:generator 6
	       (note-this-location vop :internal-error)
	       (let ((yr (,real-part y))
		     (yi (,imag-part y)))
		 ;; Set fp-zero to zero
		 (inst ,fsub fp-zero fp-zero fp-zero)
		 (inst ,fcmp x yr)
		 (inst nop)
		 (inst fb (if not-p :ne :eq) target #+sparc-v9 :fcc0 #+sparc-v9 :pn)
		 (inst ,fcmp yi fp-zero)
		 (inst nop)
		 (inst fb (if not-p :ne :eq) target #+sparc-v9 :fcc0 #+sparc-v9 :pn)
		 (inst nop))))))))
  (frob %compare-complex-single-single %compare-single-complex-single
	single fcmps fsubs)
  (frob %compare-complex-double-double %compare-double-complex-double
	double fcmpd fsubd))

;; Compare two complex numbers for equality
(macrolet
    ((frob (float-type fcmp)
       (let ((vop-name
	      (symbolicate "COMPLEX-" float-type "-FLOAT-COMPARE"))
	     (complex-reg (symbolicate "COMPLEX-" float-type "-REG"))
	     (c-type (symbolicate "COMPLEX-" float-type "-FLOAT"))
	     (real-part (symbolicate "COMPLEX-" float-type "-REG-REAL-TN"))
	     (imag-part (symbolicate "COMPLEX-" float-type "-REG-IMAG-TN")))
	 `(define-vop (,vop-name)
	    (:args (x :scs (,complex-reg))
		   (y :scs (,complex-reg)))
	    (:arg-types ,c-type ,c-type)
	    (:translate =)
	    (:conditional)
	    (:info target not-p)
	    (:policy :fast-safe)
	    (:note _N"inline complex float comparison")
	    (:vop-var vop)
	    (:save-p :compute-only)
	    (:guard (not (backend-featurep :sparc-v9)))
	    (:generator 6
	      (note-this-location vop :internal-error)
	      (let ((xr (,real-part x))
		    (xi (,imag-part x))
		    (yr (,real-part y))
		    (yi (,imag-part y)))
		(inst ,fcmp xr yr)
		(inst nop)
		(inst fb (if not-p :ne :eq) target #+sparc-v9 :fcc0 #+sparc-v9 :pn)
		(inst ,fcmp xi yi)
		(inst nop)
		(inst fb (if not-p :ne :eq) target #+sparc-v9 :fcc0 #+sparc-v9 :pn)
		(inst nop)))))))
  (frob single fcmps)
  (frob double fcmpd))

;; Compare a complex with a complex, for V9
(macrolet
    ((frob (float-type fcmp)
       (let ((vop-name
	      (symbolicate "V9-COMPLEX-" float-type "-FLOAT-COMPARE"))
	     (complex-reg (symbolicate "COMPLEX-" float-type "-REG"))
	     (c-type (symbolicate "COMPLEX-" float-type "-FLOAT"))
	     (real-part (symbolicate "COMPLEX-" float-type "-REG-REAL-TN"))
	     (imag-part (symbolicate "COMPLEX-" float-type "-REG-IMAG-TN")))
	 `(define-vop (,vop-name)
	    (:args (x :scs (,complex-reg))
		   (y :scs (,complex-reg)))
	    (:arg-types ,c-type ,c-type)
	    (:translate =)
	    (:conditional)
	    (:info target not-p)
	    (:policy :fast-safe)
	    (:note _N"inline complex float comparison")
	    (:vop-var vop)
	    (:save-p :compute-only)
	    (:temporary (:sc descriptor-reg) true)
	    (:guard (backend-featurep :sparc-v9))
	    (:generator 6
	      (note-this-location vop :internal-error)
	      (let ((xr (,real-part x))
		    (xi (,imag-part x))
		    (yr (,real-part y))
		    (yi (,imag-part y)))
		;; Assume comparison is true
		(load-symbol true t)
		(inst ,fcmp xr yr)
		(inst cmove (if not-p :eq :ne) true null-tn :fcc0)
		(inst ,fcmp xi yi)
		(inst cmove (if not-p :eq :ne) true null-tn :fcc0)
		(inst cmp true null-tn)
		(inst b (if not-p :eq :ne) target :pt)
		(inst nop)))))))
  (frob single fcmps)
  (frob double fcmpd))


;; Instead of providing vops, we just transform these to the obvious
;; implementation.  There are probably a few unnecessary moves.

(macrolet
    ((cvt (name prototype)
       `(progn
	 (deftransform ,name ((n) (real) * :when :both)
	   '(complex (float n ,prototype)))
	 (deftransform ,name ((n) (complex) * :when :both)
	   '(complex (float (realpart n) ,prototype)
	             (float (imagpart n) ,prototype))))))
  (cvt %complex-single-float 1f0)
  (cvt %complex-double-float 1d0))


) ; end progn complex-fp-vops

#+sparc-v9
(progn

;; Vops to take advantage of the conditional move instruction
;; available on the Sparc V9
  
(defknown (%%max %%min) ((or (unsigned-byte #.vm:word-bits)
			     (signed-byte #.vm:word-bits)
			     single-float double-float)
			 (or (unsigned-byte #.vm:word-bits)
			     (signed-byte #.vm:word-bits)
			     single-float double-float))
  (or (unsigned-byte #.vm:word-bits)
      (signed-byte #.vm:word-bits)
      single-float double-float)
  (movable foldable flushable))

;; We need these definitions for byte-compiled code
(defun %%min (x y)
  (declare (type (or (unsigned-byte 32) (signed-byte 32)
		     single-float double-float) x y))
  (if (<= x y)
      x y))

(defun %%max (x y)
  (declare (type (or (unsigned-byte 32) (signed-byte 32)
		     single-float double-float) x y))
  (if (>= x y)
      x y))
  
(macrolet
    ((frob (name sc-type type compare cmov cost cc max min note)
       (let ((vop-name (symbolicate name "-" type "=>" type))
	     (trans-name (symbolicate "%%" name)))
	 `(define-vop (,vop-name)
	    (:args (x :scs (,sc-type))
		   (y :scs (,sc-type)))
	    (:results (r :scs (,sc-type)))
	    (:arg-types ,type ,type)
	    (:result-types ,type)
	    (:policy :fast-safe)
	    (:note ,note)
	    (:translate ,trans-name)
	    (:guard (backend-featurep :sparc-v9))
	    (:generator ,cost
	      (inst ,compare x y)
	      (cond ((location= r x)
		     ;; If x < y, need to move y to r, otherwise r already has
		     ;; the max.
		     (inst ,cmov ,min r y ,cc))
		    ((location= r y)
		     ;; If x > y, need to move x to r, otherwise r already has
		     ;; the max.
		     (inst ,cmov ,max r x ,cc))
		    (t
		     ;; It doesn't matter what R is, just copy the min to R.
		     (inst ,cmov ,max r x ,cc)
		     (inst ,cmov ,min r y ,cc))))))))
  (frob max single-reg single-float fcmps cfmovs 3
	:fcc0 :ge :l _N"inline float max")
  (frob max double-reg double-float fcmpd cfmovd 3
	:fcc0 :ge :l _N"inline float max")
  (frob min single-reg single-float fcmps cfmovs 3
	:fcc0 :l :ge _N"inline float min")
  (frob min double-reg double-float fcmpd cfmovd 3
	:fcc0 :l :ge _N"inline float min")
  ;; Strictly speaking these aren't float ops, but it's convenient to
  ;; do them here.
  ;;
  ;; The cost is here is the worst case number of instructions.  For
  ;; 32-bit integer operands, we add 2 more to account for the
  ;; untagging of fixnums, if necessary.
  (frob max signed-reg signed-num cmp cmove 5
	:icc :ge :lt _N"inline (signed-byte 32) max")
  (frob max unsigned-reg unsigned-num cmp cmove 5
	:icc :ge :lt _N"inline (unsigned-byte 32) max")
  ;; For fixnums, make the cost lower so we don't have to untag the
  ;; numbers.
  (frob max any-reg tagged-num cmp cmove 3
	:icc :ge :lt _N"inline fixnum max")
  (frob min signed-reg signed-num cmp cmove 5
	:icc :lt :ge _N"inline (signed-byte 32) min")
  (frob min unsigned-reg unsigned-num cmp cmove 5
	:icc :lt :ge _N"inline (unsigned-byte 32) min")
  ;; For fixnums, make the cost lower so we don't have to untag the
  ;; numbers.
  (frob min any-reg tagged-num cmp cmove 3
	:icc :lt :ge _N"inline fixnum min"))
	   
#+nil
(define-vop (max-boxed-double-float=>boxed-double-float)
  (:args (x :scs (descriptor-reg))
	 (y :scs (descriptor-reg)))
  (:results (r :scs (descriptor-reg)))
  (:arg-types double-float double-float)
  (:result-types double-float)
  (:policy :fast-safe)
  (:note _N"inline float max/min")
  (:translate %max-double-float)
  (:temporary (:scs (double-reg)) xval)
  (:temporary (:scs (double-reg)) yval)
  (:guard (backend-featurep :sparc-v9))
  (:vop-var vop)
  (:generator 3
    (let ((offset (- (* vm:double-float-value-slot vm:word-bytes)
		     vm:other-pointer-type)))
      (inst lddf xval x offset)
      (inst lddf yval y offset)
      (inst fcmpd xval yval)
      (cond ((location= r x)
	     ;; If x < y, need to move y to r, otherwise r already has
	     ;; the max.
	     (inst cmove :l r y :fcc0))
	    ((location= r y)
	     ;; If x > y, need to move x to r, otherwise r already has
	     ;; the max.
	     (inst cmove :ge r x :fcc0))
	    (t
	     ;; It doesn't matter what R is, just copy the min to R.
	     (inst cmove :ge r x :fcc0)
	     (inst cmove :l r y :fcc0))))))
    
)

(in-package "C")
#+sparc-v9
(progn
;;; The sparc-v9 architecture has conditional move instructions that
;;; can be used.  This should be faster than using the obvious if
;;; expression since we don't have to do branches.
  
(def-source-transform min (&rest args)
  (case (length args)
    ((0 2) (values nil t))
    (1 `(values (the real ,(first args))))
    (t (c::associate-arguments 'min (first args) (rest args)))))

(def-source-transform max (&rest args)
  (case (length args)
    ((0 2) (values nil t))
    (1 `(values (the real ,(first args))))
    (t (c::associate-arguments 'max (first args) (rest args)))))

;; Derive the types of max and min
(defoptimizer (max derive-type) ((x y))
  ;; It's Y < X instead of X < Y because that's how the
  ;; source-transform, the deftransform and the max function do the
  ;; comparisons.  This is important if the types of X and Y are
  ;; different types, like integer vs double-float because CMUCL
  ;; returns the actual arg, instead of applying float-contagion to
  ;; the result.
  (multiple-value-bind (definitely-< definitely->=)
      (ir1-transform-<-helper y x)
    (cond (definitely-<
	      (continuation-type x))
	  (definitely->=
	      (continuation-type y))
	  (t
	   (make-canonical-union-type (list (continuation-type x)
					    (continuation-type y)))))))

(defoptimizer (min derive-type) ((x y))
  (multiple-value-bind (definitely-> definitely-<=)
      (ir1-transform-<-helper y x)
    (cond (definitely-<=
	      (continuation-type x))
	  (definitely->
	      (continuation-type y))
	  (t
	   (make-canonical-union-type (list (continuation-type x)
					    (continuation-type y)))))))

(deftransform max ((x y) (number number) * :when :both)
  (let ((x-type (continuation-type x))
	(y-type (continuation-type y))
	(signed (specifier-type '(signed-byte #.vm:word-bits)))
	(unsigned (specifier-type '(unsigned-byte #.vm:word-bits)))
	(d-float (specifier-type 'double-float))
	(s-float (specifier-type 'single-float)))
    ;; Use %%max if both args are good types of the same type.  As a
    ;; last resort, use the obvious comparison to select the desired
    ;; element.
    (cond ((and (csubtypep x-type signed)
		(csubtypep y-type signed))
	   `(sparc::%%max x y))
	  ((and (csubtypep x-type unsigned)
		(csubtypep y-type unsigned))
	   `(sparc::%%max x y))
	  ((and (csubtypep x-type d-float)
		(csubtypep y-type d-float))
	   `(sparc::%%max x y))
	  ((and (csubtypep x-type s-float)
		(csubtypep y-type s-float))
	   `(sparc::%%max x y))
	  (t
	   (let ((arg1 (gensym))
		 (arg2 (gensym)))
	     `(let ((,arg1 x)
		    (,arg2 y))
	       (if (> ,arg1 ,arg2)
		   ,arg1 ,arg2)))))))

(deftransform min ((x y) (real real) * :when :both)
  (let ((x-type (continuation-type x))
	(y-type (continuation-type y))
	(signed (specifier-type '(signed-byte #.vm:word-bits)))
	(unsigned (specifier-type '(unsigned-byte #.vm:word-bits)))
	(d-float (specifier-type 'double-float))
	(s-float (specifier-type 'single-float)))
    (cond ((and (csubtypep x-type signed)
		(csubtypep y-type signed))
	   `(sparc::%%min x y))
	  ((and (csubtypep x-type unsigned)
		(csubtypep y-type unsigned))
	   `(sparc::%%min x y))
	  ((and (csubtypep x-type d-float)
		(csubtypep y-type d-float))
	   `(sparc::%%min x y))
	  ((and (csubtypep x-type s-float)
		(csubtypep y-type s-float))
	   `(sparc::%%min x y))
	  (t
	   (let ((arg1 (gensym))
		 (arg2 (gensym)))
	     `(let ((,arg1 x)
		    (,arg2 y))
		(if (< ,arg1 ,arg2)
		    ,arg1 ,arg2)))))))

)



(in-package "SPARC")


;;; Support for double-double floats

#+double-double
(progn
(defun double-double-reg-hi-tn (x)
  (make-random-tn :kind :normal :sc (sc-or-lose 'double-reg *backend*)
		  :offset (tn-offset x)))

(defun double-double-reg-lo-tn (x)
  ;; The low tn is 2 more than the offset because double regs are
  ;; even.
  (make-random-tn :kind :normal :sc (sc-or-lose 'double-reg *backend*)
		  :offset (+ 2 (tn-offset x))))

(define-move-function (load-double-double 4) (vop x y)
  ((double-double-stack) (double-double-reg))
  (let ((nfp (current-nfp-tn vop))
	(offset (* (tn-offset x) vm:word-bytes)))
    (let ((hi-tn (double-double-reg-hi-tn y)))
      (inst lddf hi-tn nfp offset))
    (let ((lo-tn (double-double-reg-lo-tn y)))
      (inst lddf lo-tn nfp (+ offset (* 2 vm:word-bytes))))))

(define-move-function (store-double-double 4) (vop x y)
  ((double-double-reg) (double-double-stack))
  (let ((nfp (current-nfp-tn vop))
	(offset (* (tn-offset y) vm:word-bytes)))
    (let ((hi-tn (double-double-reg-hi-tn x)))
      (inst stdf hi-tn nfp offset))
    (let ((lo-tn (double-double-reg-lo-tn x)))
      (inst stdf lo-tn nfp (+ offset (* 2 vm:word-bytes))))))

;;; Double-double float register to register moves

(define-vop (double-double-move)
  (:args (x :scs (double-double-reg)
	    :target y :load-if (not (location= x y))))
  (:results (y :scs (double-double-reg) :load-if (not (location= x y))))
  (:note _N"double-double float move")
  (:generator 0
     (unless (location= x y)
       ;; Note the double-float-regs are aligned to every second
       ;; float register so there is not need to worry about overlap.
       (let ((x-hi (double-double-reg-hi-tn x))
	     (y-hi (double-double-reg-hi-tn y)))
	 (move-double-reg y-hi x-hi))
       (let ((x-lo (double-double-reg-lo-tn x))
	     (y-lo (double-double-reg-lo-tn y)))
	 (move-double-reg y-lo x-lo)))))
;;;
(define-move-vop double-double-move :move
  (double-double-reg) (double-double-reg))

;;; Move from a complex float to a descriptor register allocating a
;;; new complex float object in the process.

(define-vop (move-from-double-double)
  (:args (x :scs (double-double-reg) :to :save))
  (:results (y :scs (descriptor-reg)))
  (:temporary (:scs (non-descriptor-reg)) ndescr)
  (:note _N"double-double float to pointer coercion")
  (:generator 13
     (with-fixed-allocation (y ndescr vm::double-double-float-type
			       vm::double-double-float-size))
     (let ((hi-tn (double-double-reg-hi-tn x)))
       (inst stdf hi-tn y (- (* vm::double-double-float-hi-slot
				  vm:word-bytes)
			       vm:other-pointer-type)))
     (let ((lo-tn (double-double-reg-lo-tn x)))
       (inst stdf lo-tn y (- (* vm::double-double-float-lo-slot
				  vm:word-bytes)
			       vm:other-pointer-type)))))
;;;
(define-move-vop move-from-double-double :move
  (double-double-reg) (descriptor-reg))

;;; Move from a descriptor to a double-double float register

(define-vop (move-to-double-double)
  (:args (x :scs (descriptor-reg)))
  (:results (y :scs (double-double-reg)))
  (:note _N"pointer to double-double float coercion")
  (:generator 2
    (let ((hi-tn (double-double-reg-hi-tn y)))
      (inst lddf hi-tn x (- (* double-double-float-hi-slot word-bytes)
			     other-pointer-type)))
    (let ((lo-tn (double-double-reg-lo-tn y)))
      (inst lddf lo-tn x (- (* double-double-float-lo-slot word-bytes)
			   other-pointer-type)))))

(define-move-vop move-to-double-double :move
  (descriptor-reg) (double-double-reg))

;;; double-double float move-argument vop

(define-vop (move-double-double-float-argument)
  (:args (x :scs (double-double-reg) :target y)
	 (nfp :scs (any-reg) :load-if (not (sc-is y double-double-reg))))
  (:results (y))
  (:note _N"double-double float argument move")
  (:generator 2
    (sc-case y
      (double-double-reg
       (unless (location= x y)
	 (let ((x-hi (double-double-reg-hi-tn x))
	       (y-hi (double-double-reg-hi-tn y)))
	   (move-double-reg y-hi x-hi))
	 (let ((x-lo (double-double-reg-lo-tn x))
	       (y-lo (double-double-reg-lo-tn y)))
	   (move-double-reg y-lo x-lo))))
      (double-double-stack
       (let ((offset (* (tn-offset y) word-bytes)))
	 (let ((hi-tn (double-double-reg-hi-tn x)))
	   (inst stdf hi-tn nfp offset))
	 (let ((lo-tn (double-double-reg-lo-tn x)))
	   (inst stdf lo-tn nfp (+ offset (* 2 word-bytes)))))))))

(define-move-vop move-double-double-float-argument :move-argument
  (double-double-reg descriptor-reg) (double-double-reg))


(define-vop (make/double-double-float)
  (:args (hi :scs (double-reg) :target res
	     :load-if (not (location= hi res)))
	 (lo :scs (double-reg) :to :save))
  (:results (res :scs (double-double-reg) :from (:argument 0)
		 :load-if (not (sc-is res double-double-stack))))
  (:arg-types double-float double-float)
  (:result-types double-double-float)
  (:translate kernel::%make-double-double-float)
  (:note _N"inline double-double float creation")
  (:policy :fast-safe)
  (:vop-var vop)
  (:generator 5
    (sc-case res
      (double-double-reg
       (let ((res-hi (double-double-reg-hi-tn res)))
	 (unless (location= res-hi hi)
	   (move-double-reg res-hi hi)))
       (let ((res-lo (double-double-reg-lo-tn res)))
	 (unless (location= res-lo lo)
	   (move-double-reg res-lo lo))))
      (double-double-stack
       (let ((nfp (current-nfp-tn vop))
	     (offset (* (tn-offset res) vm:word-bytes)))
	 (unless (location= hi res)
	   (inst stdf hi nfp offset))
	 (inst stdf lo nfp (+ offset (* 2 vm:word-bytes))))))))

(define-vop (double-double-float-value)
  (:args (x :scs (double-double-reg descriptor-reg) :target r
	    :load-if (not (sc-is x double-double-stack))))
  (:arg-types double-double-float)
  (:results (r :scs (double-reg)))
  (:result-types double-float)
  (:variant-vars slot)
  (:policy :fast-safe)
  (:vop-var vop)
  (:generator 3
    (sc-case x
      (double-double-reg
       (let ((value-tn (ecase slot
			 (:hi (double-double-reg-hi-tn x))
			 (:lo (double-double-reg-lo-tn x)))))
	 (unless (location= value-tn r)
	   (move-double-reg r value-tn))))
      (double-double-stack
       (inst lddf r (current-nfp-tn vop) (* (+ (ecase slot (:hi 0) (:lo 2))
					       (tn-offset x))
					    vm:word-bytes)))
      (descriptor-reg
       (inst lddf r x (- (* vm:word-bytes
			    (ecase slot
			      (:hi vm:double-double-float-hi-slot)
			      (:lo vm:double-double-float-lo-slot)))
			 vm:other-pointer-type))))))

(define-vop (hi/double-double-value double-double-float-value)
  (:translate kernel::double-double-hi)
  (:note _N"double-double high part")
  (:variant :hi))

(define-vop (lo/double-double-value double-double-float-value)
  (:translate kernel::double-double-lo)
  (:note _N"double-double low part")
  (:variant :lo))


(define-vop (make-complex-double-double-float)
  (:translate complex)
  (:args (real :scs (double-double-reg) :target r
	       :load-if (not (location= real r)))
	 (imag :scs (double-double-reg) :to :save))
  (:arg-types double-double-float double-double-float)
  (:results (r :scs (complex-double-double-reg) :from (:argument 0)
	       :load-if (not (sc-is r complex-double-double-stack))))
  (:result-types complex-double-double-float)
  (:note _N"inline complex double-double float creation")
  (:policy :fast-safe)
  (:vop-var vop)
  (:generator 5
    (sc-case r
      (complex-double-double-reg
       (let ((r-real (complex-double-double-reg-real-hi-tn r))
	     (real-hi (double-double-reg-hi-tn real)))
	 (move-double-reg r-real real-hi))
       (let ((r-real (complex-double-double-reg-real-lo-tn r))
	     (real-lo (double-double-reg-lo-tn real)))
	 (move-double-reg r-real real-lo))
       (let ((r-imag (complex-double-double-reg-imag-hi-tn r))
	     (imag-hi (double-double-reg-hi-tn imag)))
	 (move-double-reg r-imag imag-hi))
       (let ((r-imag (complex-double-double-reg-imag-lo-tn r))
	     (imag-lo (double-double-reg-lo-tn imag)))
	 (move-double-reg r-imag imag-lo)))
      (complex-double-double-stack
       (let ((nfp (current-nfp-tn vop))
	     (offset (* (tn-offset r) vm:word-bytes)))
	 (let ((r-real (double-double-reg-hi-tn real)))
	   (inst stdf r-real nfp offset))
	 (let ((r-real (double-double-reg-lo-tn real)))
	   (inst stdf r-real nfp (+ offset (* 2 vm:word-bytes))))
	 (let ((r-imag (double-double-reg-hi-tn imag)))
	   (inst stdf r-imag nfp (+ offset (* 4 vm:word-bytes))))
	 (let ((r-imag (double-double-reg-lo-tn imag)))
	   (inst stdf r-imag nfp (+ offset (* 6 vm:word-bytes)))))))))

(define-vop (complex-double-double-float-value)
  (:args (x :scs (complex-double-double-reg descriptor-reg)
	    :load-if (not (or (sc-is x complex-double-double-stack)))))
  (:arg-types complex-double-double-float)
  (:results (r :scs (double-double-reg)))
  (:result-types double-double-float)
  (:variant-vars slot)
  (:policy :fast-safe)
  (:vop-var vop)
  (:generator 3
    (sc-case x
      (complex-double-double-reg
       (let ((value-tn (ecase slot
			 (:real (complex-double-double-reg-real-hi-tn x))
			 (:imag (complex-double-double-reg-imag-hi-tn x))))
	     (r-hi (double-double-reg-hi-tn r)))
	 (unless (location= value-tn r-hi)
	   (move-double-reg r-hi value-tn)))
       (let ((value-tn (ecase slot
			 (:real (complex-double-double-reg-real-lo-tn x))
			 (:imag (complex-double-double-reg-imag-lo-tn x))))
	     (r-lo (double-double-reg-lo-tn r)))
	 (unless (location= value-tn r-lo)
	   (move-double-reg r-lo value-tn))))
      (complex-double-double-stack
       (let ((r-hi (double-double-reg-hi-tn r)))
	 (inst lddf r-hi (current-nfp-tn vop) (* (+ (ecase slot (:real 0) (:imag 4))
						    (tn-offset x))
						 vm:word-bytes)))
       (let ((r-lo (double-double-reg-lo-tn r)))
	 (inst lddf r-lo (current-nfp-tn vop) (* (+ (ecase slot (:real 2) (:imag 6))
						    (tn-offset x))
						 vm:word-bytes))))
      (descriptor-reg
       (let ((r-hi (double-double-reg-hi-tn r)))
	 (inst lddf r-hi x (- (* (ecase slot
				   (:real vm::complex-double-double-float-real-hi-slot)
				   (:imag vm::complex-double-double-float-imag-hi-slot))
				 vm:word-bytes)
			      vm:other-pointer-type))
       (let ((r-lo (double-double-reg-lo-tn r)))
	 (inst lddf r-lo x (- (* (ecase slot
				 (:real vm::complex-double-double-float-real-lo-slot)
				 (:imag vm::complex-double-double-float-imag-lo-slot))
			       vm:word-bytes)
			    vm:other-pointer-type))))))))

(define-vop (realpart/complex-double-double-float complex-double-double-float-value)
  (:translate realpart)
  (:note _N"complex double-double float realpart")
  (:variant :real))

(define-vop (imagpart/complex-double-double-float complex-double-double-float-value)
  (:translate imagpart)
  (:note _N"complex double-double float imagpart")
  (:variant :imag))

); progn

