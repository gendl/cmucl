#!/bin/sh

while getopts "G:O:I:bgh?" arg
do
    case $arg in
	G) GROUP="-g $OPTARG" ;;
	O) OWNER="-o $OPTARG" ;;
        I) INSTALL_DIR=$OPTARG ;;
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
TARGET="`echo $1 | sed 's:/*$::'`"
VERSION=$2
ARCH=$3
OS=$4

case $ARCH in
	x86*)		FASL="sse2f" ;;
	sparc*)		FASL=sparcf ;;
	alpha*)		FASL=axpf ;;
	ppc*)		FASL=ppcf ;;
	mips*)		FASL=sgif ;;
	*)
		echo "Unknown FASL type for architecture $ARCH"
		exit 2
		;;
esac

# Frob PATH to use /usr/ucb/install for Solaris
if [ `uname -s` = "SunOS" ]
then
	PATH=/usr/ucb:$PATH
fi

if [ -z "$INSTALL_DIR" ]; then
    echo Cleaning $DESTDIR
    [ -d $DESTDIR ] && rm -rf $DESTDIR
fi

echo Installing extra components
install -d ${GROUP} ${OWNER} -m 0755 $DESTDIR/lib/cmucl/lib

install -d ${GROUP} ${OWNER} -m 0755 $DESTDIR/lib/cmucl/lib/subsystems

install -d ${GROUP} ${OWNER} -m 0755 $DESTDIR/lib/cmucl/lib/contrib

for ext in $FASL
do
  install ${GROUP} ${OWNER} -m 0644 $TARGET/clx/clx-library.$ext \
      $DESTDIR/lib/cmucl/lib/subsystems/
  install ${GROUP} ${OWNER} -m 0644 $TARGET/hemlock/hemlock-library.$ext \
      $DESTDIR/lib/cmucl/lib/subsystems/
  install ${GROUP} ${OWNER} -m 0644 $TARGET/interface/clm-library.$ext  \
      $DESTDIR/lib/cmucl/lib/subsystems/
done

# Not sure we really need these, but we'll install them in the
# ext-formats directory.  (Should they go somewhere else?)
#install -d ${GROUP} ${OWNER} -m 0755 $DESTDIR/lib/cmucl/lib/ext-formats
#for f in src/i18n/NameAliases.txt src/i18n/UnicodeData.txt
#do
#    echo $f
#    install ${GROUP} ${OWNER} -m 0644 $f $DESTDIR/lib/cmucl/lib/ext-formats/
#done

# install -d ${GROUP} ${OWNER} -m 0755 $DESTDIR/lib/cmucl/lib/fonts/
# install ${GROUP} ${OWNER} -m 0644 misc/8x13u.snf misc/fonts.dir \
#	$DESTDIR/lib/cmucl/lib/fonts/
install ${GROUP} ${OWNER} -m 0644 src/hemlock/XKeysymDB \
	src/hemlock/hemlock11.cursor src/hemlock/hemlock11.mask \
	$TARGET/hemlock/spell-dictionary.bin \
	$DESTDIR/lib/cmucl/lib/
install ${GROUP} ${OWNER} -m 0755 src/hemlock/mh-scan $DESTDIR/lib/cmucl/lib/
install ${GROUP} ${OWNER} -m 0755 $TARGET/motif/server/motifd \
	$DESTDIR/lib/cmucl/lib/

# Install the contrib stuff.  Create the directories and then copy the files.

for d in `(cd src; find contrib -type d -print | egrep -v "CVS|asdf|defsystem")`
do
    install -d ${GROUP} ${OWNER} -m 0755 $DESTDIR/lib/cmucl/lib/$d
done

for f in `(cd src/contrib; find . -type f -print | egrep -v "CVS|asdf|defsystem")`
do
    FILE=`basename $f`
    DIR=`dirname $f`
    install ${GROUP} ${OWNER} -m 0644 src/contrib/$f $DESTDIR/lib/cmucl/lib/contrib/$DIR
done

# Install all the locale data.

for d in `(cd src/i18n/; find locale -type d -print | egrep -v CVS)`
do
    install -d ${GROUP} ${OWNER} -m 0755 $DESTDIR/lib/cmucl/lib/$d
done

# Install mo files.
for f in `(cd $TARGET/i18n; find locale -type f -print | egrep -v 'CVS|~.*~|.*~')`
do
    FILE=`basename $f`
    DIR=`dirname $f`
    install ${GROUP} ${OWNER} -m 0644 $TARGET/i18n/$f $DESTDIR/lib/cmucl/lib/$DIR
done

# Install po files.  (Do we really need to distribute the po files?)
#for f in `(cd $TARGET/i18n; find locale -type f -print | egrep -v 'CVS|~.*~|.*~')`
#do
#    FILE=`basename $f`
#    DIR=`dirname $f`
#    install ${GROUP} ${OWNER} -m 0644 $TARGET/i18n/$f $DESTDIR/lib/cmucl/lib/$DIR
#done

if [ -z "$INSTALL_DIR" ]; then
    sync ; sleep 1 ; sync ; sleep 1 ; sync
    echo Tarring extra components
    if [ -n "$ENABLE_GZIP" ]; then
	echo "  Compressing with gzip"
	( cd $DESTDIR >/dev/null ; tar cf - lib ) | \
	 gzip -c > cmucl-$VERSION-$ARCH-$OS.extra.tar.gz
    fi
    if [ -n "$ENABLE_BZIP" ]; then
	echo "  Compressing with bzip"
	( cd $DESTDIR >/dev/null ; tar cf - lib ) | \
	 bzip2 > cmucl-$VERSION-$ARCH-$OS.extra.tar.bz2
    fi

    echo Cleaning $DESTDIR
    [ -d $DESTDIR ] && rm -rf $DESTDIR
    echo Done
fi
