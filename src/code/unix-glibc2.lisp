;;; -*- Package: UNIX -*-
;;;
;;; **********************************************************************
;;; This code was written as part of the CMU Common Lisp project at
;;; Carnegie Mellon University, and has been placed in the public domain.
;;;
(ext:file-comment
  "$Header: src/code/unix-glibc2.lisp $")
;;;
;;; **********************************************************************
;;;
;;; This file contains the UNIX low-level support for glibc2.  Based
;;; on unix.lisp 1.56, converted for glibc2 by Peter Van Eynde (1998).
;;; Alpha support by Julian Dolby, 1999.
;;;
;;; All the functions with #+(or) in front are work in progress,
;;; and mostly don't work.
;;;
;; Todo: #+(or)'ed stuff and ioctl's
;;
;;
;; Large File Support (LFS) added by Pierre Mai and Eric Marsden, Feb
;; 2003. This is necessary to be able to read/write/stat files that
;; are larger than 2GB on a 32-bit system. From a C program, defining
;; a preprocessor macro _LARGEFILE64_SOURCE makes the preproccessor
;; replace a call to open() by open64(), and similarly for stat,
;; fstat, lstat, lseek, readdir and friends. Furthermore, certain data
;; types, that are normally 32 bits wide, are replaced by 64-bit wide
;; equivalents: off_t -> off64_t etc. The libc.so fiddles around with
;; weak symbols to support this mess.
;;
;; From CMUCL, we make FFI calls to the xxx64 functions, and use the
;; 64-bit wide versions of the data structures. The most ugly aspect
;; is that some of the stat functions are not available via dlsym, so
;; we reference them explicitly from linux-stubs.S. Another amusing
;; fact is that on glibc 2.2, stat64() returns a struct stat with a
;; 32-bit ino_t, whereas readdir64() returns a struct dirent that
;; contains a 64-bit ino_t.  On glibc 2.1, OTOH, both stat64 and
;; readdir64 use structs with 32-bit ino_t.
;;
;; The current version deals with this by going with the glibc 2.2
;; definitions, unless the keyword :glibc2.1 also occurs on *features*,
;; in addition to :glibc2, in which case we go with the glibc 2.1
;; definitions.  Note that binaries compiled against glibc 2.1 do in
;; fact work fine on glibc 2.2, because readdir64 is available in both
;; glibc 2.1 and glibc 2.2 versions in glibc 2.2, disambiguated through
;; ELF symbol versioning.  We use an entry for readdir64 in linux-stubs.S
;; in order to force usage of the correct version of readdir64 at runtime.
;;
;; So in order to compile for glibc 2.2 and newer, just compile CMUCL
;; on a glibc 2.2 system, and make sure that :glibc2.1 doesn't appear
;; on the *features* list.  In order to compile for glibc 2.1 and newer,
;; compile CMUCL on a glibc 2.1 system, and make sure that :glibc2.1 does
;; appear on the *features* list.

(in-package "UNIX")
(use-package "ALIEN")
(use-package "C-CALL")
(use-package "SYSTEM")
(use-package "EXT")
(intl:textdomain "cmucl-unix-glibc2")

;; Check the G_BROKEN_FILENAMES environment variable; if set the encoding
;; is locale-dependent...else use :utf-8 on Unicode Lisps.  On 8 bit Lisps
;; it must be set to :iso8859-1 (or left as NIL), making files with
;; non-Latin-1 characters "mojibake", but otherwise they'll be inaccessible.
;; Must be set to NIL initially to enable building Lisp!
(defvar *filename-encoding* nil)

(export '(
	  daddr-t caddr-t ino-t swblk-t size-t time-t dev-t off-t uid-t gid-t
          blkcnt-t fsblkcnt-t fsfilcnt-t
	  unix-lockf f_ulock f_lock f_tlock f_test
	  timeval tv-sec tv-usec timezone tz-minuteswest tz-dsttime
	  itimerval it-interval it-value tchars t-intrc t-quitc t-startc
	  t-stopc t-eofc t-brkc ltchars t-suspc t-dsuspc t-rprntc t-flushc
	  t-werasc t-lnextc sgttyb sg-ispeed sg-ospeed sg-erase sg-kill
	  sg-flags winsize ws-row ws-col ws-xpixel ws-ypixel
	  direct d-off d-ino d-reclen  d-name
	  stat st-dev st-mode st-nlink st-uid st-gid st-rdev st-size
	  st-atime st-mtime st-ctime st-blksize st-blocks
	  s-ifmt s-ifdir s-ifchr s-ifblk s-ifreg s-iflnk s-ifsock
	  s-isuid s-isgid s-isvtx s-iread s-iwrite s-iexec
	  ruseage ru-utime ru-stime ru-maxrss ru-ixrss ru-idrss
	  ru-isrss ru-minflt ru-majflt ru-nswap ru-inblock ru-oublock
	  ru-msgsnd ru-msgrcv ru-nsignals ru-nvcsw ru-nivcsw
	  rlimit rlim-cur rlim-max sc-onstack sc-mask sc-pc
	  unix-errno get-unix-error-msg
	  prot_read prot_write prot_exec prot_none
	  map_shared map_private map_fixed map_anonymous
	  ms_async ms_sync ms_invalidate
	  unix-mmap unix-munmap unix-msync unix-mprotect
	  unix-pathname unix-file-mode unix-fd unix-pid unix-uid unix-gid
	  unix-setitimer unix-getitimer
	  unix-access r_ok w_ok x_ok f_ok unix-chdir unix-chmod setuidexec
	  setgidexec savetext readown writeown execown readgrp writegrp
	  execgrp readoth writeoth execoth unix-fchmod unix-chown unix-fchown
	  unix-getdtablesize unix-close unix-creat unix-dup unix-dup2
	  unix-fcntl f-dupfd f-getfd f-setfd f-getfl f-setfl f-getown f-setown
	  fndelay fappend fasync fcreat ftrunc fexcl unix-link unix-lseek
	  l_set l_incr l_xtnd unix-mkdir unix-open o_rdonly o_wronly o_rdwr
	  o_ndelay
	  o_noctty
	  o_append o_creat o_trunc o_excl unix-pipe unix-read unix-readlink
	  unix-rename unix-rmdir unix-fast-select fd-setsize fd-set fd-clr
	  fd-isset fd-zero unix-select unix-sync unix-fsync unix-truncate
	  unix-ftruncate unix-symlink unix-unlink unix-write unix-ioctl
	  unix-uname utsname
	  tcsetpgrp tcgetpgrp tty-process-group
	  terminal-speeds tty-raw tty-crmod tty-echo tty-lcase
	  tty-cbreak
	   termios
           c-lflag
	   c-iflag
           c-oflag
	   tty-icrnl
           tty-ocrnl
	   veof
	   vintr
           vquit
           vstart
	   vstop
           vsusp
	   c-cflag
	   c-cc
           tty-icanon
	   vmin
           vtime
	   tty-ixon
           tcsanow
           tcsadrain
           tciflush
           tcoflush
           tcioflush
	   tcsaflush
           unix-tcgetattr
           unix-tcsetattr
           tty-ignbrk
           tty-brkint
           tty-ignpar
           tty-parmrk
           tty-inpck
           tty-istrip
           tty-inlcr
           tty-igncr
           tty-iuclc
           tty-ixany
           tty-ixoff
	  tty-imaxbel
           tty-opost
           tty-olcuc
           tty-onlcr
           tty-onocr
           tty-onlret
           tty-ofill
           tty-ofdel
           tty-isig
           tty-xcase
           tty-echoe
           tty-echok
           tty-echonl
           tty-noflsh
           tty-iexten
           tty-tostop
           tty-echoctl
           tty-echoprt
           tty-echoke
           tty-pendin
           tty-cstopb
           tty-cread
           tty-parenb
           tty-parodd
           tty-hupcl
           tty-clocal
           vintr
           verase
           vkill
           veol
           veol2
	  TIOCGETP TIOCSETP TIOCFLUSH TIOCSETC TIOCGETC TIOCSLTC
	  TIOCGLTC TIOCNOTTY TIOCSPGRP TIOCGPGRP TIOCGWINSZ TIOCSWINSZ
	  TIOCSIGSEND

	  KBDCGET KBDCSET KBDCRESET KBDCRST KBDCSSTD KBDSGET KBDGCLICK
	  KBDSCLICK FIONREAD	  unix-exit unix-stat unix-lstat unix-fstat
	  unix-getrusage unix-fast-getrusage rusage_self rusage_children
	  unix-gettimeofday
	  unix-utimes unix-sched-yield unix-setreuid
	  unix-setregid
	  unix-getpid unix-getppid
	  unix-getgid unix-getegid unix-getpgrp unix-setpgrp unix-getuid
	  unix-getpagesize unix-gethostname unix-gethostid unix-fork
	  unix-getenv unix-setenv unix-putenv unix-unsetenv
	  unix-current-directory unix-isatty unix-ttyname unix-execve
	  unix-socket unix-connect unix-bind unix-listen unix-accept
	  unix-recv unix-send unix-getpeername unix-getsockname
	  unix-getsockopt unix-setsockopt unix-openpty

	  unix-recvfrom unix-sendto unix-shutdown

          unix-getpwnam unix-getpwuid unix-getgrnam unix-getgrgid
          user-info user-info-name user-info-password user-info-uid
          user-info-gid user-info-gecos user-info-dir user-info-shell
          group-info group-info-name group-info-gid group-info-members))

(pushnew :unix *features*)
(pushnew :glibc2 *features*)

;; needed for bootstrap
(eval-when (:compile-toplevel)
  (defmacro %name->file (string)
    `(if *filename-encoding*
	 (string-encode ,string *filename-encoding*)
	 ,string))
  (defmacro %file->name (string)
    `(if *filename-encoding*
	 (string-decode ,string *filename-encoding*)
	 ,string)))

;;;; Common machine independent structures.

(eval-when (compile eval)

(defparameter *compiler-unix-errors* nil)

(defmacro def-unix-error (name number description)
  `(progn
     (eval-when (compile eval)
       (push (cons ,number ,description) *compiler-unix-errors*))
     (defconstant ,name ,number ,description)
     (export ',name)))

(defmacro emit-unix-errors ()
  (let* ((max (apply #'max (mapcar #'car *compiler-unix-errors*)))
	 (array (make-array (1+ max) :initial-element nil)))
    (dolist (error *compiler-unix-errors*)
      (setf (svref array (car error)) (cdr error)))
    `(progn
       (defvar *unix-errors* ',array)
       (declaim (simple-vector *unix-errors*)))))

)

