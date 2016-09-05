#!/bin/sh

# set -x
while getopts "G:O:I:M:bgh?" arg
do
    case $arg in
	G) GROUP="-g $OPTARG" ;;
	O) OWNER="-o $OPTARG" ;;
        I) INSTALL_DIR=$OPTARG ;;
        M) MANDIR=$OPTARG ;;
	b) ENABLE_BZIP=-b ;;
	g) ENABLE_GZIP=-g  ;;
	h | \?) usage; exit 1 ;;
    esac
done

shift `expr $OPTIND - 1`

if [ "$1" = "" -o "$2" = "" -o "$3" = "" -o "$4" = "" ]
then
	echo "Usage: $0 target-directory version arch os"
	exit 1
fi

if [ ! -d "$1" ]
then
	echo "$1 isn't a directory"
	exit 2
fi

DESTDIR=${INSTALL_DIR:-release-$$}
DOCDIR=${DOCDIR:-doc/cmucl}
MANDIR=${MANDIR:-man/man1}
TARGET="`echo $1 | sed 's:/*$::'`"
VERSION=$2
ARCH=$3
OS=$4

# Core file to look for.
CORE=lisp.core
case $ARCH in
	x86*)		FASL=sse2f
                        CORE="lisp-sse2.core" ;;
	sparc*)		FASL=sparcf ;;
	alpha*)		FASL=axpf ;;
	ppc*)		FASL=ppcf ;;
	mips*)		FASL=sgif ;;
	*)
		echo "Unknown FASL type for architecture $ARCH"
		exit 2
		;;
esac

case $OS in
  freebsd*)	
      EXECUTABLE=true
      SCRIPT=FreeBSD
      ;;
  linux*)		
      EXECUTABLE=true
      SCRIPT=Linux
      ;;
  solaris*)		
      EXECUTABLE=true
      SCRIPT=SunOS
      ;;
  darwin*)
      EXECUTABLE=true
      ;;
  *)
      EXECUTABLE=""
      ;;
esac

# Frob PATH to use /usr/ucb/install for Solaris
if [ `uname -s` = "SunOS" ]
then
	PATH=/usr/ucb:$PATH
fi

if [ -z "$INSTALL_DIR" ]; then
    # Clean out DESTDIR, if we're not installing there.
    echo Cleaning $DESTDIR
    [ -d $DESTDIR ] && rm -rf $DESTDIR
fi

# set -x
echo Installing main components
install -d ${GROUP} ${OWNER} -m 0755 $DESTDIR/bin
install -d ${GROUP} ${OWNER} -m 0755 $DESTDIR/lib/cmucl
install -d ${GROUP} ${OWNER} -m 0755 $DESTDIR/lib/cmucl/lib
install -d ${GROUP} ${OWNER} -m 0755 $DESTDIR/lib/cmucl/lib/subsystems
install -d ${GROUP} ${OWNER} -m 0755 $DESTDIR/lib/cmucl/lib/ext-formats
install -d ${GROUP} ${OWNER} -m 0755 $DESTDIR/${DOCDIR}
install -d ${GROUP} ${OWNER} -m 0755 $DESTDIR/${MANDIR}
install ${GROUP} ${OWNER} -m 0755 $TARGET/lisp/lisp $DESTDIR/bin/
if [ "$EXECUTABLE" = "true" ]
then
    install ${GROUP} ${OWNER} -m 0644 $TARGET/lisp/lisp.a $DESTDIR/lib/cmucl/lib/
    install ${GROUP} ${OWNER} -m 0644 $TARGET/lisp/exec-init.o $DESTDIR/lib/cmucl/lib/
    install ${GROUP} ${OWNER} -m 0644 $TARGET/lisp/exec-final.o $DESTDIR/lib/cmucl/lib/
    install ${GROUP} ${OWNER} -m 0755 src/tools/linker.sh $DESTDIR/lib/cmucl/lib/
    if [ -f src/tools/$SCRIPT-cmucl-linker-script ]; then
	install ${GROUP} ${OWNER} -m 0755 src/tools/$SCRIPT-cmucl-linker-script $DESTDIR/lib/cmucl/lib/
    fi
fi
for corefile in $TARGET/lisp/$CORE
do
  install ${GROUP} ${OWNER} -m 0644 $corefile $DESTDIR/lib/cmucl/lib/
done
install ${GROUP} ${OWNER} -m 0755 src/tools/load-foreign.csh src/tools/config \
	$DESTDIR/lib/cmucl/lib/
