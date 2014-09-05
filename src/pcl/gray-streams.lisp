;;;
;;; **********************************************************************
;;; This code was written by Douglas T. Crosher and has been placed in
;;; the Public domain, and is provided 'as is'.
;;;

(file-comment
  "$Header: src/pcl/gray-streams.lisp $")
;;;
;;; **********************************************************************
;;;
;;; Gray streams implementation for CMUCL.
;;; Based on the stream-definition-by-user proposal by David N. Gray.
;;;

(in-package "LISP")
(intl:textdomain "cmucl")



(fmakunbound 'stream-element-type)

(defgeneric stream-element-type (stream)
  (:documentation
   _N"Returns a type specifier for the kind of object returned by the
  Stream. Class FUNDAMENTAL-CHARACTER-STREAM provides a default method
  which returns CHARACTER."))

(defmethod stream-element-type ((stream lisp-stream))
  (funcall (lisp-stream-misc stream) stream :element-type))

(defmethod stream-element-type ((stream fundamental-character-stream))
  'character)

(when (find-class 'stream:simple-stream nil)
  (defmethod stream-element-type ((stream stream:simple-stream))
    '(unsigned-byte 8)))



(defgeneric pcl-open-stream-p (stream)
  (:documentation
   _N"Return true if Stream is not closed.  A default method is provided
  by class FUNDAMENTAL-STREAM which returns true if CLOSE has not been
  called on the stream."))

(defmethod pcl-open-stream-p ((stream lisp-stream))
  (not (eq (lisp-stream-in stream) #'closed-flame)))

(defmethod pcl-open-stream-p ((stream fundamental-stream))
  nil)

(when (find-class 'stream:simple-stream nil)
  (defmethod pcl-open-stream-p ((stream stream:simple-stream))
    (stream::%open-stream-p stream)))

;;; Bootstrapping hack.
(pcl-open-stream-p (make-string-output-stream))
(setf (fdefinition 'open-stream-p) #'pcl-open-stream-p)



(defgeneric pcl-close (stream &key abort)
  (:documentation
   _N"Closes the given Stream.  No more I/O may be performed, but
  inquiries may still be made.  If :Abort is non-nil, an attempt is made
  to clean up the side effects of having created the stream."))

(defmethod pcl-close ((stream lisp-stream) &key abort)
  (when (open-stream-p stream)
    (funcall (lisp-stream-misc stream) stream :close abort))
  t)

(when (find-class 'stream:simple-stream nil)
  (defmethod pcl-close ((stream stream:simple-stream) &key abort)
    (stream:device-close stream abort)))

(pcl-close (make-string-output-stream))
(setf (fdefinition 'close) #'pcl-close)



(fmakunbound 'input-stream-p)

(defgeneric input-stream-p (stream)
  (:documentation _N"Returns non-nil if the given Stream can perform input operations."))

(defmethod input-stream-p ((stream lisp-stream))
  (and (not (eq (lisp-stream-in stream) #'closed-flame))
       (or (not (eq (lisp-stream-in stream) #'ill-in))
	   (not (eq (lisp-stream-bin stream) #'ill-bin))
	   (not (eq (lisp-stream-n-bin stream) #'ill-n-bin)))))

(defmethod input-stream-p ((stream fundamental-input-stream))
  t)

(when (find-class 'stream:simple-stream nil)
  (defmethod input-stream-p ((stream stream:simple-stream))
    (stream::%input-stream-p stream)))



(fmakunbound 'output-stream-p)

(defgeneric output-stream-p (stream)
  (:documentation _N"Returns non-nil if the given Stream can perform output operations."))

(defmethod output-stream-p ((stream lisp-stream))
  (and (not (eq (lisp-stream-in stream) #'closed-flame))
       (or (not (eq (lisp-stream-out stream) #'ill-out))
	   (not (eq (lisp-stream-bout stream) #'ill-bout)))))

(defmethod output-stream-p ((stream fundamental-output-stream))
  t)

(when (find-class 'stream:simple-stream nil)
  (defmethod output-stream-p ((stream stream:simple-stream))
    (stream::%output-stream-p stream)))


;;; Character input streams.
;;;
;;; A character input stream can be created by defining a class that
;;; includes FUNDAMENTAL-CHARACTER-INPUT-STREAM and defining methods
;;; for the generic functions below.

(defgeneric stream-read-char (stream)
  (:documentation
   _N"This reads one character from the stream.  It returns either a
  character object, or the symbol :EOF if the stream is at end-of-file.
  Every subclass of FUNDAMENTAL-CHARACTER-INPUT-STREAM must define a
  method for this function."))

(defgeneric stream-unread-char (stream character)
  (:documentation
   _N"Un-does the last call to STREAM-READ-CHAR, as in UNREAD-CHAR.
  Returns NIL.  Every subclass of FUNDAMENTAL-CHARACTER-INPUT-STREAM
  must define a method for this function."))

(defgeneric stream-read-char-no-hang (stream)
  (:documentation
   _N"This is used to implement READ-CHAR-NO-HANG.  It returns either a
  character, or NIL if no input is currently available, or :EOF if
  end-of-file is reached.  The default method provided by
  FUNDAMENTAL-CHARACTER-INPUT-STREAM simply calls STREAM-READ-CHAR; this
  is sufficient for file streams, but interactive streams should define
  their own method."))

(defmethod stream-read-char-no-hang ((stream fundamental-character-input-stream))
  (stream-read-char stream))

(defgeneric stream-peek-char (stream)
  (:documentation
   _N"Used to implement PEEK-CHAR; this corresponds to peek-type of NIL.
  It returns either a character or :EOF.  The default method calls
  STREAM-READ-CHAR and STREAM-UNREAD-CHAR."))

(defmethod stream-peek-char ((stream fundamental-character-input-stream))
  (let ((char (stream-read-char stream)))
    (unless (eq char :eof)
      (stream-unread-char stream char))
    char))

(defgeneric stream-listen (stream)
  (:documentation
   _N"Used by LISTEN.  Returns true or false.  The default method uses
  STREAM-READ-CHAR-NO-HANG and STREAM-UNREAD-CHAR.  Most streams should 
  define their own method since it will usually be trivial and will
  always be more efficient than the default method."))

(defmethod stream-listen ((stream fundamental-character-input-stream))
  (let ((char (stream-read-char-no-hang stream)))
    (when (characterp char)
      (stream-unread-char stream char)
      t)))

(defgeneric stream-read-line (stream)
  (:documentation
   _N"Used by READ-LINE.  A string is returned as the first value.  The
  second value is true if the string was terminated by end-of-file
  instead of the end of a line.  The default method uses repeated
  calls to STREAM-READ-CHAR."))

(defmethod stream-read-line ((stream fundamental-character-input-stream))
  (let ((res (make-string 80))
	(len 80)
	(index 0))
    (loop
     (let ((ch (stream-read-char stream)))
       (cond ((eq ch :eof)
	      (return (values (shrink-vector res index) t)))
	     (t
	      (when (char= ch #\newline)
		(return (values (shrink-vector res index) nil)))
	      (when (= index len)
		(setq len (* len 2))
		(let ((new (make-string len)))
		  (replace new res)
		  (setq res new)))
	      (setf (schar res index) ch)
	      (incf index)))))))

(defgeneric stream-clear-input (stream)
  (:documentation
   _N"Implements CLEAR-INPUT for the stream, returning NIL.  The default
  method does nothing."))

(defmethod stream-clear-input ((stream fundamental-character-input-stream))
  nil)

(defgeneric stream-read-sequence (stream seq &optional start end)
  (:documentation
   _N"Implements READ-SEQUENCE for the stream."))


;;; Character output streams.
;;;
;;; A character output stream can be created by defining a class that
;;; includes FUNDAMENTAL-CHARACTER-OUTPUT-STREAM and defining methods
;;; for the generic functions below.

(defgeneric stream-write-char (stream character)
  (:documentation
   _N"Writes character to the stream and returns the character.  Every
  subclass of FUNDAMENTAL-CHARACTER-OUTPUT-STREAM must have a method
  defined for this function."))

(defgeneric stream-line-column (stream)
  (:documentation
   _N"This function returns the column number where the next character
  will be written, or NIL if that is not meaningful for this stream.
  The first column on a line is numbered 0.  This function is used in
  the implementation of PPRINT and the FORMAT ~T directive.  For every
  character output stream class that is defined, a method must be
  defined for this function, although it is permissible for it to
  always return NIL."))

;;; Stream-line-length is a CMUCL extension to Gray streams.
(defgeneric stream-line-length (stream)
  (:documentation _N"Return the stream line length or Nil."))

(defmethod stream-line-length ((stream fundamental-character-output-stream))
  nil)

(defgeneric stream-start-line-p (stream)
  (:documentation
   _N"This is a predicate which returns T if the stream is positioned at
  the beginning of a line, else NIL.  It is permissible to always return
  NIL.  This is used in the implementation of FRESH-LINE.  Note that
  while a value of 0 from STREAM-LINE-COLUMN also indicates the
  beginning of a line, there are cases where STREAM-START-LINE-P can be
  meaningfully implemented although STREAM-LINE-COLUMN can't be.  For
  example, for a window using variable-width characters, the column
  number isn't very meaningful, but the beginning of the line does have
  a clear meaning.  The default method for STREAM-START-LINE-P on class
  FUNDAMENTAL-CHARACTER-OUTPUT-STREAM uses STREAM-LINE-COLUMN, so if
  that is defined to return NIL, then a method should be provided for
  either STREAM-START-LINE-P or STREAM-FRESH-LINE."))

(defmethod stream-start-line-p ((stream fundamental-character-output-stream))
  (eql (stream-line-column stream) 0))

(defgeneric stream-write-string (stream string &optional start end)
  (:documentation
   _N"This is used by WRITE-STRING.  It writes the string to the stream,
  optionally delimited by start and end, which default to 0 and NIL.
  The string argument is returned.  The default method provided by
  FUNDAMENTAL-CHARACTER-OUTPUT-STREAM uses repeated calls to
  STREAM-WRITE-CHAR."))

(defmethod stream-write-string ((stream fundamental-character-output-stream)
				string &optional (start 0) end)
  (declare (string string)
	   (fixnum start))
  (let ((end (or end (length string))))
    (declare (fixnum end))
    (do ((pos start (1+ pos)))
	((>= pos end))
      (declare (type index pos))
      (stream-write-char stream (aref string pos))))
  string)

(defgeneric stream-terpri (stream)
  (:documentation
   _N"Writes an end of line, as for TERPRI.  Returns NIL.  The default
  method does (STREAM-WRITE-CHAR stream #\NEWLINE)."))

(defmethod stream-terpri ((stream fundamental-character-output-stream))
  (stream-write-char stream #\Newline))

(defgeneric stream-fresh-line (stream)
  (:documentation
   _N"Outputs a new line to the Stream if it is not positioned at the
  begining of a line.  Returns T if it output a new line, nil
  otherwise. Used by FRESH-LINE. The default method uses
  STREAM-START-LINE-P and STREAM-TERPRI."))

(defmethod stream-fresh-line ((stream fundamental-character-output-stream))
  (unless (stream-start-line-p stream)
    (stream-terpri stream)
    t))

(defgeneric stream-finish-output (stream)
  (:documentation
   _N"Attempts to ensure that all output sent to the Stream has reached
  its destination, and only then returns false. Implements
  FINISH-OUTPUT.  The default method does nothing."))

(defmethod stream-finish-output ((stream fundamental-output-stream))
  nil)

(defgeneric stream-force-output (stream)
  (:documentation
   _N"Attempts to force any buffered output to be sent. Implements
  FORCE-OUTPUT.  The default method does nothing."))

(defmethod stream-force-output ((stream fundamental-output-stream))
  nil)

(defgeneric stream-clear-output (stream)
  (:documentation
   _N"Clears the given output Stream. Implements CLEAR-OUTPUT.  The
  default method does nothing."))

(defmethod stream-clear-output ((stream fundamental-output-stream))
  nil)

(defgeneric stream-advance-to-column (stream column)
  (:documentation
   _N"Writes enough blank space so that the next character will be
  written at the specified column.  Returns true if the operation is
  successful, or NIL if it is not supported for this stream.  This is
  intended for use by by PPRINT and FORMAT ~T.  The default method uses
  STREAM-LINE-COLUMN and repeated calls to STREAM-WRITE-CHAR with a
  #\SPACE character; it returns NIL if STREAM-LINE-COLUMN returns NIL."))

(defmethod stream-advance-to-column ((stream fundamental-character-output-stream)
				     column)
  (let ((current-column (stream-line-column stream)))
    (when current-column
      (let ((fill (- column current-column)))
	(dotimes (i fill)
	  (stream-write-char stream #\Space)))
      T)))

(defgeneric stream-write-sequence (stream seq &optional start end)
  (:documentation
   _N"Implements WRITE-SEQUENCE for the stream."))

(defgeneric stream-file-position (stream)
  (:documentation
   _N"Implements FILE-POSITION for the stream."))

(defmethod stream-file-position ((stream fundamental-stream))
  nil)

(defmethod stream-file-position ((stream character-input-stream))
  (file-position (character-input-stream-lisp-stream stream)))

(defmethod stream-file-position ((stream character-output-stream))
  (file-position (character-output-stream-lisp-stream stream)))

(defgeneric (setf stream-file-position) (position stream)
  (:documentation
   _N"Implements FILE-POSITION for the stream for setting the position."))

(defmethod (setf stream-file-position) (position (stream fundamental-stream))
  nil)

(defmethod (setf stream-file-position) (position (stream character-input-stream))
  (file-position (character-input-stream-lisp-stream stream) position))

(defmethod (setf stream-file-position) (position (stream character-output-stream))
  (file-position (character-output-stream-lisp-stream stream) position))


;;; Binary streams.
;;;
;;; Binary streams can be created by defining a class that includes
;;; either FUNDAMENTAL-BINARY-INPUT-STREAM or
;;; FUNDAMENTAL-BINARY-OUTPUT-STREAM (or both) and defining a method
;;; for STREAM-ELEMENT-TYPE and for one or both of the following
;;; generic functions.

(defgeneric stream-read-byte (stream)
  (:documentation
   _N"Used by READ-BYTE; returns either an integer, or the symbol :EOF
  if the stream is at end-of-file."))

(defgeneric stream-write-byte (stream integer)
  (:documentation
   _N"Implements WRITE-BYTE; writes the integer to the stream and
  returns the integer as the result."))


;;; Example character output stream encapsulating a lisp-stream.
(defun make-character-output-stream (lisp-stream)
  (declare (type lisp-stream lisp-stream))
  (make-instance 'character-output-stream :lisp-stream lisp-stream))

(defmethod open-stream-p ((stream character-output-stream))
  (open-stream-p (character-output-stream-lisp-stream stream)))

(defmethod close ((stream character-output-stream) &key abort)
  (close (character-output-stream-lisp-stream stream) :abort abort))

(defmethod input-stream-p ((stream character-output-stream))
  (input-stream-p (character-output-stream-lisp-stream stream)))

(defmethod output-stream-p ((stream character-output-stream))
  (output-stream-p (character-output-stream-lisp-stream stream)))

(defmethod stream-write-char ((stream character-output-stream) character)
  (write-char character (character-output-stream-lisp-stream stream)))

(defmethod stream-line-column ((stream character-output-stream))
  (charpos (character-output-stream-lisp-stream stream)))

(defmethod stream-line-length ((stream character-output-stream))
  (line-length (character-output-stream-lisp-stream stream)))

(defmethod stream-finish-output ((stream character-output-stream))
  (finish-output (character-output-stream-lisp-stream stream)))

(defmethod stream-force-output ((stream character-output-stream))
  (force-output (character-output-stream-lisp-stream stream)))

(defmethod stream-clear-output ((stream character-output-stream))
  (clear-output (character-output-stream-lisp-stream stream)))


;;; Example character input stream encapsulating a lisp-stream.

(defun make-character-input-stream (lisp-stream)
  (declare (type lisp-stream lisp-stream))
  (make-instance 'character-input-stream :lisp-stream lisp-stream))

(defmethod open-stream-p ((stream character-input-stream))
  (open-stream-p (character-input-stream-lisp-stream stream)))

(defmethod close ((stream character-input-stream) &key abort)
  (close (character-input-stream-lisp-stream stream) :abort abort))

(defmethod input-stream-p ((stream character-input-stream))
  (input-stream-p (character-input-stream-lisp-stream stream)))

(defmethod output-stream-p ((stream character-input-stream))
  (output-stream-p (character-input-stream-lisp-stream stream)))

(defmethod stream-read-char ((stream character-input-stream))
  (read-char (character-input-stream-lisp-stream stream)))

(defmethod stream-unread-char ((stream character-input-stream) character)
  (unread-char character (character-input-stream-lisp-stream stream)))

(defmethod stream-read-char-no-hang ((stream character-input-stream))
  (read-char-no-hang (character-input-stream-lisp-stream stream) nil :eof))

#+(or)
(defmethod stream-peek-char ((stream character-input-stream))
  (peek-char nil (character-input-stream-lisp-stream stream) nil :eof))

#+(or)
(defmethod stream-listen ((stream character-input-stream))
  (listen (character-input-stream-lisp-stream stream)))

(defmethod stream-clear-input ((stream character-input-stream))
  (clear-input (character-input-stream-lisp-stream stream)))

;; Announce ourselves to the world
(pushnew :gray-streams *features*)
(provide :gray-streams)

(setf (getf *herald-items* :gray-streams)
      `(,#'(lambda (stream)
	     (write-string _"    Gray Streams Protocol Support" stream))))



