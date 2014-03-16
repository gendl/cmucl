;;; Tests from trac tickets

(defpackage :trac-tests
  (:use :cl :lisp-unit))

(in-package "TRAC-TESTS")

(define-test trac.1
  (:tag :trac)
  (assert-false
   (let (failures)
     (dotimes (k 1000)
       (let ((x (random 1d-3)))
	 (let ((s (prin1-to-string x))
	       (f (format nil "~E" x)))
	 (unless (string-equal s f)
	   (push (list x s f)
		 failures)))))
     failures)))

(define-test trac.8
  (:tag :trac)
  (assert-false
   (let (failures)
     (dolist (base (list nil 2 2.0 2d0
			 (ash 1 99) (ash 1 3000)
			 8/7 (/ (ash 1 3000) 7)))
       (dolist (number (list 100 100.0 100d0
			     (ash 1 100) (ash 1 3500)
			     50/7 (/ (ash 1 3500) 7)))
	 (multiple-value-bind (result cond)
	     (ignore-errors (if base
				(log number base)
				(log number)))
	   (unless result
	     (push (list number base cond)
		   failures)))))
     failures)))

(define-test trac.10
  (:tag :trac)
  (assert-equal '(536870912 0.5d0)
		(multiple-value-list (round (+ 536870911 1.5d0)))))

(define-test trac.11
  (:tag :trac)
  (assert-true (eql 0w0 0w0)))

(define-test trac.12
  (:tag :trac)
  (assert-equal "   0.1D-05"
		 (format nil "~10,1,2,0,'*,,'DE" 1d-6)))

(define-test trac.13
  (:tag :trac)
  (assert-equal "  0.100E+01"
		(format nil "~11,3,2,0,'*,,'EE" .9999)))

;; See http://trac.common-lisp.net/cmucl/ticket/15.  We don't intend
;; to fix this with x87 due to the x87 extended double float (80-bit)
;; format.
#-x87
(define-test trac.15
  (:tag :trac)
  (assert-true
   (funcall (compile nil
		     (lambda (z tt betain beta)
		       (declare (double-float z tt betain beta)
				(optimize (speed 3) (safety 0)))
		       (= (* (* (* z tt) betain) beta) z)))
	    5.562684646268004d-309 (1+ double-float-epsilon) .5d0 2d0)))