install ${GROUP} ${OWNER} -m 0644 src/tools/config.lisp \
	$DESTDIR/lib/cmucl/lib/
install ${GROUP} ${OWNER} -m 0644 src/code/generic-site.lisp \
	$DESTDIR/lib/cmucl/lib/
install ${GROUP} ${OWNER} -m 0644 $TARGET/lisp/lisp.nm $TARGET/lisp/lisp.map \
	$TARGET/lisp/internals.h $TARGET/lisp/internals.inc $DESTDIR/lib/cmucl/
install ${GROUP} ${OWNER} -m 0755 src/tools/sample-wrapper $DESTDIR/lib/cmucl/

for f in gray-streams gray-compat simple-streams iodefs
do
    install ${GROUP} ${OWNER} -m 0644 $TARGET/pcl/$f-library.$FASL $DESTDIR/lib/cmucl/lib/subsystems/
done

for f in src/pcl/simple-streams/external-formats/*.lisp src/pcl/simple-streams/external-formats/aliases src/i18n/unidata.bin
do
    install ${GROUP} ${OWNER} -m 0644 $f $DESTDIR/lib/cmucl/lib/ext-formats/
done

# set -x
# Create the directories for asdf and defsystem
for f in asdf defsystem asdf/doc
do
    install -d ${GROUP} ${OWNER} -m 0755 $DESTDIR/lib/cmucl/lib/contrib/$f
done

case `uname -s` in
  Linux*) UCONTRIB="unix-glibc2" ;;
  *) UCONTRIB="unix" ;;
esac

install -d ${GROUP} ${OWNER} -m 0755 $DESTDIR/lib/cmucl/lib/contrib/unix
install ${GROUP} ${OWNER} -m 0644 $TARGET/contrib/unix/$UCONTRIB.$FASL $DESTDIR/lib/cmucl/lib/contrib/unix
install ${GROUP} ${OWNER} -m 0644 src/contrib/load-unix.lisp $DESTDIR/lib/cmucl/lib/contrib
install ${GROUP} ${OWNER} -m 0644 src/contrib/unix/${UCONTRIB}.lisp $DESTDIR/lib/cmucl/lib/contrib/unix

# Copy the source files for asdf and defsystem
for f in `(cd src; find contrib/asdf contrib/defsystem -type f -print | grep -v CVS)`
do
    install ${GROUP} ${OWNER} -m 0644 src/$f $DESTDIR/lib/cmucl/lib/$f
done

# Install the fasl files for asdf and defsystem
for f in asdf defsystem
do
    install ${GROUP} ${OWNER} -m 0644 $TARGET/contrib/$f/$f.$FASL $DESTDIR/lib/cmucl/lib/contrib/$f
done

# Install the docs for asdf
for f in src/contrib/asdf/doc/*
do
    base=`basename $f`
    install ${GROUP} ${OWNER} -m 0644 $f $DESTDIR/lib/cmucl/lib/contrib/asdf/doc/$base
done

install ${GROUP} ${OWNER} -m 0644 src/general-info/cmucl.1 \
	$DESTDIR/${MANDIR}/
install ${GROUP} ${OWNER} -m 0644 src/general-info/lisp.1 \
	$DESTDIR/${MANDIR}/
install ${GROUP} ${OWNER} -m 0644 src/general-info/README $DESTDIR/${DOCDIR}
if [ -f src/general-info/release-$VERSION.txt ] 
then
	install ${GROUP} ${OWNER} -m 0644 src/general-info/release-$VERSION.txt \
		$DESTDIR/${DOCDIR}
fi

if [ -z "$INSTALL_DIR" ]; then
    sync ; sleep 1 ; sync ; sleep 1 ; sync
    echo Tarring main components
    if [ -n "$ENABLE_GZIP" ]; then
	echo "  Compressing with gzip"
	( cd $DESTDIR >/dev/null ; tar cf - . ) | \
	  gzip -c > cmucl-$VERSION-$ARCH-$OS.tar.gz
    fi
    if [ -n "$ENABLE_BZIP" ]; then
	echo "  Compressing with bzip"
	( cd $DESTDIR >/dev/null ; tar cf - . ) | \
	  bzip2 > cmucl-$VERSION-$ARCH-$OS.tar.bz2
    fi

    echo Cleaning $DESTDIR
    [ -d $DESTDIR ] && rm -rf $DESTDIR
    echo Done
fi
