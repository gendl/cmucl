;;; -*- Package: SPARC -*-
;;;
;;; **********************************************************************
;;; This code was written as part of the CMU Common Lisp project at
;;; Carnegie Mellon University, and has been placed in the public domain.
;;;
(ext:file-comment
  "$Header: src/assembly/sparc/alloc.lisp $")
;;;
;;; **********************************************************************
;;;
;;; Stuff to handle allocating simple objects.
;;;
;;; Written by William Lott.
;;;

(in-package "SPARC")

;;; But we do everything inline now that we have a better pseudo-atomic.