(define-test trac.24
  (:tag :trac)
  (assert-true
   (let ((y (expt 2 #c(-0.5d0 0))))
     (and (zerop (imagpart y))
	  (<= (abs (- (realpart y)
		      (sqrt 0.5d0)))
	      (* 2 double-float-epsilon))))))

(define-test trac.25
  (:tag :trac)
  (assert-true
   (compile nil (lambda ()
		  (declare (optimize (speed 0) (safety 3) (debug 3)))
		  (loop
		    (pop *random-stack*)
		    (return)))))
  (assert-true
   (compile nil (lambda ()
		  (declare (optimize (safety 3)))
		  (catch (make-symbol "CMUCL-DEBUG-CATCH-TAG")
		    (make-string 49))))))

(define-test trac.29
  (:tag :trac)
  (assert-true
   (make-condition (find-class 'error))))

(define-test trac.31
  (:tag :trac)
  (assert-equal '(:absolute "TMP" "Foo"  "bar")
		(pathname-directory "/tmp/Foo/BAR/" :case :common)))
  
(define-test trac.36
  (:tag :trac)
  (let ((path "/tmp/trac.36.bom.txt"))
    (flet ((bug (&optional (format :utf16))
	     (with-open-file (s path
				:direction :output
				:if-exists :supersede
				:external-format format)
	       (format s "Hello~%"))
	     (with-open-file (s path 
				:direction :input
				:external-format format)
	       (let ((ch (read-char s)))
		 (values ch (file-position s))))))
      (assert-equal (values #\H 4)
		    (bug :utf16))
      (assert-equal (values #\H 8)
		    (bug :utf32)))))

(define-test trac.43
  (:tag :trac)
  (assert-true
   (let ((path "/tmp/trac.43.txt"))
     (unwind-protect
	  (progn
	    (with-open-file (ostream path :direction :output
					  :external-format :utf-8)
	      (dotimes (i 1000)
		(write-char (code-char #x1234) ostream)))

	    (with-open-file (stream path :direction :input
					 :external-format :utf-8)
	      (let ((p0 (file-position stream))
		    (ch (read-char stream)))
		(unread-char ch stream)
		(let ((p0* (file-position stream)))
		  (eql p0* p0)))))))))

(define-test trac.50
  (:tag :trac)
  (assert-equal "#P(:DIRECTORY (:ABSOLUTE \"tmp\" \"\" \"a\" \"\" \"b\"))"
		(princ-to-string (make-pathname :directory '(:absolute "tmp" "" "a" "" "b")))))

(define-test trac.58
  (:tag :trac)
  (assert-false
   (let ((path "/tmp/trac.58.txt")
	 failures)
     (unwind-protect
	  (progn
	    (with-open-file (s path :direction :output :external-format :utf-16)
	      (dotimes (i 300)
		(write-char (code-char i) s)))

	    (with-open-file (s path :direction :input :external-format :utf-16)
	      (dotimes (i 300)
		(let ((ch (read-char s nil nil)))
		  (unless (= i (char-code ch))
		    (push (list i ch (char-code ch)) failures)))))
	    failures)
       (delete-file path)))))

(define-test trac.63
  (:tag :trac)
  (assert-eql
   4.999995d11
   (funcall (compile nil
		     (lambda (x)
		       (declare (type (and fixnum unsigned-byte) x) 
				(optimize speed (safety 0)))
		       (vm::with-cycle-counter
			 (let ((sum 0d0))
			   (declare (double-float sum))
			   (dotimes (k x)
			     (declare (type (and fixnum unsigned-byte) k))
			     (incf sum k))
			   sum))))
	    1000000)))
		     
(define-test trac.65
  (:tag :trac)
  (dolist (base '(2 2f0 2d0 2w0 #c(0 1) #c(0f0 1) #c(0d0 1) #c(0w0 1)))
    (dolist (power '(2 3 1/2 -2 -3 -1/2 5))
      (dolist (power-type '(rational single-float double-float ext:double-double-float
			    (complex single-float) (complex double-float)
			    (complex ext:double-double-float)))
	(let* ((pp (coerce power power-type))
	       (interp (expt base pp))
	       (*compile-print* nil)
	       (compiled (funcall (compile nil `(lambda (b)
						  (declare (type ,(type-of base) b))
						  (expt b ,pp)))
				  base)))
	  (assert-eql interp compiled base pp))))))

(define-test trac.67
  (:tag :trac)
  (assert-error 'simple-error
		(funcall (compile nil
				  (lambda (s)
				    (declare (simple-string s))
				    (replace s s :start2 100 :end2 105)))
			 (copy-seq "1234567890"))))

(setf (logical-pathname-translations "trac69")
      '(("**;*.*.*" "/tmp/**/*.*")))

(define-test trac.69
  (:tag :trac)
  (assert-error 'lisp::namestring-parse-error
		(let ((*default-pathname-defaults* #p"trac69:"))
		  (pathname "/tmp/bar.lisp"))))

(defparameter *trac.70* (make-string 40 :initial-element #\A))

(compile 'trac.70-test
	 (lambda (workspace s)
	   (declare (simple-string workspace s))
	   (replace workspace s :start1 1 :end1 5 :start2 1 :end2 5)))

(define-test trac.71
  (:tag :trac)
  (assert-true
   (funcall (compile nil
		     (lambda (x)
		       (declare (double-float x))
		       (expt x 2w0)))
	    2d0)))

(defpackage :cl-haml
  (:use :cl))

(defparameter *path* cl:*load-pathname*)

(define-test trac.74
  (:tag :trac)
  (assert-true
   (let ((path (merge-pathnames "resources/read-insert.lisp"
				*path*)))
     (compile-file path :external-format :utf8))))

(define-test trac.76
  (:tag :trac)
  (assert-equal "A1234AAAA"
		(subseq (trac.70-test *trac.70* "a12345") 0 9)))

(define-test trac.79
  (:tag :trac)
  ;; Create a temp file full of latin1 characters.
  (assert-equal
   '(0 1)
   (let ((path "/tmp/trac.70.txt"))
     (unwind-protect
	  (progn
	    (with-open-file (s path :direction :output :if-exists :supersede
				    :external-format :latin1)
	      (dotimes (k 255)
		(write-char (code-char k) s)))
	    (with-open-file (s path :direction :input :external-format :latin1)
	      (list (file-position s)
		    (progn
		      (read-char s)
		      (file-position s)))))
       (delete-file path)))))

(define-test trac.80
  (:tag :trac)
  ;; The following formats should not signal an error.
  (assert-true (ignore-errors (format nil "~ve" 21 5d-234)))
  (assert-true (ignore-errors (format nil "~ve" 100 5d-234))))

(define-test trac.87.output
  (:tag :trac)
  ;; Test that run-program accepts :element-type and produces the
  ;; correct output.
  (let ((path "/tmp/trac.87.output")
	(string "Hello"))
    (unwind-protect
	 (progn
	   (with-open-file (s path :direction :output :if-exists :supersede
			      :external-format :latin1)
	     (write-string string s))
	   (let* ((expected (stream:string-to-octets string :external-format :latin1))
		  (octets (make-array (length expected)
				      :element-type '(unsigned-byte 8)))
		  (proc (ext:run-program "/bin/cat" (list path)
					 :output :stream
					 :element-type '(unsigned-byte 8))))
	     (read-sequence octets (ext:process-output proc))
	     (assert-equalp
	      expected
	      octets)))
      (delete-file path))))

(define-test trac.87.input
  (:tag :trac)
  ;; Test that run-program accepts :element-type and produces the
  ;; correct input (and output).
  (let ((path "/tmp/trac.87.input")
	(string "Hello"))
    (unwind-protect
	 (progn
	   (with-open-file (s path :direction :output :if-exists :supersede
			      :external-format :latin1)
	     (write-string string s))
	   (let ((octets (stream:string-to-octets string :external-format :latin1))
		 (output (make-array (length string)
				     :element-type '(unsigned-byte 8)))
		 (proc (ext:run-program "/bin/cat" (list path)
					:input :stream
					:output :stream
					:element-type '(unsigned-byte 8))))
	     (write-sequence octets (ext:process-input proc))
	     (read-sequence output (ext:process-output proc))
	     (assert-equalp
	      octets
	      output)))
      (delete-file path))))
      
(define-test trac.92
  (:tag :trac)
  (let ((f (compile nil
		    #'(lambda (x)
			(declare (type (double-float 0d0) x))
			(log x)))))
    (assert-equal
     'double-float
     (third (kernel:%function-type f)))))

(define-test trac.93
  (:tag :trac)
  ;; These small values should read to least-positive-foo-float
  ;; because that's the closest non-zero float.
  (assert-eql least-positive-short-float
	      (values (read-from-string ".8s-45")))
  (assert-eql least-positive-single-float
	      (values (read-from-string ".8e-45")))
  (assert-eql least-positive-double-float
	      (values (read-from-string "4d-324")))
  (assert-eql (kernel:make-double-double-float least-positive-double-float 0d0)
	      (values (read-from-string "4w-324")))
  ;; These should signal reader errors because the numbers are not
  ;; zero, but are too small to be represented by the corresponding
  ;; float type.
  (assert-error 'reader-error (read-from-string ".1s-45"))
  (assert-error 'reader-error (read-from-string ".1e-45"))
  (assert-error 'reader-error (read-from-string "1d-324"))
  (assert-error 'reader-error (read-from-string "1w-324")))
  