(defmacro def-enum (inc cur &rest names)
  (flet ((defform (name)
	     (prog1 (when name `(defconstant ,name ,cur))
	       (setf cur (funcall inc cur 1)))))
    `(progn ,@(mapcar #'defform names))))

;;;; Memory-mapped files

(defconstant +null+ (sys:int-sap 0))

(defconstant prot_read 1)
(defconstant prot_write 2)
(defconstant prot_exec 4)
(defconstant prot_none 0)

(defconstant map_shared 1)
(defconstant map_private 2)
(defconstant map_fixed 16)
(defconstant map_anonymous 32)

(defconstant ms_async 1)
(defconstant ms_sync 4)
(defconstant ms_invalidate 2)

;; The return value from mmap that means mmap failed.
(defconstant map_failed (int-sap (1- (ash 1 vm:word-bits))))

(defun unix-mmap (addr length prot flags fd offset)
  (declare (type (or null system-area-pointer) addr)
	   (type (unsigned-byte 32) length)
           (type (integer 1 7) prot)
	   (type (unsigned-byte 32) flags)
	   (type (or null unix-fd) fd)
	   (type (signed-byte 32) offset))
  ;; Can't use syscall, because the address that is returned could be
  ;; "negative".  Hence we explicitly check for mmap returning
  ;; MAP_FAILED.
  (let ((result
	 (alien-funcall (extern-alien "mmap" (function system-area-pointer
						       system-area-pointer
						       size-t int int int off-t))
			(or addr +null+) length prot flags (or fd -1) offset)))
    (if (sap= result map_failed)
	(values nil (unix-errno))
	(values result 0))))

(defun unix-munmap (addr length)
  (declare (type system-area-pointer addr)
	   (type (unsigned-byte 32) length))
  (syscall ("munmap" system-area-pointer size-t) t addr length))

(defun unix-msync (addr length flags)
  (declare (type system-area-pointer addr)
	   (type (unsigned-byte 32) length)
	   (type (signed-byte 32) flags))
  (syscall ("msync" system-area-pointer size-t int) t addr length flags))

(defun unix-mprotect (addr length prot)
  (declare (type system-area-pointer addr)
	   (type (unsigned-byte 32) length)
           (type (integer 1 7) prot))
  (syscall ("mprotect" system-area-pointer size-t int)
	   t addr length prot))
  
;;;; Lisp types used by syscalls.

(deftype unix-pathname () 'simple-string)
(deftype unix-fd () `(integer 0 ,most-positive-fixnum))

(deftype unix-file-mode () '(unsigned-byte 32))
(deftype unix-pid () '(unsigned-byte 32))
(deftype unix-uid () '(unsigned-byte 32))
(deftype unix-gid () '(unsigned-byte 32))


;;;; User and group database structures: <pwd.h> and <grp.h>

(defstruct user-info
  (name "" :type string)
  (password "" :type string)
  (uid 0 :type unix-uid)
  (gid 0 :type unix-gid)
  (gecos "" :type string)
  (dir "" :type string)
  (shell "" :type string))

(defstruct group-info
  (name "" :type string)
  (password "" :type string)
  (gid 0 :type unix-gid)
  (members nil :type list))             ; list of logins as strings

(def-alien-type nil
    (struct passwd
	    (pw-name (* char))          ; user's login name
	    (pw-passwd (* char))        ; no longer used
	    (pw-uid uid-t)              ; user id
	    (pw-gid gid-t)              ; group id
	    (pw-gecos (* char))         ; typically user's full name
	    (pw-dir (* char))           ; user's home directory
	    (pw-shell (* char))))       ; user's login shell

(def-alien-type nil
  (struct group
      (gr-name (* char))                ; name of the group
      (gr-passwd (* char))              ; encrypted group password
      (gr-gid gid-t)                    ; numerical group ID
      (gr-mem (* (* char)))))           ; vector of pointers to member names


;;;; System calls.

(def-alien-routine ("os_get_errno" unix-get-errno) int)
(def-alien-routine ("os_set_errno" unix-set-errno) int (newvalue int))
(defun unix-errno () (unix-get-errno))
(defun (setf unix-errno) (newvalue) (unix-set-errno newvalue))

;;; GET-UNIX-ERROR-MSG -- public.
;;; 
(defun get-unix-error-msg (&optional (error-number (unix-errno)))
  _N"Returns a string describing the error number which was returned by a
  UNIX system call."
  (declare (type integer error-number))
  
  (if (array-in-bounds-p *unix-errors* error-number)
      (svref *unix-errors* error-number)
      (format nil (intl:gettext "Unknown error [~d]") error-number)))

(defmacro syscall ((name &rest arg-types) success-form &rest args)
  `(let ((result (alien-funcall (extern-alien ,name (function int ,@arg-types))
				,@args)))
     (if (minusp result)
	 (values nil (unix-errno))
	 ,success-form)))

;;; Like syscall, but if it fails, signal an error instead of returning error
;;; codes.  Should only be used for syscalls that will never really get an
;;; error.
;;;
(defmacro syscall* ((name &rest arg-types) success-form &rest args)
  `(let ((result (alien-funcall (extern-alien ,name (function int ,@arg-types))
				,@args)))
     (if (minusp result)
	 (error (intl:gettext "Syscall ~A failed: ~A") ,name (get-unix-error-msg))
	 ,success-form)))

(defmacro void-syscall ((name &rest arg-types) &rest args)
  `(syscall (,name ,@arg-types) (values t 0) ,@args))

(defmacro int-syscall ((name &rest arg-types) &rest args)
  `(syscall (,name ,@arg-types) (values result 0) ,@args))

;;; From stdio.h

;;; Unix-rename accepts two files names and renames the first to the second.

(defun unix-rename (name1 name2)
  _N"Unix-rename renames the file with string name1 to the string
   name2.  NIL and an error code is returned if an error occured."
  (declare (type unix-pathname name1 name2))
  (void-syscall ("rename" c-string c-string)
		(%name->file name1) (%name->file name2)))

;;; From sys/types.h
;;;         and
;;;      gnu/types.h

(defconstant +max-s-long+ 2147483647)
(defconstant +max-u-long+ 4294967295)

(def-alien-type quad-t #+alpha long #-alpha (array long 2))
(def-alien-type uquad-t #+alpha unsigned-long
		#-alpha (array unsigned-long 2))
(def-alien-type qaddr-t (* quad-t))
(def-alien-type daddr-t int)
(def-alien-type caddr-t (* char))
(def-alien-type swblk-t long)
(def-alien-type size-t #-alpha unsigned-int #+alpha long)
(def-alien-type time-t long)
(def-alien-type clock-t long)
(def-alien-type uid-t unsigned-int)
(def-alien-type ssize-t #-alpha int #+alpha long)
(def-alien-type key-t int)
(def-alien-type int8-t char)
(def-alien-type u-int8-t unsigned-char)
(def-alien-type int16-t short)
(def-alien-type u-int16-t unsigned-short)
(def-alien-type int32-t int)
(def-alien-type u-int32-t unsigned-int)
(def-alien-type int64-t (signed 64))
(def-alien-type u-int64-t (unsigned 64))
(def-alien-type register-t #-alpha int #+alpha long)

(def-alien-type dev-t #-amd64 uquad-t #+amd64 u-int64-t)
(def-alien-type uid-t unsigned-int)
(def-alien-type gid-t unsigned-int)
(def-alien-type ino-t #-amd64 u-int32-t #+amd64 u-int64-t)
(def-alien-type ino64-t u-int64-t)
(def-alien-type mode-t u-int32-t)
(def-alien-type nlink-t #-amd64 unsigned-int #+amd64 u-int64-t)
(def-alien-type off-t int64-t)
(def-alien-type blkcnt-t u-int64-t)
(def-alien-type fsblkcnt-t u-int64-t)
(def-alien-type fsfilcnt-t u-int64-t)
(def-alien-type pid-t int)
;(def-alien-type ssize-t #-alpha int #+alpha long)

(def-alien-type fsid-t (array int 2))

(def-alien-type fd-mask #-alpha unsigned-long #+alpha unsigned-int)

(defconstant fd-setsize 1024)
(defconstant nfdbits 32)
  
(def-alien-type nil
  (struct fd-set
	  (fds-bits (array fd-mask #.(/ fd-setsize nfdbits)))))

(def-alien-type key-t int)

(def-alien-type ipc-pid-t unsigned-short)

;;; direntry.h

(def-alien-type nil
  (struct dirent
    #+glibc2.1
    (d-ino ino-t)                       ; inode number of entry
    #-glibc2.1
    (d-ino ino64-t)                     ; inode number of entry
    (d-off off-t)                       ; offset of next disk directory entry
    (d-reclen unsigned-short)		; length of this record
    (d_type unsigned-char)
    (d-name (array char 256))))		; name must be no longer than this
;;; dirent.h

;;; Operations on Unix Directories.

(export '(open-dir read-dir close-dir))

(defstruct (%directory
	     (:constructor make-directory)
	     (:conc-name directory-)
	     (:print-function %print-directory))
  name
  (dir-struct (required-argument) :type system-area-pointer))

(defun %print-directory (dir stream depth)
  (declare (ignore depth))
  (format stream "#<Directory ~S>" (directory-name dir)))

(defun open-dir (pathname)
  (declare (type unix-pathname pathname))
  (when (string= pathname "")
    (setf pathname "."))
  (let ((kind (unix-file-kind pathname)))
    (case kind
      (:directory
       (let ((dir-struct
	      (alien-funcall (extern-alien "opendir"
					   (function system-area-pointer
						     c-string))
			     (%name->file pathname))))
	 (if (zerop (sap-int dir-struct))
	     (values nil (unix-errno))
	     (make-directory :name pathname :dir-struct dir-struct))))
      ((nil)
       (values nil enoent))
      (t
       (values nil enotdir)))))

(defun read-dir (dir)
  (declare (type %directory dir))
  (let ((daddr (alien-funcall (extern-alien "readdir64"
					    (function system-area-pointer
						      system-area-pointer))
			      (directory-dir-struct dir))))
    (declare (type system-area-pointer daddr))
    (if (zerop (sap-int daddr))
	nil
	(with-alien ((dirent (* (struct dirent)) daddr))
	  (values (%file->name (cast (slot dirent 'd-name) c-string))
		  (slot dirent 'd-ino))))))

(defun close-dir (dir)
  (declare (type %directory dir))
  (alien-funcall (extern-alien "closedir"
			       (function void system-area-pointer))
		 (directory-dir-struct dir))
  nil)

;;; dlfcn.h -> in foreign.lisp

;;; fcntl.h
;;;
;;; POSIX Standard: 6.5 File Control Operations	<fcntl.h>

(defconstant r_ok 4 _N"Test for read permission")
(defconstant w_ok 2 _N"Test for write permission")
(defconstant x_ok 1 _N"Test for execute permission")
(defconstant f_ok 0 _N"Test for presence of file")

(defun unix-fcntl (fd cmd arg)
  _N"Unix-fcntl manipulates file descriptors accoridng to the
   argument CMD which can be one of the following:

   F-DUPFD         Duplicate a file descriptor.
   F-GETFD         Get file descriptor flags.
   F-SETFD         Set file descriptor flags.
   F-GETFL         Get file flags.
   F-SETFL         Set file flags.
   F-GETOWN        Get owner.
   F-SETOWN        Set owner.

   The flags that can be specified for F-SETFL are:

   FNDELAY         Non-blocking reads.
   FAPPEND         Append on each write.
   FASYNC          Signal pgrp when data ready.
   FCREAT          Create if nonexistant.
   FTRUNC          Truncate to zero length.
   FEXCL           Error if already created.
   "
  (declare (type unix-fd fd)
	   (type (unsigned-byte 32) cmd)
	   (type (unsigned-byte 32) arg))
  (int-syscall ("fcntl" int unsigned-int unsigned-int) fd cmd arg))

(defun unix-open (path flags mode)
  _N"Unix-open opens the file whose pathname is specified by PATH
   for reading and/or writing as specified by the FLAGS argument.
   Returns an integer file descriptor.
   The flags argument can be:

     o_rdonly        Read-only flag.
     o_wronly        Write-only flag.
     o_rdwr          Read-and-write flag.
     o_append        Append flag.
     o_creat         Create-if-nonexistant flag.
     o_trunc         Truncate-to-size-0 flag.
     o_excl          Error if the file already exists
     o_noctty        Don't assign controlling tty
     o_ndelay        Non-blocking I/O
     o_sync          Synchronous I/O
     o_async         Asynchronous I/O

   If the o_creat flag is specified, then the file is created with
   a permission of argument MODE if the file doesn't exist."
  (declare (type unix-pathname path)
	   (type fixnum flags)
	   (type unix-file-mode mode))
  (int-syscall ("open64" c-string int int) (%name->file path) flags mode))

(defun unix-getdtablesize ()
  _N"Unix-getdtablesize returns the maximum size of the file descriptor
   table. (i.e. the maximum number of descriptors that can exist at
   one time.)"
  (int-syscall ("getdtablesize")))

;;; Unix-close accepts a file descriptor and attempts to close the file
;;; associated with it.

(defun unix-close (fd)
  _N"Unix-close takes an integer file descriptor as an argument and
   closes the file associated with it.  T is returned upon successful
   completion, otherwise NIL and an error number."
  (declare (type unix-fd fd))
  (void-syscall ("close" int) fd))

;;; Unix-creat accepts a file name and a mode.  It creates a new file
;;; with name and sets it mode to mode (as for chmod).

(defun unix-creat (name mode)
  _N"Unix-creat accepts a file name and a mode (same as those for
   unix-chmod) and creates a file by that name with the specified
   permission mode.  It returns a file descriptor on success,
   or NIL and an error  number otherwise.

   This interface is made obsolete by UNIX-OPEN."
  
  (declare (type unix-pathname name)
	   (type unix-file-mode mode))
  (int-syscall ("creat64" c-string int) (%name->file name) mode))

;;; fcntlbits.h

(defconstant o_read    o_rdonly _N"Open for reading")
(defconstant o_write   o_wronly _N"Open for writing")

(defconstant o_rdonly  0 _N"Read-only flag.") 
(defconstant o_wronly  1 _N"Write-only flag.")
(defconstant o_rdwr    2 _N"Read-write flag.")
(defconstant o_accmode 3 _N"Access mode mask.")

#-alpha
(progn
  (defconstant o_creat   #o100 _N"Create if nonexistant flag. (not fcntl)") 
  (defconstant o_excl    #o200 _N"Error if already exists. (not fcntl)")
  (defconstant o_noctty  #o400 _N"Don't assign controlling tty. (not fcntl)")
  (defconstant o_trunc   #o1000 _N"Truncate flag. (not fcntl)")
  (defconstant o_append  #o2000 _N"Append flag.")
  (defconstant o_ndelay  #o4000 _N"Non-blocking I/O")
  (defconstant o_nonblock #o4000 _N"Non-blocking I/O")
  (defconstant o_ndelay  o_nonblock)
  (defconstant o_sync    #o10000 _N"Synchronous writes (on ext2)")
  (defconstant o_fsync    o_sync)
  (defconstant o_async   #o20000 _N"Asynchronous I/O"))
#+alpha
(progn
  (defconstant o_creat   #o1000 _N"Create if nonexistant flag. (not fcntl)") 
  (defconstant o_trunc   #o2000 _N"Truncate flag. (not fcntl)")
  (defconstant o_excl    #o4000 _N"Error if already exists. (not fcntl)")
  (defconstant o_noctty  #o10000 _N"Don't assign controlling tty. (not fcntl)")
  (defconstant o_nonblock #o4 _N"Non-blocking I/O")
  (defconstant o_append  #o10 _N"Append flag.")
  (defconstant o_ndelay  o_nonblock)
  (defconstant o_sync    #o40000 _N"Synchronous writes (on ext2)")
  (defconstant o_fsync    o_sync)
  (defconstant o_async   #o20000 _N"Asynchronous I/O"))

(defconstant f-dupfd    0  _N"Duplicate a file descriptor")
(defconstant f-getfd    1  _N"Get file desc. flags")
(defconstant f-setfd    2  _N"Set file desc. flags")
(defconstant f-getfl    3  _N"Get file flags")
(defconstant f-setfl    4  _N"Set file flags")

#-alpha
(progn
  (defconstant f-getlk    5   _N"Get lock")
  (defconstant f-setlk    6   _N"Set lock")
  (defconstant f-setlkw   7   _N"Set lock, wait for release")
  (defconstant f-setown   8  _N"Set owner (for sockets)")
  (defconstant f-getown   9  _N"Get owner (for sockets)"))
#+alpha
(progn
  (defconstant f-getlk    7   _N"Get lock")
  (defconstant f-setlk    8   _N"Set lock")
  (defconstant f-setlkw   9   _N"Set lock, wait for release")
  (defconstant f-setown   5  _N"Set owner (for sockets)")
  (defconstant f-getown   6  _N"Get owner (for sockets)"))



(defconstant F-CLOEXEC 1 _N"for f-getfl and f-setfl")

#-alpha
(progn
  (defconstant F-RDLCK 0 _N"for fcntl and lockf")
  (defconstant F-WRLCK 1 _N"for fcntl and lockf")
  (defconstant F-UNLCK 2 _N"for fcntl and lockf")
  (defconstant F-EXLCK 4 _N"old bsd flock (depricated)")
  (defconstant F-SHLCK 8 _N"old bsd flock (depricated)"))
#+alpha
(progn
  (defconstant F-RDLCK 1 _N"for fcntl and lockf")
  (defconstant F-WRLCK 2 _N"for fcntl and lockf")
  (defconstant F-UNLCK 8 _N"for fcntl and lockf")
  (defconstant F-EXLCK 16 _N"old bsd flock (depricated)")
  (defconstant F-SHLCK 32 _N"old bsd flock (depricated)"))

(defconstant F-LOCK-SH 1 _N"Shared lock for bsd flock")
(defconstant F-LOCK-EX 2 _N"Exclusive lock for bsd flock")
(defconstant F-LOCK-NB 4 _N"Don't block. Combine with F-LOCK-SH or F-LOCK-EX")
(defconstant F-LOCK-UN 8 _N"Remove lock for bsd flock")

(def-alien-type nil
    (struct flock
	    (l-type short)
	    (l-whence short)
	    (l-start off-t)
	    (l-len off-t)
	    (l-pid pid-t)))

;;; Define some more compatibility macros to be backward compatible with
;;; BSD systems which did not managed to hide these kernel macros. 

(defconstant FAPPEND  o_append _N"depricated stuff")
(defconstant FFSYNC   o_fsync  _N"depricated stuff")
(defconstant FASYNC   o_async  _N"depricated stuff")
(defconstant FNONBLOCK  o_nonblock _N"depricated stuff")
(defconstant FNDELAY  o_ndelay _N"depricated stuff")


;;; grp.h 

;;;  POSIX Standard: 9.2.1 Group Database Access	<grp.h>

#+(or)
(defun unix-setgrend ()
  _N"Rewind the group-file stream."
  (void-syscall ("setgrend")))

#+(or)
(defun unix-endgrent ()
  _N"Close the group-file stream."
  (void-syscall ("endgrent")))

#+(or)
(defun unix-getgrent ()
  _N"Read an entry from the group-file stream, opening it if necessary."
  
  (let ((result (alien-funcall (extern-alien "getgrent"
					     (function (* (struct group)))))))
    (declare (type system-area-pointer result))
    (if (zerop (sap-int result))
	nil
      result)))

;;; ioctl-types.h

(def-alien-type nil
  (struct winsize
    (ws-row unsigned-short)		; rows, in characters
    (ws-col unsigned-short)		; columns, in characters
    (ws-xpixel unsigned-short)		; horizontal size, pixels
    (ws-ypixel unsigned-short)))	; veritical size, pixels

(defconstant +NCC+ 8
  _N"Size of control character vector.")

(def-alien-type nil
  (struct termio
    (c-iflag unsigned-int) ; input mode flags
    (c-oflag unsigned-int) ; output mode flags
    (c-cflag unsigned-int) ; control mode flags
    (c-lflag unsigned-int) ; local mode flags
    (c-line unsigned-char) ; line discipline
    (c-cc (array unsigned-char #.+NCC+)))) ; control characters

;;; modem lines 
(defconstant tiocm-le  1)
(defconstant tiocm-dtr 2)
(defconstant tiocm-rts 4)
(defconstant tiocm-st  8)
(defconstant tiocm-sr  #x10)
(defconstant tiocm-cts #x20)
(defconstant tiocm-car #x40)
(defconstant tiocm-rng #x80)
(defconstant tiocm-dsr #x100)
(defconstant tiocm-cd  tiocm-car)
(defconstant tiocm-ri  #x80)

;;; ioctl (fd, TIOCSERGETLSR, &result) where result may be as below 

;;; line disciplines 
(defconstant N-TTY    0)
(defconstant N-SLIP   1)
(defconstant N-MOUSE  2)
(defconstant N-PPP    3)
(defconstant N-STRIP  4)
(defconstant N-AX25   5)


;;; ioctls.h

;;; Routing table calls. 
(defconstant siocaddrt	#x890B) ;; add routing table entry	
(defconstant siocdelrt	#x890C) ;; delete routing table entry	
(defconstant siocrtmsg	#x890D) ;; call to routing system	

;;; Socket configuration controls.
(defconstant siocgifname #x8910) ;; get iface name		
(defconstant siocsiflink #x8911) ;; set iface channel		
(defconstant siocgifconf #x8912) ;; get iface list		
(defconstant siocgifflags #x8913) ;; get flags			
(defconstant siocsifflags #x8914) ;; set flags			
(defconstant siocgifaddr #x8915) ;; get PA address		
(defconstant siocsifaddr #x8916) ;; set PA address		
(defconstant siocgifdstaddr #x8917  ) ;; get remote PA address 
(defconstant siocsifdstaddr #x8918  ) ;; set remote PA address 
(defconstant siocgifbrdaddr #x8919  ) ;; get broadcast PA address 
(defconstant siocsifbrdaddr #x891a  ) ;; set broadcast PA address 
(defconstant siocgifnetmask #x891b  ) ;; get network PA mask  
(defconstant siocsifnetmask #x891c  ) ;; set network PA mask  
(defconstant siocgifmetric #x891d  ) ;; get metric   
(defconstant siocsifmetric #x891e  ) ;; set metric   
(defconstant siocgifmem #x891f  ) ;; get memory address (BSD) 
(defconstant siocsifmem #x8920  ) ;; set memory address (BSD) 
(defconstant siocgifmtu #x8921  ) ;; get MTU size   
(defconstant siocsifmtu #x8922  ) ;; set MTU size   
(defconstant siocsifhwaddr #x8924  ) ;; set hardware address  
(defconstant siocgifencap #x8925  ) ;; get/set encapsulations       
(defconstant siocsifencap #x8926)
(defconstant siocgifhwaddr #x8927  ) ;; Get hardware address  
(defconstant siocgifslave #x8929  ) ;; Driver slaving support 
(defconstant siocsifslave #x8930)
(defconstant siocaddmulti #x8931  ) ;; Multicast address lists 
(defconstant siocdelmulti #x8932)
(defconstant siocgifindex #x8933  ) ;; name -> if_index mapping 
(defconstant siogifindex SIOCGIFINDEX ) ;; misprint compatibility :-) 
(defconstant siocsifpflags #x8934  ) ;; set/get extended flags set 
(defconstant siocgifpflags #x8935)
(defconstant siocdifaddr #x8936  ) ;; delete PA address  
(defconstant siocsifhwbroadcast #x8937 ) ;; set hardware broadcast addr 
(defconstant siocgifcount #x8938  ) ;; get number of devices 

(defconstant siocgifbr #x8940  ) ;; Bridging support  
(defconstant siocsifbr #x8941  ) ;; Set bridging options  

(defconstant siocgiftxqlen #x8942  ) ;; Get the tx queue length 
(defconstant siocsiftxqlen #x8943  ) ;; Set the tx queue length  


;;; ARP cache control calls. 
;;  0x8950 - 0x8952  * obsolete calls, don't re-use 
(defconstant siocdarp #x8953  ) ;; delete ARP table entry 
(defconstant siocgarp #x8954  ) ;; get ARP table entry  
(defconstant siocsarp #x8955  ) ;; set ARP table entry  

;;; RARP cache control calls. 
(defconstant siocdrarp #x8960  ) ;; delete RARP table entry 
(defconstant siocgrarp #x8961  ) ;; get RARP table entry  
(defconstant siocsrarp #x8962  ) ;; set RARP table entry  

;;; Driver configuration calls 

(defconstant siocgifmap #x8970  ) ;; Get device parameters 
(defconstant siocsifmap #x8971  ) ;; Set device parameters 

;;; DLCI configuration calls 

(defconstant siocadddlci #x8980  ) ;; Create new DLCI device 
(defconstant siocdeldlci #x8981  ) ;; Delete DLCI device  

;;; Device private ioctl calls. 

;; These 16 ioctls are available to devices via the do_ioctl() device
;; vector.  Each device should include this file and redefine these
;; names as their own. Because these are device dependent it is a good
;; idea _NOT_ to issue them to random objects and hope. 

(defconstant siocdevprivate	#x89F0	) ;; to 89FF 


;;; netdb.h

;; All data returned by the network data base library are supplied in
;; host order and returned in network order (suitable for use in
;; system calls).

;;; Absolute file name for network data base files.
(defconstant path-hequiv "/etc/hosts.equiv")
(defconstant path-hosts "/etc/hosts")
(defconstant path-networks "/etc/networks")
(defconstant path-nsswitch_conf "/etc/nsswitch.conf")
(defconstant path-protocols "/etc/protocols")
(defconstant path-services "/etc/services")


;;; Possible values left in `h_errno'.
(defconstant netdb-internal -1 _N"See errno.")
(defconstant netdb-success 0 _N"No problem.")
(defconstant host-not-found 1 _N"Authoritative Answer Host not found.")
(defconstant try-again 2 _N"Non-Authoritative Host not found,or SERVERFAIL.")
(defconstant no-recovery 3 _N"Non recoverable errors, FORMERR, REFUSED, NOTIMP.")
(defconstant no-data 4	"Valid name, no data record of requested type.")
(defconstant no-address	no-data	"No address, look for MX record.")

;;; Description of data base entry for a single host.

(def-alien-type nil
    (struct hostent
	    (h-name c-string)        ; Official name of host.
	    (h-aliases (* c-string)) ; Alias list.
	    (h-addrtype int)         ; Host address type.
	    (h_length int)           ; Length of address.
	    (h-addr-list (* c-string)))) ; List of addresses from name server.

#+(or)
(defun unix-sethostent (stay-open)
  _N"Open host data base files and mark them as staying open even after
a later search if STAY_OPEN is non-zero."
  (void-syscall ("sethostent" int) stay-open))

#+(or)
(defun unix-endhostent ()
  _N"Close host data base files and clear `stay open' flag."
  (void-syscall ("endhostent")))

#+(or)
(defun unix-gethostent ()
  _N"Get next entry from host data base file.  Open data base if
necessary."
    (let ((result (alien-funcall (extern-alien "gethostent"
					     (function (* (struct hostent)))))))
    (declare (type system-area-pointer result))
    (if (zerop (sap-int result))
	nil
      result)))

#+(or)
(defun unix-gethostbyaddr(addr length type)
  _N"Return entry from host data base which address match ADDR with
length LEN and type TYPE."
    (let ((result (alien-funcall (extern-alien "gethostbyaddr"
					     (function (* (struct hostent))
						       c-string int int))
				 addr len type)))
    (declare (type system-area-pointer result))
    (if (zerop (sap-int result))
	nil
      result)))

#+(or)
(defun unix-gethostbyname (name)
  _N"Return entry from host data base for host with NAME."
    (let ((result (alien-funcall (extern-alien "gethostbyname"
					     (function (* (struct hostent))
						       c-string))
				 name)))
    (declare (type system-area-pointer result))
    (if (zerop (sap-int result))
	nil
      result)))

#+(or)
(defun unix-gethostbyname2 (name af)
  _N"Return entry from host data base for host with NAME.  AF must be
   set to the address type which as `AF_INET' for IPv4 or `AF_INET6'
   for IPv6."
    (let ((result (alien-funcall (extern-alien "gethostbyname2"
					     (function (* (struct hostent))
						       c-string int))
				 name af)))
    (declare (type system-area-pointer result))
    (if (zerop (sap-int result))
	nil
      result)))

;; Description of data base entry for a single network.  NOTE: here a
;; poor assumption is made.  The network number is expected to fit
;; into an unsigned long int variable.

(def-alien-type nil
    (struct netent
	    (n-name c-string) ; Official name of network.
	    (n-aliases (* c-string)) ; Alias list.
	    (n-addrtype int) ;  Net address type.
	    (n-net unsigned-long))) ; Network number.

#+(or)
(defun unix-setnetent (stay-open)
  _N"Open network data base files and mark them as staying open even
   after a later search if STAY_OPEN is non-zero."
  (void-syscall ("setnetent" int) stay-open))


#+(or)
(defun unix-endnetent ()
  _N"Close network data base files and clear `stay open' flag."
  (void-syscall ("endnetent")))


#+(or)
(defun unix-getnetent ()
  _N"Get next entry from network data base file.  Open data base if
   necessary."
    (let ((result (alien-funcall (extern-alien "getnetent"
					     (function (* (struct netent)))))))
    (declare (type system-area-pointer result))
    (if (zerop (sap-int result))
	nil
      result)))


#+(or)
(defun unix-getnetbyaddr (net type)
  _N"Return entry from network data base which address match NET and
   type TYPE."
    (let ((result (alien-funcall (extern-alien "getnetbyaddr"
					     (function (* (struct netent))
						       unsigned-long int))
				 net type)))
    (declare (type system-area-pointer result))
    (if (zerop (sap-int result))
	nil
      result)))

#+(or)
(defun unix-getnetbyname (name)
  _N"Return entry from network data base for network with NAME."
    (let ((result (alien-funcall (extern-alien "getnetbyname"
					     (function (* (struct netent))
						       c-string))
				 name)))
    (declare (type system-area-pointer result))
    (if (zerop (sap-int result))
	nil
      result)))

;; Description of data base entry for a single service.
(def-alien-type nil
    (struct servent
	    (s-name c-string) ; Official service name.
	    (s-aliases (* c-string)) ; Alias list.
	    (s-port int) ; Port number.
	    (s-proto c-string))) ; Protocol to use.

#+(or)
(defun unix-setservent (stay-open)
  _N"Open service data base files and mark them as staying open even
   after a later search if STAY_OPEN is non-zero."
  (void-syscall ("setservent" int) stay-open))

#+(or)
(defun unix-endservent (stay-open)
  _N"Close service data base files and clear `stay open' flag."
  (void-syscall ("endservent")))


#+(or)
(defun unix-getservent ()
  _N"Get next entry from service data base file.  Open data base if
   necessary."
    (let ((result (alien-funcall (extern-alien "getservent"
					     (function (* (struct servent)))))))
    (declare (type system-area-pointer result))
    (if (zerop (sap-int result))
	nil
      result)))

#+(or)
(defun unix-getservbyname (name proto)
  _N"Return entry from network data base for network with NAME and
   protocol PROTO."
    (let ((result (alien-funcall (extern-alien "getservbyname"
					     (function (* (struct netent))
						       c-string (* char)))
				 name proto)))
    (declare (type system-area-pointer result))
    (if (zerop (sap-int result))
	nil
      result)))

#+(or)
(defun unix-getservbyport (port proto)
  _N"Return entry from service data base which matches port PORT and
   protocol PROTO."
    (let ((result (alien-funcall (extern-alien "getservbyport"
					     (function (* (struct netent))
						       int (* char)))
				 port proto)))
    (declare (type system-area-pointer result))
    (if (zerop (sap-int result))
	nil
      result)))

;;  Description of data base entry for a single service.

(def-alien-type nil
    (struct protoent
	    (p-name c-string) ; Official protocol name.
	    (p-aliases (* c-string)) ; Alias list.
	    (p-proto int))) ; Protocol number.

#+(or)
(defun unix-setprotoent (stay-open)
  _N"Open protocol data base files and mark them as staying open even
   after a later search if STAY_OPEN is non-zero."
  (void-syscall ("setprotoent" int) stay-open))

#+(or)
(defun unix-endprotoent ()
  _N"Close protocol data base files and clear `stay open' flag."
  (void-syscall ("endprotoent")))

#+(or)
(defun unix-getprotoent ()
  _N"Get next entry from protocol data base file.  Open data base if
   necessary."
    (let ((result (alien-funcall (extern-alien "getprotoent"
					     (function (* (struct protoent)))))))
    (declare (type system-area-pointer result))
    (if (zerop (sap-int result))
	nil
      result)))

#+(or)
(defun unix-getprotobyname (name)
  _N"Return entry from protocol data base for network with NAME."
    (let ((result (alien-funcall (extern-alien "getprotobyname"
					     (function (* (struct protoent))
						       c-string))
				 name)))
    (declare (type system-area-pointer result))
    (if (zerop (sap-int result))
	nil
      result)))

#+(or)
(defun unix-getprotobynumber (proto)
  _N"Return entry from protocol data base which number is PROTO."
    (let ((result (alien-funcall (extern-alien "getprotobynumber"
					     (function (* (struct protoent))
						       int))
				 proto)))
    (declare (type system-area-pointer result))
    (if (zerop (sap-int result))
	nil
      result)))

#+(or)
(defun unix-setnetgrent (netgroup)
  _N"Establish network group NETGROUP for enumeration."
  (int-syscall ("setservent" c-string) netgroup))

#+(or)
(defun unix-endnetgrent ()
  _N"Free all space allocated by previous `setnetgrent' call."
  (void-syscall ("endnetgrent")))

#+(or)
(defun unix-getnetgrent (hostp userp domainp)
  _N"Get next member of netgroup established by last `setnetgrent' call
   and return pointers to elements in HOSTP, USERP, and DOMAINP."
  (int-syscall ("getnetgrent" (* c-string) (* c-string) (* c-string))
	       hostp userp domainp))

#+(or)
(defun unix-innetgr (netgroup host user domain)
  _N"Test whether NETGROUP contains the triple (HOST,USER,DOMAIN)."
  (int-syscall ("innetgr" c-string c-string c-string c-string)
	       netgroup host user domain))

(def-alien-type nil
    (struct addrinfo
	    (ai-flags int)    ; Input flags.
	    (ai-family int)   ; Protocol family for socket.
	    (ai-socktype int) ; Socket type.
	    (ai-protocol int) ; Protocol for socket.
	    (ai-addrlen int)  ; Length of socket address.
	    (ai-addr (* (struct sockaddr)))
	                      ; Socket address for socket.
	    (ai-cononname c-string)
	                      ; Canonical name for service location.
	    (ai-net (* (struct addrinfo))))) ; Pointer to next in list.

;; Possible values for `ai_flags' field in `addrinfo' structure.

(defconstant ai_passive 1 _N"Socket address is intended for `bind'.")
(defconstant ai_canonname 2 _N"Request for canonical name.")

;; Error values for `getaddrinfo' function.
(defconstant eai_badflags -1 _N"Invalid value for `ai_flags' field.")
(defconstant eai_noname -2 _N"NAME or SERVICE is unknown.")
(defconstant eai_again -3 _N"Temporary failure in name resolution.")
(defconstant eai_fail -4 _N"Non-recoverable failure in name res.")
(defconstant eai_nodata -5 _N"No address associated with NAME.")
(defconstant eai_family -6 _N"ai_family not supported.")
(defconstant eai_socktype -7 _N"ai_socktype not supported.")
(defconstant eai_service -8 _N"SERVICE not supported for ai_socktype.")
(defconstant eai_addrfamily -9 _N"Address family for NAME not supported.")
(defconstant eai_memory -10 _N"Memory allocation failure.")
(defconstant eai_system -11 _N"System error returned in errno.")


#+(or)
(defun unix-getaddrinfo (name service req pai)
  _N"Translate name of a service location and/or a service name to set of
   socket addresses."
  (int-syscall ("getaddrinfo" c-string c-string (* (struct addrinfo))
			      (* (* struct addrinfo)))
	       name service req pai))


#+(or)
(defun unix-freeaddrinfo (ai)
  _N"Free `addrinfo' structure AI including associated storage."
  (void-syscall ("freeaddrinfo" (* struct addrinfo))
		ai))


;;; pty.h

(defun unix-openpty (name termp winp)
  _N"Create pseudo tty master slave pair with NAME and set terminal
   attributes according to TERMP and WINP and return handles for both
   ends in AMASTER and ASLAVE."
  (with-alien ((amaster int)
	       (aslave int))
    (values
     (int-syscall ("openpty" (* int) (* int) c-string (* (struct termios))
			     (* (struct winsize)))
		  (addr amaster) (addr aslave) name termp winp)
     amaster aslave)))

#+(or)
(defun unix-forkpty (amaster name termp winp)
  _N"Create child process and establish the slave pseudo terminal as the
   child's controlling terminal."
  (int-syscall ("forkpty" (* int) c-string (* (struct termios))
			  (* (struct winsize)))
	       amaster name termp winp))


;; POSIX Standard: 9.2.2 User Database Access <pwd.h>

#+(or)
(defun unix-setpwent ()
  _N"Rewind the password-file stream."
  (void-syscall ("setpwent")))

#+(or)
(defun unix-endpwent ()
  _N"Close the password-file stream."
  (void-syscall ("endpwent")))

#+(or)
(defun unix-getpwent ()
  _N"Read an entry from the password-file stream, opening it if necessary."
    (let ((result (alien-funcall (extern-alien "getpwent"
					     (function (* (struct passwd)))))))
    (declare (type system-area-pointer result))
    (if (zerop (sap-int result))
	nil
	result)))

;;; resourcebits.h

(def-alien-type nil
  (struct rlimit
    (rlim-cur long)	 ; current (soft) limit
    (rlim-max long))); maximum value for rlim-cur

(defconstant rusage_self 0 _N"The calling process.")
(defconstant rusage_children -1 _N"Terminated child processes.")
(defconstant rusage_both -2)

(def-alien-type nil
  (struct rusage
    (ru-utime (struct timeval))		; user time used
    (ru-stime (struct timeval))		; system time used.
    (ru-maxrss long)                    ; Maximum resident set size (in kilobytes)
    (ru-ixrss long)			; integral shared memory size
    (ru-idrss long)			; integral unshared data "
    (ru-isrss long)			; integral unshared stack "
    (ru-minflt long)			; page reclaims
    (ru-majflt long)			; page faults
    (ru-nswap long)			; swaps
    (ru-inblock long)			; block input operations
    (ru-oublock long)			; block output operations
    (ru-msgsnd long)			; messages sent
    (ru-msgrcv long)			; messages received
    (ru-nsignals long)			; signals received
    (ru-nvcsw long)			; voluntary context switches
    (ru-nivcsw long)))			; involuntary "

;; Priority limits.

(defconstant prio-min -20 _N"Minimum priority a process can have")
(defconstant prio-max 20 _N"Maximum priority a process can have")


;;; The type of the WHICH argument to `getpriority' and `setpriority',
;;; indicating what flavor of entity the WHO argument specifies.

(defconstant priority-process 0 _N"WHO is a process ID")
(defconstant priority-pgrp 1 _N"WHO is a process group ID")
(defconstant priority-user 2 _N"WHO is a user ID")

;;; sched.h

#+(or)
(defun unix-sched_setparam (pid param)
  _N"Rewind the password-file stream."
  (int-syscall ("sched_setparam" pid-t (struct psched-param))
		pid param))

#+(or)
(defun unix-sched_getparam (pid param)
  _N"Rewind the password-file stream."
  (int-syscall ("sched_getparam" pid-t (struct psched-param))
		pid param))


#+(or)
(defun unix-sched_setscheduler (pid policy param)
  _N"Set scheduling algorithm and/or parameters for a process."
  (int-syscall ("sched_setscheduler" pid-t int (struct psched-param))
		pid policy param))

#+(or)
(defun unix-sched_getscheduler (pid)
  _N"Retrieve scheduling algorithm for a particular purpose."
  (int-syscall ("sched_getscheduler" pid-t)
		pid))

(defun unix-sched-yield ()
  _N"Retrieve scheduling algorithm for a particular purpose."
  (int-syscall ("sched_yield")))

#+(or)
(defun unix-sched_get_priority_max (algorithm)
  _N"Get maximum priority value for a scheduler."
  (int-syscall ("sched_get_priority_max" int)
		algorithm))

#+(or)
(defun unix-sched_get_priority_min (algorithm)
  _N"Get minimum priority value for a scheduler."
  (int-syscall ("sched_get_priority_min" int)
		algorithm))



#+(or)
(defun unix-sched_rr_get_interval (pid t)
  _N"Get the SCHED_RR interval for the named process."
  (int-syscall ("sched_rr_get_interval" pid-t (* (struct timespec)))
		pid t))

;;; schedbits.h

(defconstant scheduler-other 0)
(defconstant scheduler-fifo 1)
(defconstant scheduler-rr 2)


;; Data structure to describe a process' schedulability.

(def-alien-type nil
    (struct sched_param
	    (sched-priority int)))

;; Cloning flags.
(defconstant csignal       #x000000ff _N"Signal mask to be sent at exit.")
(defconstant clone_vm      #x00000100 _N"Set if VM shared between processes.")
(defconstant clone_fs      #x00000200 _N"Set if fs info shared between processes")
(defconstant clone_files   #x00000400 _N"Set if open files shared between processe")
(defconstant clone_sighand #x00000800 _N"Set if signal handlers shared.")
(defconstant clone_pid     #x00001000 _N"Set if pid shared.")


;;; shadow.h

;; Structure of the password file.

(def-alien-type nil
    (struct spwd
	    (sp-namp c-string) ; Login name.
	    (sp-pwdp c-string) ; Encrypted password.
	    (sp-lstchg long)   ; Date of last change.
	    (sp-min long)      ; Minimum number of days between changes.
	    (sp-max long)      ; Maximum number of days between changes.
	    (sp-warn long)     ; Number of days to warn user to change the password.
	    (sp-inact long)    ; Number of days the account may be inactive.
	    (sp-expire long)   ; Number of days since 1970-01-01 until account expires.
	    (sp-flags long)))  ; Reserved.

#+(or)
(defun unix-setspent ()
  _N"Open database for reading."
  (void-syscall ("setspent")))

#+(or)
(defun unix-endspent ()
  _N"Close database."
  (void-syscall ("endspent")))

#+(or)
(defun unix-getspent ()
  _N"Get next entry from database, perhaps after opening the file."
    (let ((result (alien-funcall (extern-alien "getspent"
					     (function (* (struct spwd)))))))
    (declare (type system-area-pointer result))
    (if (zerop (sap-int result))
	nil
      result)))

#+(or)
(defun unix-getspnam (name)
  _N"Get shadow entry matching NAME."
    (let ((result (alien-funcall (extern-alien "getspnam"
					     (function (* (struct spwd))
						       c-string))
				 name)))
    (declare (type system-area-pointer result))
    (if (zerop (sap-int result))
	nil
      result)))

#+(or)
(defun unix-sgetspent (string)
  _N"Read shadow entry from STRING."
    (let ((result (alien-funcall (extern-alien "sgetspent"
					     (function (* (struct spwd))
						       c-string))
				 string)))
    (declare (type system-area-pointer result))
    (if (zerop (sap-int result))
	nil
      result)))

;; 

#+(or)
(defun unix-lckpwdf ()
  _N"Protect password file against multi writers."
  (void-syscall ("lckpwdf")))


#+(or)
(defun unix-ulckpwdf ()
  _N"Unlock password file."
  (void-syscall ("ulckpwdf")))

;;; bits/stat.h

(def-alien-type nil
  (struct stat
    (st-dev dev-t)
    #-(or alpha amd64) (st-pad1 unsigned-short)
    (st-ino ino-t)
    #+alpha (st-pad1 unsigned-int)
    #-amd64 (st-mode mode-t)
    (st-nlink  nlink-t)
    #+amd64 (st-mode mode-t)
    (st-uid  uid-t)
    (st-gid  gid-t)
    (st-rdev dev-t)
    #-alpha (st-pad2  unsigned-short)
    (st-size off-t)
    #-alpha (st-blksize unsigned-long)
    #-alpha (st-blocks blkcnt-t)
    (st-atime time-t)
    #-alpha (unused-1 unsigned-long)
    (st-mtime time-t)
    #-alpha (unused-2 unsigned-long)
    (st-ctime time-t)
    #+alpha (st-blocks int)
    #+alpha (st-pad2 unsigned-int)
    #+alpha (st-blksize unsigned-int)
    #+alpha (st-flags unsigned-int)
    #+alpha (st-gen unsigned-int)
    #+alpha (st-pad3 unsigned-int)
    #+alpha (unused-1 unsigned-long)
    #+alpha (unused-2 unsigned-long)
    (unused-3 unsigned-long)
    (unused-4 unsigned-long)
    #-alpha (unused-5 unsigned-long)))

;; Encoding of the file mode.

(defconstant s-ifmt   #o0170000 _N"These bits determine file type.")

;; File types.

(defconstant s-ififo  #o0010000 _N"FIFO")
(defconstant s-ifchr  #o0020000 _N"Character device")
(defconstant s-ifdir  #o0040000 _N"Directory")
(defconstant s-ifblk  #o0060000 _N"Block device")
(defconstant s-ifreg  #o0100000 _N"Regular file")

;; These don't actually exist on System V, but having them doesn't hurt.

(defconstant s-iflnk  #o0120000 _N"Symbolic link.")
(defconstant s-ifsock #o0140000 _N"Socket.")

;; Protection bits.

(defconstant s-isuid #o0004000 _N"Set user ID on execution.")
(defconstant s-isgid #o0002000 _N"Set group ID on execution.")
(defconstant s-isvtx #o0001000 _N"Save swapped text after use (sticky).")
(defconstant s-iread #o0000400 _N"Read by owner")
(defconstant s-iwrite #o0000200 _N"Write by owner.")
(defconstant s-iexec #o0000100 _N"Execute by owner.")

;;; statfsbuf.h

(def-alien-type nil
    (struct statfs
	    (f-type int)
	    (f-bsize int)
	    (f-blocks fsblkcnt-t)
	    (f-bfree fsblkcnt-t)
	    (f-bavail fsblkcnt-t)
	    (f-files fsfilcnt-t)
	    (f-ffree fsfilcnt-t)
	    (f-fsid fsid-t)
	    (f-namelen int)
	    (f-spare (array int 6))))


;;; termbits.h

(def-alien-type cc-t unsigned-char)
(def-alien-type speed-t  unsigned-int)
(def-alien-type tcflag-t unsigned-int)

(defconstant +NCCS+ 32
  _N"Size of control character vector.")

(def-alien-type nil
  (struct termios
    (c-iflag tcflag-t)
    (c-oflag tcflag-t)
    (c-cflag tcflag-t)
    (c-lflag tcflag-t)
    (c-line cc-t)
    (c-cc (array cc-t #.+NCCS+))
    (c-ispeed speed-t)
    (c-ospeed speed-t)))

;; c_cc characters

(def-enum + 0 vintr vquit verase
	  vkill veof vtime
	  vmin vswtc vstart
	  vstop vsusp veol
	  vreprint vdiscard vwerase
	  vlnext veol2)
(defvar vdsusp vsusp)

(def-enum + 0 tciflush tcoflush tcioflush)

(def-enum + 0 tcsanow tcsadrain tcsaflush)

;; c_iflag bits
(def-enum ash 1 tty-ignbrk tty-brkint tty-ignpar tty-parmrk tty-inpck
	  tty-istrip tty-inlcr tty-igncr tty-icrnl tty-iuclc
	  tty-ixon tty-ixany tty-ixoff 
	  tty-imaxbel)

;; c_oflag bits
(def-enum ash 1 tty-opost tty-olcuc tty-onlcr tty-ocrnl tty-onocr
	  tty-onlret tty-ofill tty-ofdel tty-nldly)

(defconstant tty-nl0 0)
(defconstant tty-nl1 #o400)

(defconstant tty-crdly	#o0003000)
(defconstant   tty-cr0	#o0000000)
(defconstant   tty-cr1	#o0001000)
(defconstant   tty-cr2	#o0002000)
(defconstant   tty-cr3	#o0003000)
(defconstant tty-tabdly	#o0014000)
(defconstant   tty-tab0	#o0000000)
(defconstant   tty-tab1	#o0004000)
(defconstant   tty-tab2	#o0010000)
(defconstant   tty-tab3	#o0014000)
(defconstant   tty-xtabs	#o0014000)
(defconstant tty-bsdly	#o0020000)
(defconstant   tty-bs0	#o0000000)
(defconstant   tty-bs1	#o0020000)
(defconstant tty-vtdly	#o0040000)
(defconstant   tty-vt0	#o0000000)
(defconstant   tty-vt1	#o0040000)
(defconstant tty-ffdly	#o0100000)
(defconstant   tty-ff0	#o0000000)
(defconstant   tty-ff1	#o0100000)

;; c-cflag bit meaning
(defconstant tty-cbaud	#o0010017)
(defconstant tty-b0	#o0000000) ;; hang up
(defconstant tty-b50	#o0000001)
(defconstant tty-b75	#o0000002)
(defconstant tty-b110	#o0000003)
(defconstant tty-b134	#o0000004)
(defconstant tty-b150	#o0000005)
(defconstant tty-b200	#o0000006)
(defconstant tty-b300	#o0000007)
(defconstant tty-b600	#o0000010)
(defconstant tty-b1200	#o0000011)
(defconstant tty-b1800	#o0000012)
(defconstant tty-b2400	#o0000013)
(defconstant tty-b4800	#o0000014)
(defconstant tty-b9600	#o0000015)
(defconstant tty-b19200	#o0000016)
(defconstant tty-b38400	#o0000017)
(defconstant tty-exta tty-b19200)
(defconstant tty-extb tty-b38400)
(defconstant tty-csize	#o0000060)
(defconstant tty-cs5	#o0000000)
(defconstant tty-cs6	#o0000020)
(defconstant tty-cs7	#o0000040)
(defconstant tty-cs8	#o0000060)
(defconstant tty-cstopb	#o0000100)
(defconstant tty-cread	#o0000200)
(defconstant tty-parenb	#o0000400)
(defconstant tty-parodd	#o0001000)
(defconstant tty-hupcl	#o0002000)
(defconstant tty-clocal	#o0004000)
(defconstant tty-cbaudex #o0010000)
(defconstant tty-b57600  #o0010001)
(defconstant tty-b115200 #o0010002)
(defconstant tty-b230400 #o0010003)
(defconstant tty-b460800 #o0010004)
(defconstant tty-cibaud	  #o002003600000) ; input baud rate (not used)
(defconstant tty-crtscts	  #o020000000000) ;flow control 

;; c_lflag bits
(def-enum ash 1 tty-isig tty-icanon tty-xcase tty-echo tty-echoe
	  tty-echok tty-echonl tty-noflsh
	  tty-tostop tty-echoctl tty-echoprt
	  tty-echoke tty-flusho
	  tty-pendin tty-iexten)

;;; tcflow() and TCXONC use these 
(def-enum + 0 tty-tcooff tty-tcoon tty-tcioff tty-tcion)

;; tcflush() and TCFLSH use these */
(def-enum + 0 tty-tciflush tty-tcoflush tty-tcioflush)

;; tcsetattr uses these
(def-enum + 0 tty-tcsanow tty-tcsadrain tty-tcsaflush)

;;; termios.h

(defun unix-cfgetospeed (termios)
  _N"Get terminal output speed."
  (multiple-value-bind (speed errno)
      (int-syscall ("cfgetospeed" (* (struct termios))) termios)
    (if speed
	(values (svref terminal-speeds speed) 0)
      (values speed errno))))

(defun unix-cfsetospeed (termios speed)
  _N"Set terminal output speed."
  (let ((baud (or (position speed terminal-speeds)
		  (error _"Bogus baud rate ~S" speed))))
    (void-syscall ("cfsetospeed" (* (struct termios)) int) termios baud)))

(defun unix-cfgetispeed (termios)
  _N"Get terminal input speed."
  (multiple-value-bind (speed errno)
      (int-syscall ("cfgetispeed" (* (struct termios))) termios)
    (if speed
	(values (svref terminal-speeds speed) 0)
      (values speed errno))))

(defun unix-cfsetispeed (termios speed)
  _N"Set terminal input speed."
  (let ((baud (or (position speed terminal-speeds)
		  (error _"Bogus baud rate ~S" speed))))
    (void-syscall ("cfsetispeed" (* (struct termios)) int) termios baud)))

(defun unix-tcgetattr (fd termios)
  _N"Get terminal attributes."
  (declare (type unix-fd fd))
  (void-syscall ("tcgetattr" int (* (struct termios))) fd termios))

(defun unix-tcsetattr (fd opt termios)
  _N"Set terminal attributes."
  (declare (type unix-fd fd))
  (void-syscall ("tcsetattr" int int (* (struct termios))) fd opt termios))

(defun unix-tcsendbreak (fd duration)
  _N"Send break"
  (declare (type unix-fd fd))
  (void-syscall ("tcsendbreak" int int) fd duration))

(defun unix-tcdrain (fd)
  _N"Wait for output for finish"
  (declare (type unix-fd fd))
  (void-syscall ("tcdrain" int) fd))

(defun unix-tcflush (fd selector)
  _N"See tcflush(3)"
  (declare (type unix-fd fd))
  (void-syscall ("tcflush" int int) fd selector))

(defun unix-tcflow (fd action)
  _N"Flow control"
  (declare (type unix-fd fd))
  (void-syscall ("tcflow" int int) fd action))

;;; timebits.h

;; A time value that is accurate to the nearest
;; microsecond but also has a range of years.  
(def-alien-type nil
  (struct timeval
	  (tv-sec time-t)	; seconds
	  (tv-usec time-t)))	; and microseconds

;;; unistd.h

(defun sub-unix-execve (program arg-list env-list)
  (let ((argv nil)
	(argv-bytes 0)
	(envp nil)
	(envp-bytes 0)
	result error-code)
    (unwind-protect
	(progn
	  ;; Blast the stuff into the proper format
	  (multiple-value-setq
	      (argv argv-bytes)
	    (string-list-to-c-strvec arg-list))
	  (multiple-value-setq
	      (envp envp-bytes)
	    (string-list-to-c-strvec env-list))
	  ;;
	  ;; Now do the system call
	  (multiple-value-setq
	      (result error-code)
	    (int-syscall ("execve"
			  c-string system-area-pointer system-area-pointer)
			 program argv envp)))
      ;; 
      ;; Deallocate memory
      (when argv
	(system:deallocate-system-memory argv argv-bytes))
      (when envp
	(system:deallocate-system-memory envp envp-bytes)))
    (values result error-code)))

;;;; UNIX-EXECVE

(defun unix-execve (program &optional arg-list
			    (environment *environment-list*))
  _N"Executes the Unix execve system call.  If the system call suceeds, lisp
   will no longer be running in this process.  If the system call fails this
   function returns two values: NIL and an error code.  Arg-list should be a
   list of simple-strings which are passed as arguments to the exec'ed program.
   Environment should be an a-list mapping symbols to simple-strings which this
   function bashes together to form the environment for the exec'ed program."
  (check-type program simple-string)
  (let ((env-list (let ((envlist nil))
		    (dolist (cons environment)
		      (push (if (cdr cons)
				(concatenate 'simple-string
					     (string (car cons)) "="
					     (cdr cons))
				(car cons))
			    envlist))
		    envlist)))
    (sub-unix-execve (%name->file program) arg-list env-list)))


(defmacro round-bytes-to-words (n)
  `(logand (the fixnum (+ (the fixnum ,n) 3)) (lognot 3)))

;; Values for the second argument to access.

;;; Unix-access accepts a path and a mode.  It returns two values the
;;; first is T if the file is accessible and NIL otherwise.  The second
;;; only has meaning in the second case and is the unix errno value.

(defun unix-access (path mode)
  _N"Given a file path (a string) and one of four constant modes,
   unix-access returns T if the file is accessible with that
   mode and NIL if not.  It also returns an errno value with
   NIL which determines why the file was not accessible.

   The access modes are:
	r_ok     Read permission.
	w_ok     Write permission.
	x_ok     Execute permission.
	f_ok     Presence of file."
  (declare (type unix-pathname path)
	   (type (mod 8) mode))
  (void-syscall ("access" c-string int) (%name->file path) mode))

(defconstant l_set 0 _N"set the file pointer")
(defconstant l_incr 1 _N"increment the file pointer")
(defconstant l_xtnd 2 _N"extend the file size")

(defun unix-lseek (fd offset whence)
  _N"UNIX-LSEEK accepts a file descriptor and moves the file pointer ahead
   a certain OFFSET for that file.  WHENCE can be any of the following:

   l_set        Set the file pointer.
   l_incr       Increment the file pointer.
   l_xtnd       Extend the file size.
  "
  (declare (type unix-fd fd)
	   (type (signed-byte 64) offset)
	   (type (integer 0 2) whence))
  (let ((result (alien-funcall
                 (extern-alien "lseek64" (function off-t int off-t int))
                 fd offset whence)))
    (if (minusp result)
        (values nil (unix-errno))
        (values result 0))))


;;; UNIX-READ accepts a file descriptor, a buffer, and the length to read.
;;; It attempts to read len bytes from the device associated with fd
;;; and store them into the buffer.  It returns the actual number of
;;; bytes read.

(defun unix-read (fd buf len)
  _N"UNIX-READ attempts to read from the file described by fd into
   the buffer buf until it is full.  Len is the length of the buffer.
   The number of bytes actually read is returned or NIL and an error
   number if an error occured."
  (declare (type unix-fd fd)
	   (type (unsigned-byte 32) len))
  #+gencgc
  ;; With gencgc, the collector tries to keep raw objects like strings
  ;; in separate pages that are not write-protected.  However, this
  ;; isn't always true.  Thus, BUF will sometimes be write-protected
  ;; and the kernel doesn't like writing to write-protected pages.  So
  ;; go through and touch each page to give the segv handler a chance
  ;; to unprotect the pages.  (This is taken from unix.lisp.)
  (without-gcing
   (let* ((page-size (get-page-size))
	  (1-page-size (1- page-size))
	  (sap (etypecase buf
		 (system-area-pointer buf)
		 (vector (vector-sap buf))))
	  (end (sap+ sap len)))
     (declare (type (and fixnum unsigned-byte) page-size 1-page-size)
	      (type system-area-pointer sap end)
	      (optimize (speed 3) (safety 0)))
     ;; Touch the beginning of every page
     (do ((sap (int-sap (logand (sap-int sap)
				(logxor 1-page-size (ldb (byte 32 0) -1))))
	       (sap+ sap page-size)))
	 ((sap>= sap end))
       (declare (type system-area-pointer sap))
       (setf (sap-ref-8 sap 0) (sap-ref-8 sap 0)))))
  (int-syscall ("read" int (* char) int) fd buf len))


;;; Unix-write accepts a file descriptor, a buffer, an offset, and the
;;; length to write.  It attempts to write len bytes to the device
;;; associated with fd from the the buffer starting at offset.  It returns
;;; the actual number of bytes written.

(defun unix-write (fd buf offset len)
  _N"Unix-write attempts to write a character buffer (buf) of length
   len to the file described by the file descriptor fd.  NIL and an
   error is returned if the call is unsuccessful."
  (declare (type unix-fd fd)
	   (type (unsigned-byte 32) offset len))
  (int-syscall ("write" int (* char) int)
	       fd
	       (with-alien ((ptr (* char) (etypecase buf
					    ((simple-array * (*))
					     (vector-sap buf))
					    (system-area-pointer
					     buf))))
		 (addr (deref ptr offset)))
	       len))

(defun unix-pipe ()
  _N"Unix-pipe sets up a unix-piping mechanism consisting of
  an input pipe and an output pipe.  Unix-Pipe returns two
  values: if no error occurred the first value is the pipe
  to be read from and the second is can be written to.  If
  an error occurred the first value is NIL and the second
  the unix error code."
  (with-alien ((fds (array int 2)))
    (syscall ("pipe" (* int))
	     (values (deref fds 0) (deref fds 1))
	     (cast fds (* int)))))


(defun unix-chown (path uid gid)
  _N"Given a file path, an integer user-id, and an integer group-id,
   unix-chown changes the owner of the file and the group of the
   file to those specified.  Either the owner or the group may be
   left unchanged by specifying them as -1.  Note: Permission will
   fail if the caller is not the superuser."
  (declare (type unix-pathname path)
	   (type (or unix-uid (integer -1 -1)) uid)
	   (type (or unix-gid (integer -1 -1)) gid))
  (void-syscall ("chown" c-string int int) (%name->file path) uid gid))

;;; Unix-fchown is exactly the same as unix-chown except that the file
;;; is specified by a file-descriptor ("fd") instead of a pathname.

(defun unix-fchown (fd uid gid)
  _N"Unix-fchown is like unix-chown, except that it accepts an integer
   file descriptor instead of a file path name."
  (declare (type unix-fd fd)
	   (type (or unix-uid (integer -1 -1)) uid)
	   (type (or unix-gid (integer -1 -1)) gid))
  (void-syscall ("fchown" int int int) fd uid gid))

;;; Unix-chdir accepts a directory name and makes that the
;;; current working directory.

(defun unix-chdir (path)
  _N"Given a file path string, unix-chdir changes the current working 
   directory to the one specified."
  (declare (type unix-pathname path))
  (void-syscall ("chdir" c-string) (%name->file path)))

(defun unix-current-directory ()
  _N"Put the absolute pathname of the current working directory in BUF.
   If successful, return BUF.  If not, put an error message in
   BUF and return NULL.  BUF should be at least PATH_MAX bytes long."
  ;; 5120 is some randomly selected maximum size for the buffer for getcwd.
  (with-alien ((buf (array c-call:char 5120)))
    (let ((result (alien-funcall
		    (extern-alien "getcwd"
				  (function (* c-call:char)
					    (* c-call:char) c-call:int))
		    (cast buf (* c-call:char))
		    5120)))
      
      (values (not (zerop (sap-int (alien-sap result))))
	      (%file->name (cast buf c-call:c-string))))))


;;; Unix-dup returns a duplicate copy of the existing file-descriptor
;;; passed as an argument.

(defun unix-dup (fd)
  _N"Unix-dup duplicates an existing file descriptor (given as the
   argument) and return it.  If FD is not a valid file descriptor, NIL
   and an error number are returned."
  (declare (type unix-fd fd))
  (int-syscall ("dup" int) fd))

;;; Unix-dup2 makes the second file-descriptor describe the same file
;;; as the first. If the second file-descriptor points to an open
;;; file, it is first closed. In any case, the second should have a 
;;; value which is a valid file-descriptor.

(defun unix-dup2 (fd1 fd2)
  _N"Unix-dup2 duplicates an existing file descriptor just as unix-dup
   does only the new value of the duplicate descriptor may be requested
   through the second argument.  If a file already exists with the
   requested descriptor number, it will be closed and the number
   assigned to the duplicate."
  (declare (type unix-fd fd1 fd2))
  (void-syscall ("dup2" int int) fd1 fd2))

;;; Unix-exit terminates a program.

(defun unix-exit (&optional (code 0))
  _N"Unix-exit terminates the current process with an optional
   error code.  If successful, the call doesn't return.  If
   unsuccessful, the call returns NIL and an error number."
  (declare (type (signed-byte 32) code))
  (void-syscall ("exit" int) code))

#+(or)
(defun unix-pathconf (path name)
  _N"Get file-specific configuration information about PATH."
  (int-syscall ("pathconf" c-string int) (%name->file path) name))

#+(or)
(defun unix-sysconf (name)
  _N"Get the value of the system variable NAME."
  (int-syscall ("sysconf" int) name))

#+(or)
(defun unix-confstr (name)
  _N"Get the value of the string-valued system variable NAME."
  (with-alien ((buf (array char 1024)))
    (values (not (zerop (alien-funcall (extern-alien "confstr"
						     (function int
							       c-string
							       size-t))
				       name buf 1024)))
	    (cast buf c-string))))


(def-alien-routine ("getpid" unix-getpid) int
  _N"Unix-getpid returns the process-id of the current process.")

(def-alien-routine ("getppid" unix-getppid) int
  _N"Unix-getppid returns the process-id of the parent of the current process.")

;;; Unix-getpgrp returns the group-id associated with the
;;; current process.

(defun unix-getpgrp ()
  _N"Unix-getpgrp returns the group-id of the calling process."
  (int-syscall ("getpgrp")))

;;; Unix-setpgid sets the group-id of the process specified by 
;;; "pid" to the value of "pgrp".  The process must either have
;;; the same effective user-id or be a super-user process.

;;; setpgrp(int int)[freebsd] is identical to setpgid and is retained
;;; for backward compatibility. setpgrp(void)[solaris] is being phased
;;; out in favor of setsid().

(defun unix-setpgrp (pid pgrp)
  _N"Unix-setpgrp sets the process group on the process pid to
   pgrp.  NIL and an error number are returned upon failure."
  (void-syscall ("setpgid" int int) pid pgrp))

(defun unix-setpgid (pid pgrp)
  _N"Unix-setpgid sets the process group of the process pid to
   pgrp. If pgid is equal to pid, the process becomes a process
   group leader. NIL and an error number are returned upon failure."
  (void-syscall ("setpgid" int int) pid pgrp))

#+(or)
(defun unix-setsid ()
  _N"Create a new session with the calling process as its leader.
   The process group IDs of the session and the calling process
   are set to the process ID of the calling process, which is returned."
  (void-syscall ( "setsid")))

#+(or)
(defun unix-getsid ()
  _N"Return the session ID of the given process."
  (int-syscall ( "getsid")))

(def-alien-routine ("getuid" unix-getuid) int
  _N"Unix-getuid returns the real user-id associated with the
   current process.")

#+(or)
(def-alien-routine ("geteuid" unix-getuid) int
  _N"Get the effective user ID of the calling process.")

(def-alien-routine ("getgid" unix-getgid) int
  _N"Unix-getgid returns the real group-id of the current process.")

(def-alien-routine ("getegid" unix-getegid) int
  _N"Unix-getegid returns the effective group-id of the current process.")

;/* If SIZE is zero, return the number of supplementary groups
;   the calling process is in.  Otherwise, fill in the group IDs
;   of its supplementary groups in LIST and return the number written.  */
;extern int getgroups __P ((int __size, __gid_t __list[]));

#+(or)
(defun unix-group-member (gid)
  _N"Return nonzero iff the calling process is in group GID."
  (int-syscall ( "group-member" gid-t) gid))


(defun unix-setuid (uid)
  _N"Set the user ID of the calling process to UID.
   If the calling process is the super-user, set the real
   and effective user IDs, and the saved set-user-ID to UID;
   if not, the effective user ID is set to UID."
  (int-syscall ("setuid" uid-t) uid))

;;; Unix-setreuid sets the real and effective user-id's of the current
;;; process to the arguments "ruid" and "euid", respectively.  Usage is
;;; restricted for anyone but the super-user.  Setting either "ruid" or
;;; "euid" to -1 makes the system use the current id instead.

(defun unix-setreuid (ruid euid)
  _N"Unix-setreuid sets the real and effective user-id's of the current
   process to the specified ones.  NIL and an error number is returned
   if the call fails."
  (void-syscall ("setreuid" int int) ruid euid))

(defun unix-setgid (gid)
  _N"Set the group ID of the calling process to GID.
   If the calling process is the super-user, set the real
   and effective group IDs, and the saved set-group-ID to GID;
   if not, the effective group ID is set to GID."
  (int-syscall ("setgid" gid-t) gid))


;;; Unix-setregid sets the real and effective group-id's of the current
;;; process to the arguments "rgid" and "egid", respectively.  Usage is
;;; restricted for anyone but the super-user.  Setting either "rgid" or
;;; "egid" to -1 makes the system use the current id instead.

(defun unix-setregid (rgid egid)
  _N"Unix-setregid sets the real and effective group-id's of the current
   process process to the specified ones.  NIL and an error number is
   returned if the call fails."
  (void-syscall ("setregid" int int) rgid egid))

(defun unix-fork ()
  _N"Executes the unix fork system call.  Returns 0 in the child and the pid
   of the child in the parent if it works, or NIL and an error number if it
   doesn't work."
  (int-syscall ("fork")))

;; Environment maninpulation; man getenv(3)
(def-alien-routine ("getenv" unix-getenv) c-call:c-string
  (name c-call:c-string) 
  _N"Get the value of the environment variable named Name.  If no such
  variable exists, Nil is returned.")

(def-alien-routine ("setenv" unix-setenv) c-call:int
  (name c-call:c-string)
  (value c-call:c-string)
  (overwrite c-call:int)
  _N"Adds the environment variable named Name to the environment with
  the given Value if Name does not already exist. If Name does exist,
  the value is changed to Value if Overwrite is non-zero.  Otherwise,
  the value is not changed.")

(def-alien-routine ("putenv" unix-putenv) c-call:int
  (name c-call:c-string)
  _N"Adds or changes the environment.  Name-value must be a string of
  the form \"name=value\".  If the name does not exist, it is added.
  If name does exist, the value is updated to the given value.")

(def-alien-routine ("unsetenv" unix-unsetenv) c-call:int
  (name c-call:c-string)
  _N"Removes the variable Name from the environment")

(def-alien-routine ("ttyname" unix-ttyname) c-string
  (fd int))

(def-alien-routine ("isatty" unix-isatty) boolean
  _N"Accepts a Unix file descriptor and returns T if the device
  associated with it is a terminal."
  (fd int))

;;; Unix-link creates a hard link from name2 to name1.

(defun unix-link (name1 name2)
  _N"Unix-link creates a hard link from the file with name1 to the
   file with name2."
  (declare (type unix-pathname name1 name2))
  (void-syscall ("link" c-string c-string)
		(%name->file name1) (%name->file name2)))

(defun unix-symlink (name1 name2)
  _N"Unix-symlink creates a symbolic link named name2 to the file
   named name1.  NIL and an error number is returned if the call
   is unsuccessful."
  (declare (type unix-pathname name1 name2))
  (void-syscall ("symlink" c-string c-string)
		(%name->file name1) (%name->file name2)))

(defun unix-readlink (path)
  _N"Unix-readlink invokes the readlink system call on the file name
  specified by the simple string path.  It returns up to two values:
  the contents of the symbolic link if the call is successful, or
  NIL and the Unix error number."
  (declare (type unix-pathname path))
  (with-alien ((buf (array char 1024)))
    (syscall ("readlink" c-string (* char) int)
	     (let ((string (make-string result)))
	       #-unicode
	       (kernel:copy-from-system-area
		(alien-sap buf) 0
		string (* vm:vector-data-offset vm:word-bits)
		(* result vm:byte-bits))
	       #+unicode
	       (let ((sap (alien-sap buf)))
		 (dotimes (k result)
		   (setf (aref string k) (code-char (sap-ref-8 sap k)))))
	       (%file->name string))
	     (%name->file path) (cast buf (* char)) 1024)))

;;; Unix-unlink accepts a name and deletes the directory entry for that
;;; name and the file if this is the last link.

(defun unix-unlink (name)
  _N"Unix-unlink removes the directory entry for the named file.
   NIL and an error code is returned if the call fails."
  (declare (type unix-pathname name))
  (void-syscall ("unlink" c-string) (%name->file name)))

;;; Unix-rmdir accepts a name and removes the associated directory.

(defun unix-rmdir (name)
  _N"Unix-rmdir attempts to remove the directory name.  NIL and
   an error number is returned if an error occured."
  (declare (type unix-pathname name))
  (void-syscall ("rmdir" c-string) (%name->file name)))

(defun tcgetpgrp (fd)
  _N"Get the tty-process-group for the unix file-descriptor FD."
  (alien:with-alien ((alien-pgrp c-call:int))
    (multiple-value-bind (ok err)
	(unix-ioctl fd
		     tiocgpgrp
		     (alien:alien-sap (alien:addr alien-pgrp)))
      (if ok
	  (values alien-pgrp nil)
	  (values nil err)))))

(defun tty-process-group (&optional fd)
  _N"Get the tty-process-group for the unix file-descriptor FD.  If not supplied,
  FD defaults to /dev/tty."
  (if fd
      (tcgetpgrp fd)
      (multiple-value-bind (tty-fd errno)
	  (unix-open "/dev/tty" o_rdwr 0)
	(cond (tty-fd
	       (multiple-value-prog1
		   (tcgetpgrp tty-fd)
		 (unix-close tty-fd)))
	      (t
	       (values nil errno))))))

(defun tcsetpgrp (fd pgrp)
  _N"Set the tty-process-group for the unix file-descriptor FD to PGRP."
  (alien:with-alien ((alien-pgrp c-call:int pgrp))
    (unix-ioctl fd
		tiocspgrp
		(alien:alien-sap (alien:addr alien-pgrp)))))

(defun %set-tty-process-group (pgrp &optional fd)
  _N"Set the tty-process-group for the unix file-descriptor FD to PGRP.  If not
  supplied, FD defaults to /dev/tty."
  (let ((old-sigs
	 (unix-sigblock
	  (sigmask :sigttou :sigttin :sigtstp :sigchld))))
    (declare (type (unsigned-byte 32) old-sigs))
    (unwind-protect
	(if fd
	    (tcsetpgrp fd pgrp)
	    (multiple-value-bind (tty-fd errno)
		(unix-open "/dev/tty" o_rdwr 0)
	      (cond (tty-fd
		     (multiple-value-prog1
			 (tcsetpgrp tty-fd pgrp)
		       (unix-close tty-fd)))
		    (t
		     (values nil errno)))))
      (unix-sigsetmask old-sigs))))
  
(defsetf tty-process-group (&optional fd) (pgrp)
  _N"Set the tty-process-group for the unix file-descriptor FD to PGRP.  If not
  supplied, FD defaults to /dev/tty."
  `(%set-tty-process-group ,pgrp ,fd))

#+(or)
(defun unix-getlogin ()
  _N"Return the login name of the user."
    (let ((result (alien-funcall (extern-alien "getlogin"
					     (function c-string)))))
    (declare (type system-area-pointer result))
    (if (zerop (sap-int result))
	nil
      result)))

(def-alien-type nil
  (struct utsname
    (sysname (array char 65))
    (nodename (array char 65))
    (release (array char 65))
    (version (array char 65))
    (machine (array char 65))
    (domainname (array char 65))))

(defun unix-uname ()
  _N"Unix-uname returns the name and information about the current kernel. The
  values returned upon success are: sysname, nodename, release, version,
  machine, and domainname. Upon failure, 'nil and the 'errno are returned."
  (with-alien ((utsname (struct utsname)))
    (syscall* ("uname" (* (struct utsname)))
	      (values (cast (slot utsname 'sysname) c-string)
		      (cast (slot utsname 'nodename) c-string)
		      (cast (slot utsname 'release) c-string)
		      (cast (slot utsname 'version) c-string)
		      (cast (slot utsname 'machine) c-string)
		     (cast (slot utsname 'domainname) c-string))
	      (addr utsname))))

(defun unix-gethostname ()
  _N"Unix-gethostname returns the name of the host machine as a string."
  (with-alien ((buf (array char 256)))
    (syscall* ("gethostname" (* char) int)
	      (cast buf c-string)
	      (cast buf (* char)) 256)))

#+(or)
(defun unix-sethostname (name len)
  (int-syscall ("sethostname" c-string size-t) name len))

#+(or)
(defun unix-sethostid (id)
  (int-syscall ("sethostid" long) id))

#+(or)
(defun unix-getdomainname (name len)
  (int-syscall ("getdomainname" c-string size-t) name len))

#+(or)
(defun unix-setdomainname (name len)
  (int-syscall ("setdomainname" c-string size-t) name len))

;;; Unix-fsync writes the core-image of the file described by "fd" to
;;; permanent storage (i.e. disk).

(defun unix-fsync (fd)
  _N"Unix-fsync writes the core image of the file described by
   fd to disk."
  (declare (type unix-fd fd))
  (void-syscall ("fsync" int) fd))


#+(or)
(defun unix-vhangup ()
 _N"Revoke access permissions to all processes currently communicating
  with the control terminal, and then send a SIGHUP signal to the process
  group of the control terminal." 
 (int-syscall ("vhangup")))

#+(or)
(defun unix-revoke (file)
 _N"Revoke the access of all descriptors currently open on FILE."
 (int-syscall ("revoke" c-string) (%name->file file)))


#+(or)
(defun unix-chroot (path)
 _N"Make PATH be the root directory (the starting point for absolute paths).
   This call is restricted to the super-user."
 (int-syscall ("chroot" c-string) (%name->file path)))

(def-alien-routine ("gethostid" unix-gethostid) unsigned-long
  _N"Unix-gethostid returns a 32-bit integer which provides unique
   identification for the host machine.")

;;; Unix-sync writes all information in core memory which has been modified
;;; to permanent storage (i.e. disk).

(defun unix-sync ()
  _N"Unix-sync writes all information in core memory which has been
   modified to disk.  It returns NIL and an error code if an error
   occured."
  (void-syscall ("sync")))

;;; Unix-getpagesize returns the number of bytes in the system page.

(defun unix-getpagesize ()
  _N"Unix-getpagesize returns the number of bytes in a system page."
  (int-syscall ("getpagesize")))

;;; Unix-truncate accepts a file name and a new length.  The file is
;;; truncated to the new length.

(defun unix-truncate (name length)
  _N"Unix-truncate truncates the named file to the length (in
   bytes) specified by LENGTH.  NIL and an error number is returned
   if the call is unsuccessful."
  (declare (type unix-pathname name)
	   (type (unsigned-byte 64) length))
  (void-syscall ("truncate64" c-string off-t) (%name->file name) length))

(defun unix-ftruncate (fd length)
  _N"Unix-ftruncate is similar to unix-truncate except that the first
   argument is a file descriptor rather than a file name."
  (declare (type unix-fd fd)
	   (type (unsigned-byte 64) length))
  (void-syscall ("ftruncate64" int off-t) fd length))

#+(or)
(defun unix-getdtablesize ()
  _N"Return the maximum number of file descriptors
   the current process could possibly have."
  (int-syscall ("getdtablesize")))

(defconstant f_ulock 0 _N"Unlock a locked region")
(defconstant f_lock 1 _N"Lock a region for exclusive use")
(defconstant f_tlock 2 _N"Test and lock a region for exclusive use")
(defconstant f_test 3 _N"Test a region for othwer processes locks")

(defun unix-lockf (fd cmd length)
  _N"Unix-locks can lock, unlock and test files according to the cmd
   which can be one of the following:

   f_ulock  Unlock a locked region
   f_lock   Lock a region for exclusive use
   f_tlock  Test and lock a region for exclusive use
   f_test   Test a region for othwer processes locks

   The lock is for a region from the current location for a length
   of length.

   This is a simpler version of the interface provided by unix-fcntl.
   "
  (declare (type unix-fd fd)
	   (type (unsigned-byte 64) length)
	   (type (integer 0 3) cmd))
  (int-syscall ("lockf64" int int off-t) fd cmd length))

;;; utime.h

;; Structure describing file times.

(def-alien-type nil
    (struct utimbuf
	    (actime time-t) ; Access time. 
	    (modtime time-t))) ; Modification time.

;;; Unix-utimes changes the accessed and updated times on UNIX
;;; files.  The first argument is the filename (a string) and
;;; the second argument is a list of the 4 times- accessed and
;;; updated seconds and microseconds.

(defun unix-utimes (file atime-sec atime-usec mtime-sec mtime-usec)
  _N"Unix-utimes sets the 'last-accessed' and 'last-updated'
   times on a specified file.  NIL and an error number is
   returned if the call is unsuccessful."
  (declare (type unix-pathname file)
	   (type (alien unsigned-long)
		 atime-sec atime-usec
		 mtime-sec mtime-usec))
  (with-alien ((tvp (array (struct timeval) 2)))
    (setf (slot (deref tvp 0) 'tv-sec) atime-sec)
    (setf (slot (deref tvp 0) 'tv-usec) atime-usec)
    (setf (slot (deref tvp 1) 'tv-sec) mtime-sec)
    (setf (slot (deref tvp 1) 'tv-usec) mtime-usec)
    (void-syscall ("utimes" c-string (* (struct timeval)))
		  file
		  (cast tvp (* (struct timeval))))))
;;; waitflags.h

;; Bits in the third argument to `waitpid'.

(defconstant waitpid-wnohang 1 _N"Don't block waiting.")
(defconstant waitpid-wuntranced 2 _N"Report status of stopped children.")

(defconstant waitpid-wclone #x80000000 _N"Wait for cloned process.")

;;; sys/ioctl.h

(defun unix-ioctl (fd cmd arg)
  _N"Unix-ioctl performs a variety of operations on open i/o
   descriptors.  See the UNIX Programmer's Manual for more
   information."
  (declare (type unix-fd fd)
	   (type (unsigned-byte 32) cmd))
  (int-syscall ("ioctl" int unsigned-int (* char)) fd cmd arg))


;;; sys/fsuid.h

#+(or)
(defun unix-setfsuid (uid)
  _N"Change uid used for file access control to UID, without affecting
   other priveledges (such as who can send signals at the process)."
  (int-syscall ("setfsuid" uid-t) uid))

#+(or)
(defun unix-setfsgid (gid)
  _N"Change gid used for file access control to GID, without affecting
   other priveledges (such as who can send signals at the process)."
  (int-syscall ("setfsgid" gid-t) gid))

;;; sys/poll.h

;; Data structure describing a polling request.

(def-alien-type nil
    (struct pollfd
	    (fd int)       ; File descriptor to poll.
	    (events short) ; Types of events poller cares about.
	    (revents short))) ; Types of events that actually occurred.

;; Event types that can be polled for.  These bits may be set in `events'
;; to indicate the interesting event types; they will appear in `revents'
;; to indicate the status of the file descriptor.  

(defconstant POLLIN  #o1 _N"There is data to read.")
(defconstant POLLPRI #o2 _N"There is urgent data to read.")
(defconstant POLLOUT #o4 _N"Writing now will not block.")

;; Event types always implicitly polled for.  These bits need not be set in
;;`events', but they will appear in `revents' to indicate the status of
;; the file descriptor.  */


(defconstant POLLERR  #o10 _N"Error condition.")
(defconstant POLLHUP  #o20 _N"Hung up.")
(defconstant POLLNVAL #o40 _N"Invalid polling request.")


(defconstant +npollfile+ 30 _N"Canonical number of polling requests to read
in at a time in poll.")

#+(or)
(defun unix-poll (fds nfds timeout)
 _N" Poll the file descriptors described by the NFDS structures starting at
   FDS.  If TIMEOUT is nonzero and not -1, allow TIMEOUT milliseconds for
   an event to occur; if TIMEOUT is -1, block until an event occurs.
   Returns the number of file descriptors with events, zero if timed out,
   or -1 for errors."
 (int-syscall ("poll" (* (struct pollfd)) long int)
	      fds nfds timeout))

;;; sys/resource.h

(defun unix-getrlimit (resource)
  _N"Get the soft and hard limits for RESOURCE."
  (with-alien ((rlimits (struct rlimit)))
    (syscall ("getrlimit" int (* (struct rlimit)))
	     (values t
		     (slot rlimits 'rlim-cur)
		     (slot rlimits 'rlim-max))
	     resource (addr rlimits))))

(defun unix-setrlimit (resource current maximum)
  _N"Set the current soft and hard maximum limits for RESOURCE.
   Only the super-user can increase hard limits."
  (with-alien ((rlimits (struct rlimit)))
    (setf (slot rlimits 'rlim-cur) current)
    (setf (slot rlimits 'rlim-max) maximum)
    (void-syscall ("setrlimit" int (* (struct rlimit)))
		  resource (addr rlimits))))

(declaim (inline unix-fast-getrusage))
(defun unix-fast-getrusage (who)
  _N"Like call getrusage, but return only the system and user time, and returns
   the seconds and microseconds as separate values."
  (declare (values (member t)
		   (unsigned-byte 31) (mod 1000000)
		   (unsigned-byte 31) (mod 1000000)))
  (with-alien ((usage (struct rusage)))
    (syscall* ("getrusage" int (* (struct rusage)))
	      (values t
		      (slot (slot usage 'ru-utime) 'tv-sec)
		      (slot (slot usage 'ru-utime) 'tv-usec)
		      (slot (slot usage 'ru-stime) 'tv-sec)
		      (slot (slot usage 'ru-stime) 'tv-usec))
	      who (addr usage))))

(defun unix-getrusage (who)
  _N"Unix-getrusage returns information about the resource usage
   of the process specified by who.  Who can be either the
   current process (rusage_self) or all of the terminated
   child processes (rusage_children).  NIL and an error number
   is returned if the call fails."
  (with-alien ((usage (struct rusage)))
    (syscall ("getrusage" int (* (struct rusage)))
	      (values t
		      (+ (* (slot (slot usage 'ru-utime) 'tv-sec) 1000000)
			 (slot (slot usage 'ru-utime) 'tv-usec))
		      (+ (* (slot (slot usage 'ru-stime) 'tv-sec) 1000000)
			 (slot (slot usage 'ru-stime) 'tv-usec))
		      (slot usage 'ru-maxrss)
		      (slot usage 'ru-ixrss)
		      (slot usage 'ru-idrss)
		      (slot usage 'ru-isrss)
		      (slot usage 'ru-minflt)
		      (slot usage 'ru-majflt)
		      (slot usage 'ru-nswap)
		      (slot usage 'ru-inblock)
		      (slot usage 'ru-oublock)
		      (slot usage 'ru-msgsnd)
		      (slot usage 'ru-msgrcv)
		      (slot usage 'ru-nsignals)
		      (slot usage 'ru-nvcsw)
		      (slot usage 'ru-nivcsw))
	      who (addr usage))))

#+(or)
(defun unix-ulimit (cmd newlimit)
 _N"Function depends on CMD:
  1 = Return the limit on the size of a file, in units of 512 bytes.
  2 = Set the limit on the size of a file to NEWLIMIT.  Only the
      super-user can increase the limit.
  3 = Return the maximum possible address of the data segment.
  4 = Return the maximum number of files that the calling process can open.
  Returns -1 on errors."
 (int-syscall ("ulimit" int long) cmd newlimit))

#+(or)
(defun unix-getpriority (which who)
  _N"Return the highest priority of any process specified by WHICH and WHO
   (see above); if WHO is zero, the current process, process group, or user
   (as specified by WHO) is used.  A lower priority number means higher
   priority.  Priorities range from PRIO_MIN to PRIO_MAX (above)."
  (int-syscall ("getpriority" int int)
	       which who))

#+(or)
(defun unix-setpriority (which who)
  _N"Set the priority of all processes specified by WHICH and WHO (see above)
   to PRIO.  Returns 0 on success, -1 on errors."
  (int-syscall ("setpriority" int int)
	       which who))

;;; sys/socket.h

;;;; Socket support.

;;; Looks a bit naked.

(def-alien-routine ("socket" unix-socket) int
  (domain int)
  (type int)
  (protocol int))

(def-alien-routine ("connect" unix-connect) int
  (socket int)
  (sockaddr (* t))
  (len int))

(def-alien-routine ("bind" unix-bind) int
  (socket int)
  (sockaddr (* t))
  (len int))

(def-alien-routine ("listen" unix-listen) int
  (socket int)
  (backlog int))

(def-alien-routine ("accept" unix-accept) int
  (socket int)
  (sockaddr (* t))
  (len int :in-out))

(def-alien-routine ("recv" unix-recv) int
  (fd int)
  (buffer c-string)
  (length int)
  (flags int))

(def-alien-routine ("send" unix-send) int
  (fd int)
  (buffer c-string)
  (length int)
  (flags int))

(def-alien-routine ("getpeername" unix-getpeername) int
  (socket int)
  (sockaddr (* t))
  (len (* unsigned)))

(def-alien-routine ("getsockname" unix-getsockname) int
  (socket int)
  (sockaddr (* t))
  (len (* unsigned)))

(def-alien-routine ("getsockopt" unix-getsockopt) int
  (socket int)
  (level int)
  (optname int)
  (optval (* t))
  (optlen unsigned :in-out))

(def-alien-routine ("setsockopt" unix-setsockopt) int
  (socket int)
  (level int)
  (optname int)
  (optval (* t))
  (optlen unsigned))

;; Datagram support

(def-alien-routine ("recvfrom" unix-recvfrom) int
  (fd int)
  (buffer c-string)
  (length int)
  (flags int)
  (sockaddr (* t))
  (len int :in-out))

(def-alien-routine ("sendto" unix-sendto) int
  (fd int)
  (buffer c-string)
  (length int)
  (flags int)
  (sockaddr (* t))
  (len int))

(def-alien-routine ("shutdown" unix-shutdown) int
  (socket int)
  (level int))

;;; sys/select.h

;;; UNIX-FAST-SELECT -- public.
;;;
(defmacro unix-fast-select (num-descriptors
			    read-fds write-fds exception-fds
			    timeout-secs &optional (timeout-usecs 0))
  _N"Perform the UNIX select(2) system call."
  (declare (type (integer 0 #.FD-SETSIZE) num-descriptors) 
	   (type (or (alien (* (struct fd-set))) null) 
		 read-fds write-fds exception-fds) 
	   (type (or null (unsigned-byte 31)) timeout-secs) 
	   (type (unsigned-byte 31) timeout-usecs) 
	   (optimize (speed 3) (safety 0) (inhibit-warnings 3)))
  `(let ((timeout-secs ,timeout-secs))
     (with-alien ((tv (struct timeval)))
       (when timeout-secs
	 (setf (slot tv 'tv-sec) timeout-secs)
	 (setf (slot tv 'tv-usec) ,timeout-usecs))
       (int-syscall ("select" int (* (struct fd-set)) (* (struct fd-set))
		     (* (struct fd-set)) (* (struct timeval)))
		    ,num-descriptors ,read-fds ,write-fds ,exception-fds
		    (if timeout-secs (alien-sap (addr tv)) (int-sap 0))))))


;;; Unix-select accepts sets of file descriptors and waits for an event
;;; to happen on one of them or to time out.

(defmacro num-to-fd-set (fdset num)
  `(if (fixnump ,num)
       (progn
	 (setf (deref (slot ,fdset 'fds-bits) 0) ,num)
	 ,@(loop for index upfrom 1 below (/ fd-setsize nfdbits)
	     collect `(setf (deref (slot ,fdset 'fds-bits) ,index) 0)))
       (progn
	 ,@(loop for index upfrom 0 below (/ fd-setsize nfdbits)
	     collect `(setf (deref (slot ,fdset 'fds-bits) ,index)
			    (ldb (byte nfdbits ,(* index nfdbits)) ,num))))))

(defmacro fd-set-to-num (nfds fdset)
  `(if (<= ,nfds nfdbits)
       (deref (slot ,fdset 'fds-bits) 0)
       (+ ,@(loop for index upfrom 0 below (/ fd-setsize nfdbits)
	      collect `(ash (deref (slot ,fdset 'fds-bits) ,index)
			    ,(* index nfdbits))))))

(defun unix-select (nfds rdfds wrfds xpfds to-secs &optional (to-usecs 0))
  _N"Unix-select examines the sets of descriptors passed as arguments
   to see if they are ready for reading and writing.  See the UNIX
   Programmers Manual for more information."
  (declare (type (integer 0 #.FD-SETSIZE) nfds)
	   (type unsigned-byte rdfds wrfds xpfds)
	   (type (or (unsigned-byte 31) null) to-secs)
	   (type (unsigned-byte 31) to-usecs)
	   (optimize (speed 3) (safety 0) (inhibit-warnings 3)))
  (with-alien ((tv (struct timeval))
	       (rdf (struct fd-set))
	       (wrf (struct fd-set))
	       (xpf (struct fd-set)))
    (when to-secs
      (setf (slot tv 'tv-sec) to-secs)
      (setf (slot tv 'tv-usec) to-usecs))
    (num-to-fd-set rdf rdfds)
    (num-to-fd-set wrf wrfds)
    (num-to-fd-set xpf xpfds)
    (macrolet ((frob (lispvar alienvar)
		 `(if (zerop ,lispvar)
		      (int-sap 0)
		      (alien-sap (addr ,alienvar)))))
      (syscall ("select" int (* (struct fd-set)) (* (struct fd-set))
		(* (struct fd-set)) (* (struct timeval)))
	       (values result
		       (fd-set-to-num nfds rdf)
		       (fd-set-to-num nfds wrf)
		       (fd-set-to-num nfds xpf))
	       nfds (frob rdfds rdf) (frob wrfds wrf) (frob xpfds xpf)
	       (if to-secs (alien-sap (addr tv)) (int-sap 0))))))

;;; sys/stat.h

(defmacro extract-stat-results (buf)
  `(values T
           #+(or alpha amd64)
	   (slot ,buf 'st-dev)
           #-(or alpha amd64)
           (+ (deref (slot ,buf 'st-dev) 0)
	      (* (+ +max-u-long+  1)
	         (deref (slot ,buf 'st-dev) 1)))   ;;; let's hope this works..
	   (slot ,buf 'st-ino)
	   (slot ,buf 'st-mode)
	   (slot ,buf 'st-nlink)
	   (slot ,buf 'st-uid)
	   (slot ,buf 'st-gid)
           #+(or alpha amd64)
	   (slot ,buf 'st-rdev)
           #-(or alpha amd64)
           (+ (deref (slot ,buf 'st-rdev) 0)
	      (* (+ +max-u-long+  1)
	         (deref (slot ,buf 'st-rdev) 1)))   ;;; let's hope this works..
	   (slot ,buf 'st-size)
	   (slot ,buf 'st-atime)
	   (slot ,buf 'st-mtime)
	   (slot ,buf 'st-ctime)
	   (slot ,buf 'st-blksize)
	   (slot ,buf 'st-blocks)))

(defun unix-stat (name)
  _N"UNIX-STAT retrieves information about the specified
   file returning them in the form of multiple values.
   See the UNIX Programmer's Manual for a description
   of the values returned.  If the call fails, then NIL
   and an error number is returned instead."
  (declare (type unix-pathname name))
  (when (string= name "")
    (setf name "."))
  (with-alien ((buf (struct stat)))
    (syscall ("stat64" c-string (* (struct stat)))
	     (extract-stat-results buf)
	     (%name->file name) (addr buf))))

(defun unix-fstat (fd)
  _N"UNIX-FSTAT is similar to UNIX-STAT except the file is specified
   by the file descriptor FD."
  (declare (type unix-fd fd))
  (with-alien ((buf (struct stat)))
    (syscall ("fstat64" int (* (struct stat)))
	     (extract-stat-results buf)
	     fd (addr buf))))

(defun unix-lstat (name)
  _N"UNIX-LSTAT is similar to UNIX-STAT except the specified
   file must be a symbolic link."
  (declare (type unix-pathname name))
  (with-alien ((buf (struct stat)))
    (syscall ("lstat64" c-string (* (struct stat)))
	     (extract-stat-results buf)
	     (%name->file name) (addr buf))))

;;; Unix-chmod accepts a path and a mode and changes the mode to the new mode.

(defun unix-chmod (path mode)
  _N"Given a file path string and a constant mode, unix-chmod changes the
   permission mode for that file to the one specified. The new mode
   can be created by logically OR'ing the following:

      setuidexec        Set user ID on execution.
      setgidexec        Set group ID on execution.
      savetext          Save text image after execution.
      readown           Read by owner.
      writeown          Write by owner.
      execown           Execute (search directory) by owner.
      readgrp           Read by group.
      writegrp          Write by group.
      execgrp           Execute (search directory) by group.
      readoth           Read by others.
      writeoth          Write by others.
      execoth           Execute (search directory) by others.

  Thus #o444 and (logior unix:readown unix:readgrp unix:readoth)
  are equivalent for 'mode.  The octal-base is familar to Unix users.
  
  It returns T on successfully completion; NIL and an error number
  otherwise."
  (declare (type unix-pathname path)
	   (type unix-file-mode mode))
  (void-syscall ("chmod" c-string int) (%name->file path) mode))

;;; Unix-fchmod accepts a file descriptor ("fd") and a file protection mode
;;; ("mode") and changes the protection of the file described by "fd" to 
;;; "mode".

(defun unix-fchmod (fd mode)
  _N"Given an integer file descriptor and a mode (the same as those
   used for unix-chmod), unix-fchmod changes the permission mode
   for that file to the one specified. T is returned if the call
   was successful."
  (declare (type unix-fd fd)
	   (type unix-file-mode mode))
  (void-syscall ("fchmod" int int) fd mode))


(defun unix-umask (mask)
  _N"Set the file creation mask of the current process to MASK,
   and return the old creation mask."
  (int-syscall ("umask" mode-t) mask))

;;; Unix-mkdir accepts a name and a mode and attempts to create the
;;; corresponding directory with mode mode.

(defun unix-mkdir (name mode)
  _N"Unix-mkdir creates a new directory with the specified name and mode.
   (Same as those for unix-chmod.)  It returns T upon success, otherwise
   NIL and an error number."
  (declare (type unix-pathname name)
	   (type unix-file-mode mode))
  (void-syscall ("mkdir" c-string int) (%name->file name) mode))

#+(or)
(defun unix-makedev (path mode dev)
 _N"Create a device file named PATH, with permission and special bits MODE
  and device number DEV (which can be constructed from major and minor
  device numbers with the `makedev' macro above)."
  (declare (type unix-pathname path)
	   (type unix-file-mode mode))
  (void-syscall ("makedev" c-string mode-t dev-t) (%name->file name) mode dev))


#+(or)
(defun unix-fifo (name mode)
  _N"Create a new FIFO named PATH, with permission bits MODE."
  (declare (type unix-pathname name)
	   (type unix-file-mode mode))
  (void-syscall ("mkfifo" c-string int) (%name->file name) mode))

;;; sys/statfs.h

#+(or)
(defun unix-statfs (file buf)
  _N"Return information about the filesystem on which FILE resides."
  (int-syscall ("statfs64" c-string (* (struct statfs)))
	       (%name->file file) buf))

;;; sys/swap.h

#+(or)
(defun unix-swapon (path flags)
 _N"Make the block special device PATH available to the system for swapping.
  This call is restricted to the super-user."
 (int-syscall ("swapon" c-string int) (%name->file path) flags))

#+(or)
(defun unix-swapoff (path)
 _N"Make the block special device PATH unavailable to the system for swapping.
  This call is restricted to the super-user."
 (int-syscall ("swapoff" c-string) (%name->file path)))

;;; sys/sysctl.h

#+(or)
(defun unix-sysctl (name nlen oldval oldlenp newval newlen)
  _N"Read or write system parameters."
  (int-syscall ("sysctl" int int (* void) (* void) (* void) size-t)
	       name nlen oldval oldlenp newval newlen))

;;; time.h

;; POSIX.4 structure for a time value.  This is like a `struct timeval' but
;; has nanoseconds instead of microseconds.

(def-alien-type nil
    (struct timespec
	    (tv-sec long)   ;Seconds
	    (tv-nsec long))) ;Nanoseconds

;; Used by other time functions. 

(def-alien-type nil
    (struct tm
	    (tm-sec int)   ; Seconds.	[0-60] (1 leap second)
	    (tm-min int)   ; Minutes.	[0-59]
	    (tm-hour int)  ; Hours.	[0-23]
	    (tm-mday int)  ; Day.		[1-31]
	    (tm-mon int)   ;  Month.	[0-11]
	    (tm-year int)  ; Year	- 1900.
	    (tm-wday int)  ; Day of week.	[0-6]
	    (tm-yday int)  ; Days in year.[0-365]
	    (tm-isdst int) ;  DST.		[-1/0/1]
	    (tm-gmtoff long) ;  Seconds east of UTC.
	    (tm-zone c-string))) ; Timezone abbreviation.  

#+(or)
(defun unix-clock ()
  _N"Time used by the program so far (user time + system time).
   The result / CLOCKS_PER_SECOND is program time in seconds."
  (int-syscall ("clock")))

#+(or)
(defun unix-time (timer)
  _N"Return the current time and put it in *TIMER if TIMER is not NULL."
  (int-syscall ("time" time-t) timer))

;; Requires call to tzset() in main.

(def-alien-variable ("daylight" unix-daylight) int)
(def-alien-variable ("timezone" unix-timezone) time-t)
;(def-alien-variable ("altzone" unix-altzone) time-t) doesn't exist
(def-alien-variable ("tzname" unix-tzname) (array c-string 2))

(def-alien-routine get-timezone c-call:void
  (when c-call:long :in)
  (minutes-west c-call:int :out)
  (daylight-savings-p alien:boolean :out))

(defun unix-get-minutes-west (secs)
  (multiple-value-bind (ignore minutes dst) (get-timezone secs)
    (declare (ignore ignore) (ignore dst))
    (values minutes)))
  
(defun unix-get-timezone (secs)
  (multiple-value-bind (ignore minutes dst) (get-timezone secs)
    (declare (ignore ignore) (ignore minutes))
    (values (deref unix-tzname (if dst 1 0)))))

;;; sys/time.h

;; Structure crudely representing a timezone.
;;   This is obsolete and should never be used. 
(def-alien-type nil
  (struct timezone
    (tz-minuteswest int)		; minutes west of Greenwich
    (tz-dsttime	int)))			; type of dst correction
     

(declaim (inline unix-gettimeofday))
(defun unix-gettimeofday ()
  _N"If it works, unix-gettimeofday returns 5 values: T, the seconds and
   microseconds of the current time of day, the timezone (in minutes west
   of Greenwich), and a daylight-savings flag.  If it doesn't work, it
   returns NIL and the errno."
  (with-alien ((tv (struct timeval))
	       (tz (struct timezone)))
    (syscall* ("gettimeofday" (* (struct timeval)) 
			      (* (struct timezone)))
	      (values T
		      (slot tv 'tv-sec)
		      (slot tv 'tv-usec)
		      (slot tz 'tz-minuteswest)
		      (slot tz 'tz-dsttime))
	      (addr tv)
	      (addr tz))))


;/* Set the current time of day and timezone information.
;   This call is restricted to the super-user.  */
;extern int __settimeofday __P ((__const struct timeval *__tv,
;    __const struct timezone *__tz));
;extern int settimeofday __P ((__const struct timeval *__tv,
;         __const struct timezone *__tz));

;/* Adjust the current time of day by the amount in DELTA.
;   If OLDDELTA is not NULL, it is filled in with the amount
;   of time adjustment remaining to be done from the last `adjtime' call.
;   This call is restricted to the super-user.  */
;extern int __adjtime __P ((__const struct timeval *__delta,
;      struct timeval *__olddelta));
;extern int adjtime __P ((__const struct timeval *__delta,
;    struct timeval *__olddelta));


;; Type of the second argument to `getitimer' and
;; the second and third arguments `setitimer'. 
(def-alien-type nil
  (struct itimerval
    (it-interval (struct timeval))	; timer interval
    (it-value (struct timeval))))	; current value

(defconstant ITIMER-REAL 0)
(defconstant ITIMER-VIRTUAL 1)
(defconstant ITIMER-PROF 2)

(defun unix-getitimer (which)
  _N"Unix-getitimer returns the INTERVAL and VALUE slots of one of
   three system timers (:real :virtual or :profile). On success,
   unix-getitimer returns 5 values,
   T, it-interval-secs, it-interval-usec, it-value-secs, it-value-usec."
  (declare (type (member :real :virtual :profile) which)
	   (values t
		   (unsigned-byte 29)(mod 1000000)
		   (unsigned-byte 29)(mod 1000000)))
  (let ((which (ecase which
		 (:real ITIMER-REAL)
		 (:virtual ITIMER-VIRTUAL)
		 (:profile ITIMER-PROF))))
    (with-alien ((itv (struct itimerval)))
      (syscall* ("getitimer" int (* (struct itimerval)))
		(values T
			(slot (slot itv 'it-interval) 'tv-sec)
			(slot (slot itv 'it-interval) 'tv-usec)
			(slot (slot itv 'it-value) 'tv-sec)
			(slot (slot itv 'it-value) 'tv-usec))
		which (alien-sap (addr itv))))))

(defun unix-setitimer (which int-secs int-usec val-secs val-usec)
  _N" Unix-setitimer sets the INTERVAL and VALUE slots of one of
   three system timers (:real :virtual or :profile). A SIGALRM signal
   will be delivered VALUE <seconds+microseconds> from now. INTERVAL,
   when non-zero, is <seconds+microseconds> to be loaded each time
   the timer expires. Setting INTERVAL and VALUE to zero disables
   the timer. See the Unix man page for more details. On success,
   unix-setitimer returns the old contents of the INTERVAL and VALUE
   slots as in unix-getitimer."
  (declare (type (member :real :virtual :profile) which)
	   (type (unsigned-byte 29) int-secs val-secs)
	   (type (integer 0 (1000000)) int-usec val-usec)
	   (values t
		   (unsigned-byte 29)(mod 1000000)
		   (unsigned-byte 29)(mod 1000000)))
  (let ((which (ecase which
		 (:real ITIMER-REAL)
		 (:virtual ITIMER-VIRTUAL)
		 (:profile ITIMER-PROF))))
    (with-alien ((itvn (struct itimerval))
		 (itvo (struct itimerval)))
      (setf (slot (slot itvn 'it-interval) 'tv-sec ) int-secs
	    (slot (slot itvn 'it-interval) 'tv-usec) int-usec
	    (slot (slot itvn 'it-value   ) 'tv-sec ) val-secs
	    (slot (slot itvn 'it-value   ) 'tv-usec) val-usec)
      (syscall* ("setitimer" int (* (struct timeval))(* (struct timeval)))
		(values T
			(slot (slot itvo 'it-interval) 'tv-sec)
			(slot (slot itvo 'it-interval) 'tv-usec)
			(slot (slot itvo 'it-value) 'tv-sec)
			(slot (slot itvo 'it-value) 'tv-usec))
		which (alien-sap (addr itvn))(alien-sap (addr itvo))))))

;;; sys/timeb.h

;; Structure returned by the `ftime' function.

(def-alien-type nil
    (struct timeb
	    (time time-t)      ; Seconds since epoch, as from `time'.
	    (millitm short)    ; Additional milliseconds.
	    (timezone int)     ; Minutes west of GMT.
	    (dstflag short)))  ; Nonzero if Daylight Savings Time used. 

#+(or)
(defun unix-fstime (timebuf)
  _N"Fill in TIMEBUF with information about the current time."
  (int-syscall ("ftime" (* (struct timeb))) timebuf))


;;; sys/times.h

;; Structure describing CPU time used by a process and its children.

(def-alien-type nil
    (struct tms
	    (tms-utime clock-t) ; User CPU time.
	    (tms-stime clock-t) ; System CPU time.
	    (tms-cutime clock-t) ; User CPU time of dead children.
	    (tms-cstime clock-t))) ; System CPU time of dead children.

#+(or)
(defun unix-times (buffer)
  _N"Store the CPU time used by this process and all its
   dead children (and their dead children) in BUFFER.
   Return the elapsed real time, or (clock_t) -1 for errors.
   All times are in CLK_TCKths of a second."
  (int-syscall ("times" (* (struct tms))) buffer))

;;; sys/wait.h

#+(or)
(defun unix-wait (status)
  _N"Wait for a child to die.  When one does, put its status in *STAT_LOC
   and return its process ID.  For errors, return (pid_t) -1."
  (int-syscall ("wait" (* int)) status))

#+(or)
(defun unix-waitpid (pid status options)
  _N"Wait for a child matching PID to die.
   If PID is greater than 0, match any process whose process ID is PID.
   If PID is (pid_t) -1, match any process.
   If PID is (pid_t) 0, match any process with the
   same process group as the current process.
   If PID is less than -1, match any process whose
   process group is the absolute value of PID.
   If the WNOHANG bit is set in OPTIONS, and that child
   is not already dead, return (pid_t) 0.  If successful,
   return PID and store the dead child's status in STAT_LOC.
   Return (pid_t) -1 for errors.  If the WUNTRACED bit is
   set in OPTIONS, return status for stopped children; otherwise don't."
  (int-syscall ("waitpit" pid-t (* int) int)
	       pid status options))

;;; asm/errno.h

(def-unix-error ESUCCESS 0 _N"Successful")
(def-unix-error EPERM 1 _N"Operation not permitted")
(def-unix-error ENOENT 2 _N"No such file or directory")
(def-unix-error ESRCH 3 _N"No such process")
(def-unix-error EINTR 4 _N"Interrupted system call")
(def-unix-error EIO 5 _N"I/O error")
(def-unix-error ENXIO 6 _N"No such device or address")
(def-unix-error E2BIG 7 _N"Arg list too long")
(def-unix-error ENOEXEC 8 _N"Exec format error")
(def-unix-error EBADF 9 _N"Bad file number")
(def-unix-error ECHILD 10 _N"No children")
(def-unix-error EAGAIN 11 _N"Try again")
(def-unix-error ENOMEM 12 _N"Out of memory")
(def-unix-error EACCES 13 _N"Permission denied")
(def-unix-error EFAULT 14 _N"Bad address")
(def-unix-error ENOTBLK 15 _N"Block device required")
(def-unix-error EBUSY 16 _N"Device or resource busy")
(def-unix-error EEXIST 17 _N"File exists")
(def-unix-error EXDEV 18 _N"Cross-device link")
(def-unix-error ENODEV 19 _N"No such device")
(def-unix-error ENOTDIR 20 _N"Not a director")
(def-unix-error EISDIR 21 _N"Is a directory")
(def-unix-error EINVAL 22 _N"Invalid argument")
(def-unix-error ENFILE 23 _N"File table overflow")
(def-unix-error EMFILE 24 _N"Too many open files")
(def-unix-error ENOTTY 25 _N"Not a typewriter")
(def-unix-error ETXTBSY 26 _N"Text file busy")
(def-unix-error EFBIG 27 _N"File too large")
(def-unix-error ENOSPC 28 _N"No space left on device")
(def-unix-error ESPIPE 29 _N"Illegal seek")
(def-unix-error EROFS 30 _N"Read-only file system")
(def-unix-error EMLINK 31 _N"Too many links")
(def-unix-error EPIPE 32 _N"Broken pipe")
;;; 
;;; Math
(def-unix-error EDOM 33 _N"Math argument out of domain")
(def-unix-error ERANGE 34 _N"Math result not representable")
;;; 
(def-unix-error  EDEADLK         35     _N"Resource deadlock would occur")
(def-unix-error  ENAMETOOLONG    36     _N"File name too long")
(def-unix-error  ENOLCK          37     _N"No record locks available")
(def-unix-error  ENOSYS          38     _N"Function not implemented")
(def-unix-error  ENOTEMPTY       39     _N"Directory not empty")
(def-unix-error  ELOOP           40     _N"Too many symbolic links encountered")
(def-unix-error  EWOULDBLOCK     11     _N"Operation would block")
(def-unix-error  ENOMSG          42     _N"No message of desired type")
(def-unix-error  EIDRM           43     _N"Identifier removed")
(def-unix-error  ECHRNG          44     _N"Channel number out of range")
(def-unix-error  EL2NSYNC        45     _N"Level 2 not synchronized")
(def-unix-error  EL3HLT          46     _N"Level 3 halted")
(def-unix-error  EL3RST          47     _N"Level 3 reset")
(def-unix-error  ELNRNG          48     _N"Link number out of range")
(def-unix-error  EUNATCH         49     _N"Protocol driver not attached")
(def-unix-error  ENOCSI          50     _N"No CSI structure available")
(def-unix-error  EL2HLT          51     _N"Level 2 halted")
(def-unix-error  EBADE           52     _N"Invalid exchange")
(def-unix-error  EBADR           53     _N"Invalid request descriptor")
(def-unix-error  EXFULL          54     _N"Exchange full")
(def-unix-error  ENOANO          55     _N"No anode")
(def-unix-error  EBADRQC         56     _N"Invalid request code")
(def-unix-error  EBADSLT         57     _N"Invalid slot")
(def-unix-error  EDEADLOCK       EDEADLK     _N"File locking deadlock error")
(def-unix-error  EBFONT          59     _N"Bad font file format")
(def-unix-error  ENOSTR          60     _N"Device not a stream")
(def-unix-error  ENODATA         61     _N"No data available")
(def-unix-error  ETIME           62     _N"Timer expired")
(def-unix-error  ENOSR           63     _N"Out of streams resources")
(def-unix-error  ENONET          64     _N"Machine is not on the network")
(def-unix-error  ENOPKG          65     _N"Package not installed")
(def-unix-error  EREMOTE         66     _N"Object is remote")
(def-unix-error  ENOLINK         67     _N"Link has been severed")
(def-unix-error  EADV            68     _N"Advertise error")
(def-unix-error  ESRMNT          69     _N"Srmount error")
(def-unix-error  ECOMM           70     _N"Communication error on send")
(def-unix-error  EPROTO          71     _N"Protocol error")
(def-unix-error  EMULTIHOP       72     _N"Multihop attempted")
(def-unix-error  EDOTDOT         73     _N"RFS specific error")
(def-unix-error  EBADMSG         74     _N"Not a data message")
(def-unix-error  EOVERFLOW       75     _N"Value too large for defined data type")
(def-unix-error  ENOTUNIQ        76     _N"Name not unique on network")
(def-unix-error  EBADFD          77     _N"File descriptor in bad state")
(def-unix-error  EREMCHG         78     _N"Remote address changed")
(def-unix-error  ELIBACC         79     _N"Can not access a needed shared library")
(def-unix-error  ELIBBAD         80     _N"Accessing a corrupted shared library")
(def-unix-error  ELIBSCN         81     _N".lib section in a.out corrupted")
(def-unix-error  ELIBMAX         82     _N"Attempting to link in too many shared libraries")
(def-unix-error  ELIBEXEC        83     _N"Cannot exec a shared library directly")
(def-unix-error  EILSEQ          84     _N"Illegal byte sequence")
(def-unix-error  ERESTART        85     _N"Interrupted system call should be restarted _N")
(def-unix-error  ESTRPIPE        86     _N"Streams pipe error")
(def-unix-error  EUSERS          87     _N"Too many users")
(def-unix-error  ENOTSOCK        88     _N"Socket operation on non-socket")
(def-unix-error  EDESTADDRREQ    89     _N"Destination address required")
(def-unix-error  EMSGSIZE        90     _N"Message too long")
(def-unix-error  EPROTOTYPE      91     _N"Protocol wrong type for socket")
(def-unix-error  ENOPROTOOPT     92     _N"Protocol not available")
(def-unix-error  EPROTONOSUPPORT 93     _N"Protocol not supported")
(def-unix-error  ESOCKTNOSUPPORT 94     _N"Socket type not supported")
(def-unix-error  EOPNOTSUPP      95     _N"Operation not supported on transport endpoint")
(def-unix-error  EPFNOSUPPORT    96     _N"Protocol family not supported")
(def-unix-error  EAFNOSUPPORT    97     _N"Address family not supported by protocol")
(def-unix-error  EADDRINUSE      98     _N"Address already in use")
(def-unix-error  EADDRNOTAVAIL   99     _N"Cannot assign requested address")
(def-unix-error  ENETDOWN        100    _N"Network is down")
(def-unix-error  ENETUNREACH     101    _N"Network is unreachable")
(def-unix-error  ENETRESET       102    _N"Network dropped connection because of reset")
(def-unix-error  ECONNABORTED    103    _N"Software caused connection abort")
(def-unix-error  ECONNRESET      104    _N"Connection reset by peer")
(def-unix-error  ENOBUFS         105    _N"No buffer space available")
(def-unix-error  EISCONN         106    _N"Transport endpoint is already connected")
(def-unix-error  ENOTCONN        107    _N"Transport endpoint is not connected")
(def-unix-error  ESHUTDOWN       108    _N"Cannot send after transport endpoint shutdown")
(def-unix-error  ETOOMANYREFS    109    _N"Too many references: cannot splice")
(def-unix-error  ETIMEDOUT       110    _N"Connection timed out")
(def-unix-error  ECONNREFUSED    111    _N"Connection refused")
(def-unix-error  EHOSTDOWN       112    _N"Host is down")
(def-unix-error  EHOSTUNREACH    113    _N"No route to host")
(def-unix-error  EALREADY        114    _N"Operation already in progress")
(def-unix-error  EINPROGRESS     115    _N"Operation now in progress")
(def-unix-error  ESTALE          116    _N"Stale NFS file handle")
(def-unix-error  EUCLEAN         117    _N"Structure needs cleaning")
(def-unix-error  ENOTNAM         118    _N"Not a XENIX named type file")
(def-unix-error  ENAVAIL         119    _N"No XENIX semaphores available")
(def-unix-error  EISNAM          120    _N"Is a named type file")
(def-unix-error  EREMOTEIO       121    _N"Remote I/O error")
(def-unix-error  EDQUOT          122    _N"Quota exceeded")

;;; And now for something completely different ...
(emit-unix-errors)

;;; the ioctl's.
;;;
;;; I've deleted all the stuff that wasn't in the header files.
;;; This is what survived.

;; 0x54 is just a magic number to make these relatively unique ('T')

(eval-when (compile load eval)

(defconstant iocparm-mask #x3fff)
(defconstant ioc_void #x00000000)
(defconstant ioc_out #x40000000)
(defconstant ioc_in #x80000000)
(defconstant ioc_inout (logior ioc_in ioc_out))

(defmacro define-ioctl-command (name dev cmd &optional arg parm-type)
  _N"Define an ioctl command. If the optional ARG and PARM-TYPE are given
  then ioctl argument size and direction are included as for ioctls defined
  by _IO, _IOR, _IOW, or _IOWR. If DEV is a character then the ioctl type
  is the characters code, else DEV may be an integer giving the type."
  (let* ((type (if (characterp dev)
		   (char-code dev)
		   dev))
	 (code (logior (ash type 8) cmd)))
    (when arg
      (setf code `(logior (ash (logand (alien-size ,arg :bytes) ,iocparm-mask)
			       16)
			  ,code)))
    (when parm-type
      (let ((dir (ecase parm-type
		   (:void ioc_void)
		   (:in ioc_in)
		   (:out ioc_out)
		   (:inout ioc_inout))))
	(setf code `(logior ,dir ,code))))
    `(eval-when (eval load compile)
       (defconstant ,name ,code))))

)

;;; TTY ioctl commands.

(define-ioctl-command TIOCGWINSZ #\T #x13)
(define-ioctl-command TIOCSWINSZ #\T #x14)
(define-ioctl-command TIOCNOTTY  #\T #x22)
(define-ioctl-command TIOCSPGRP  #\T #x10)
(define-ioctl-command TIOCGPGRP  #\T #x0F)

;;; File ioctl commands.
(define-ioctl-command FIONREAD #\T #x1B)

;;; asm/sockios.h

;;; Socket options.

(define-ioctl-command SIOCSPGRP #x89 #x02)

(defun siocspgrp (fd pgrp)
  _N"Set the socket process-group for the unix file-descriptor FD to PGRP."
  (alien:with-alien ((alien-pgrp c-call:int pgrp))
    (unix-ioctl fd
		siocspgrp
		(alien:alien-sap (alien:addr alien-pgrp)))))

;;; A few random constants and functions

(defconstant setuidexec #o4000 _N"Set user ID on execution")
(defconstant setgidexec #o2000 _N"Set group ID on execution")
(defconstant savetext #o1000 _N"Save text image after execution")
(defconstant readown #o400 _N"Read by owner")
(defconstant writeown #o200 _N"Write by owner")
(defconstant execown #o100 _N"Execute (search directory) by owner")
(defconstant readgrp #o40 _N"Read by group")
(defconstant writegrp #o20 _N"Write by group")
(defconstant execgrp #o10 _N"Execute (search directory) by group")
(defconstant readoth #o4 _N"Read by others")
(defconstant writeoth #o2 _N"Write by others")
(defconstant execoth #o1 _N"Execute (search directory) by others")

(defconstant terminal-speeds
  '#(0 50 75 110 134 150 200 300 600 1200 1800 2400
     4800 9600 19200 38400 57600 115200 230400))

;;;; Support routines for dealing with unix pathnames.

(export '(unix-file-kind unix-maybe-prepend-current-directory
	  unix-resolve-links unix-simplify-pathname))

(defun unix-file-kind (name &optional check-for-links)
  _N"Returns either :file, :directory, :link, :special, or NIL."
  (declare (simple-string name))
  (multiple-value-bind (res dev ino mode)
		       (if check-for-links
			   (unix-lstat name)
			   (unix-stat name))
    (declare (type (or fixnum null) mode)
	     (ignore dev ino))
    (when res
      (let ((kind (logand mode s-ifmt)))
	(cond ((eql kind s-ifdir) :directory)
	      ((eql kind s-ifreg) :file)
	      ((eql kind s-iflnk) :link)
	      (t :special))))))

(defun unix-maybe-prepend-current-directory (name)
  (declare (simple-string name))
  (if (and (> (length name) 0) (char= (schar name 0) #\/))
      name
      (multiple-value-bind (win dir) (unix-current-directory)
	(if win
	    (concatenate 'simple-string dir "/" name)
	    name))))

(defun unix-resolve-links (pathname)
  _N"Returns the pathname with all symbolic links resolved."
  (declare (simple-string pathname))
  (let ((len (length pathname))
	(pending pathname))
    (declare (fixnum len) (simple-string pending))
    (if (zerop len)
	pathname
	(let ((result (make-string 100 :initial-element (code-char 0)))
	      (fill-ptr 0)
	      (name-start 0))
	  (loop
	    (let* ((name-end (or (position #\/ pending :start name-start) len))
		   (new-fill-ptr (+ fill-ptr (- name-end name-start))))
	      ;; grow the result string, if necessary.  the ">=" (instead of
	      ;; using ">") allows for the trailing "/" if we find this
	      ;; component is a directory.
	      (when (>= new-fill-ptr (length result))
		(let ((longer (make-string (* 3 (length result))
					   :initial-element (code-char 0))))
		  (replace longer result :end1 fill-ptr)
		  (setq result longer)))
	      (replace result pending
		       :start1 fill-ptr
		       :end1 new-fill-ptr
		       :start2 name-start
		       :end2 name-end)
	      (let ((kind (unix-file-kind (if (zerop name-end) "/" result) t)))
		(unless kind (return nil))
		(cond ((eq kind :link)
		       (multiple-value-bind (link err) (unix-readlink result)
			 (unless link
			   (error (intl:gettext "Error reading link ~S: ~S")
				  (subseq result 0 fill-ptr)
				  (get-unix-error-msg err)))
			 (cond ((or (zerop (length link))
				    (char/= (schar link 0) #\/))
				;; It's a relative link
				(fill result (code-char 0)
				      :start fill-ptr
				      :end new-fill-ptr))
			       ((string= result "/../" :end1 4)
				;; It's across the super-root.
				(let ((slash (or (position #\/ result :start 4)
						 0)))
				  (fill result (code-char 0)
					:start slash
					:end new-fill-ptr)
				  (setf fill-ptr slash)))
			       (t
				;; It's absolute.
				(and (> (length link) 0)
				     (char= (schar link 0) #\/))
				(fill result (code-char 0) :end new-fill-ptr)
				(setf fill-ptr 0)))
			 (setf pending
			       (if (= name-end len)
				   link
				   (concatenate 'simple-string
						link
						(subseq pending name-end))))
			 (setf len (length pending))
			 (setf name-start 0)))
		      ((= name-end len)
		       (when (eq kind :directory)
			 (setf (schar result new-fill-ptr) #\/)
			 (incf new-fill-ptr))
		       (return (subseq result 0 new-fill-ptr)))
		      ((eq kind :directory)
		       (setf (schar result new-fill-ptr) #\/)
		       (setf fill-ptr (1+ new-fill-ptr))
		       (setf name-start (1+ name-end)))
		      (t
		       (return nil))))))))))

(defun unix-simplify-pathname (src)
  (declare (simple-string src))
  (let* ((src-len (length src))
	 (dst (make-string src-len))
	 (dst-len 0)
	 (dots 0)
	 (last-slash nil))
    (macrolet ((deposit (char)
			`(progn
			   (setf (schar dst dst-len) ,char)
			   (incf dst-len))))
      (dotimes (src-index src-len)
	(let ((char (schar src src-index)))
	  (cond ((char= char #\.)
		 (when dots
		   (incf dots))
		 (deposit char))
		((char= char #\/)
		 (case dots
		   (0
		    ;; Either ``/...' or ``...//...'
		    (unless last-slash
		      (setf last-slash dst-len)
		      (deposit char)))
		   (1
		    ;; Either ``./...'' or ``..././...''
		    (decf dst-len))
		   (2
		    ;; We've found ..
		    (cond
		     ((and last-slash (not (zerop last-slash)))
		      ;; There is something before this ..
		      (let ((prev-prev-slash
			     (position #\/ dst :end last-slash :from-end t)))
			(cond ((and (= (+ (or prev-prev-slash 0) 2)
				       last-slash)
				    (char= (schar dst (- last-slash 2)) #\.)
				    (char= (schar dst (1- last-slash)) #\.))
			       ;; The something before this .. is another ..
			       (deposit char)
			       (setf last-slash dst-len))
			      (t
			       ;; The something is some random dir.
			       (setf dst-len
				     (if prev-prev-slash
					 (1+ prev-prev-slash)
					 0))
			       (setf last-slash prev-prev-slash)))))
		     (t
		      ;; There is nothing before this .., so we need to keep it
		      (setf last-slash dst-len)
		      (deposit char))))
		   (t
		    ;; Something other than a dot between slashes.
		    (setf last-slash dst-len)
		    (deposit char)))
		 (setf dots 0))
		(t
		 (setf dots nil)
		 (setf (schar dst dst-len) char)
		 (incf dst-len))))))
    (when (and last-slash (not (zerop last-slash)))
      (case dots
	(1
	 ;; We've got  ``foobar/.''
	 (decf dst-len))
	(2
	 ;; We've got ``foobar/..''
	 (unless (and (>= last-slash 2)
		      (char= (schar dst (1- last-slash)) #\.)
		      (char= (schar dst (- last-slash 2)) #\.)
		      (or (= last-slash 2)
			  (char= (schar dst (- last-slash 3)) #\/)))
	   (let ((prev-prev-slash
		  (position #\/ dst :end last-slash :from-end t)))
	     (if prev-prev-slash
		 (setf dst-len (1+ prev-prev-slash))
		 (return-from unix-simplify-pathname "./")))))))
    (cond ((zerop dst-len)
	   "./")
	  ((= dst-len src-len)
	   dst)
	  (t
	   (subseq dst 0 dst-len)))))

;;;
;;; STRING-LIST-TO-C-STRVEC	-- Internal
;;; 
;;; STRING-LIST-TO-C-STRVEC is a function which takes a list of
;;; simple-strings and constructs a C-style string vector (strvec) --
;;; a null-terminated array of pointers to null-terminated strings.
;;; This function returns two values: a sap and a byte count.  When the
;;; memory is no longer needed it should be deallocated with
;;; vm_deallocate.
;;; 
(defun string-list-to-c-strvec (string-list)
  ;;
  ;; Make a pass over string-list to calculate the amount of memory
  ;; needed to hold the strvec.
  (let ((string-bytes 0)
	(vec-bytes (* 4 (1+ (length string-list)))))
    (declare (fixnum string-bytes vec-bytes))
    (dolist (s string-list)
      (check-type s simple-string)
      (incf string-bytes (round-bytes-to-words (1+ (length s)))))
    ;;
    ;; Now allocate the memory and fill it in.
    (let* ((total-bytes (+ string-bytes vec-bytes))
	   (vec-sap (system:allocate-system-memory total-bytes))
	   (string-sap (sap+ vec-sap vec-bytes))
	   (i 0))
      (declare (type (and unsigned-byte fixnum) total-bytes i)
	       (type system:system-area-pointer vec-sap string-sap))
      (dolist (s string-list)
	(declare (simple-string s))
	(let ((n (length s)))
	  ;; 
	  ;; Blast the string into place
	  #-unicode
	  (kernel:copy-to-system-area (the simple-string s)
				      (* vm:vector-data-offset vm:word-bits)
				      string-sap 0
				      (* (1+ n) vm:byte-bits))
	  #+unicode
	  (progn
	    ;; FIXME: Do we need to apply some kind of transformation
	    ;; to convert Lisp unicode strings to C strings?  Utf-8?
	    (dotimes (k n)
	      (setf (sap-ref-8 string-sap k)
		    (logand #xff (char-code (aref s k)))))
	    (setf (sap-ref-8 string-sap n) 0))
	  ;; 
	  ;; Blast the pointer to the string into place
	  (setf (sap-ref-sap vec-sap i) string-sap)
	  (setf string-sap (sap+ string-sap (round-bytes-to-words (1+ n))))
	  (incf i 4)))
      ;; Blast in last null pointer
      (setf (sap-ref-sap vec-sap i) (int-sap 0))
      (values vec-sap total-bytes))))

;;; Stuff not yet found in the header files...
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; Abandon all hope who enters here...


;; not checked for linux...
(defmacro fd-set (offset fd-set)
  (let ((word (gensym))
	(bit (gensym)))
    `(multiple-value-bind (,word ,bit) (floor ,offset nfdbits)
       (setf (deref (slot ,fd-set 'fds-bits) ,word)
	     (logior (truly-the (unsigned-byte 32) (ash 1 ,bit))
		     (deref (slot ,fd-set 'fds-bits) ,word))))))

;; not checked for linux...
(defmacro fd-clr (offset fd-set)
  (let ((word (gensym))
	(bit (gensym)))
    `(multiple-value-bind (,word ,bit) (floor ,offset nfdbits)
       (setf (deref (slot ,fd-set 'fds-bits) ,word)
	     (logand (deref (slot ,fd-set 'fds-bits) ,word)
		     (32bit-logical-not
		      (truly-the (unsigned-byte 32) (ash 1 ,bit))))))))

;; not checked for linux...
(defmacro fd-isset (offset fd-set)
  (let ((word (gensym))
	(bit (gensym)))
    `(multiple-value-bind (,word ,bit) (floor ,offset nfdbits)
       (logbitp ,bit (deref (slot ,fd-set 'fds-bits) ,word)))))

;; not checked for linux...
(defmacro fd-zero (fd-set)
  `(progn
     ,@(loop for index upfrom 0 below (/ fd-setsize nfdbits)
	 collect `(setf (deref (slot ,fd-set 'fds-bits) ,index) 0))))




;;;; User and group database access, POSIX Standard 9.2.2

(defun unix-getpwnam (login)
  _N"Return a USER-INFO structure for the user identified by LOGIN, or NIL if not found."
  (declare (type simple-string login))
  (with-alien ((buf (array c-call:char 1024))
	       (user-info (struct passwd))
               (result (* (struct passwd))))
    (let ((returned
	   (alien-funcall
	    (extern-alien "getpwnam_r"
			  (function c-call:int
                                    c-call:c-string
                                    (* (struct passwd))
				    (* c-call:char)
                                    c-call:unsigned-int
                                    (* (* (struct passwd)))))
	    login
	    (addr user-info)
	    (cast buf (* c-call:char))
	    1024
            (addr result))))
      (when (zerop returned)
        (make-user-info
         :name (string (cast (slot result 'pw-name) c-call:c-string))
         :password (string (cast (slot result 'pw-passwd) c-call:c-string))
         :uid (slot result 'pw-uid)
         :gid (slot result 'pw-gid)
         :gecos (string (cast (slot result 'pw-gecos) c-call:c-string))
         :dir (string (cast (slot result 'pw-dir) c-call:c-string))
         :shell (string (cast (slot result 'pw-shell) c-call:c-string)))))))

(defun unix-getpwuid (uid)
  _N"Return a USER-INFO structure for the user identified by UID, or NIL if not found."
  (declare (type unix-uid uid))
  (with-alien ((buf (array c-call:char 1024))
	       (user-info (struct passwd))
               (result (* (struct passwd))))
    (let ((returned
	   (alien-funcall
	    (extern-alien "getpwuid_r"
			  (function c-call:int
                                    c-call:unsigned-int
                                    (* (struct passwd))
                                    (* c-call:char)
                                    c-call:unsigned-int
                                    (* (* (struct passwd)))))
	    uid
	    (addr user-info)
	    (cast buf (* c-call:char))
	    1024
            (addr result))))
      (when (zerop returned)
        (make-user-info
         :name (string (cast (slot result 'pw-name) c-call:c-string))
         :password (string (cast (slot result 'pw-passwd) c-call:c-string))
         :uid (slot result 'pw-uid)
         :gid (slot result 'pw-gid)
         :gecos (string (cast (slot result 'pw-gecos) c-call:c-string))
         :dir (string (cast (slot result 'pw-dir) c-call:c-string))
         :shell (string (cast (slot result 'pw-shell) c-call:c-string)))))))

(defun unix-getgrnam (name)
  _N"Return a GROUP-INFO structure for the group identified by NAME, or NIL if not found."
  (declare (type simple-string name))
  (with-alien ((buf (array c-call:char 2048))
	       (group-info (struct group))
               (result (* (struct group))))
    (let ((returned
	   (alien-funcall
	    (extern-alien "getgrnam_r"
			  (function c-call:int
                                    c-call:c-string
                                    (* (struct group))
                                    (* c-call:char)
                                    c-call:unsigned-int
                                    (* (* (struct group)))))
	    name
	    (addr group-info)
	    (cast buf (* c-call:char))
	    2048
            (addr result))))
      (when (zerop returned)
        (make-group-info
         :name (string (cast (slot result 'gr-name) c-call:c-string))
         :password (string (cast (slot result 'gr-passwd) c-call:c-string))
         :gid (slot result 'gr-gid)
         :members (loop :with members = (slot result 'gr-mem)
                        :for i :from 0
                        :for member = (deref members i)
                        :until (zerop (sap-int (alien-sap member)))
                        :collect (string (cast member c-call:c-string))))))))

(defun unix-getgrgid (gid)
  _N"Return a GROUP-INFO structure for the group identified by GID, or NIL if not found."
  (declare (type unix-gid gid))
  (with-alien ((buf (array c-call:char 2048))
	       (group-info (struct group))
               (result (* (struct group))))
    (let ((returned
	   (alien-funcall
	    (extern-alien "getgrgid_r"
			  (function c-call:int
                                    c-call:unsigned-int
                                    (* (struct group))
                                    (* c-call:char)
                                    c-call:unsigned-int
                                    (* (* (struct group)))))
	    gid
	    (addr group-info)
	    (cast buf (* c-call:char))
	    2048
            (addr result))))
      (when (zerop returned)
        (make-group-info
         :name (string (cast (slot result 'gr-name) c-call:c-string))
         :password (string (cast (slot result 'gr-passwd) c-call:c-string))
         :gid (slot result 'gr-gid)
         :members (loop :with members = (slot result 'gr-mem)
                        :for i :from 0
                        :for member = (deref members i)
                        :until (zerop (sap-int (alien-sap member)))
                        :collect (string (cast member c-call:c-string))))))))


;; EOF
