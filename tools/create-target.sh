#!/bin/sh

LISP_VARIANT=
MOTIF_VARIANT=
TARGET_DIR=

usage() {
    echo "Usage: `basename $0` target-dir [lisp-variant [motif-variant]]"
    echo ""
    echo "Creates a directory structure in TARGET-DIR for use in compiling"
    echo "CMUCL.  If the lisp-variant is not given, uname is used to select"
    echo "a version, if possible.  If motif-variant is not given, one is"
    echo "determined from the lisp-variant."
    echo ""
    # List possible values for lisp-variant and motif-variant
    echo "Possible lisp-variants:"
    ( cd src/lisp/ ; ls -1 Config.* ) | sed 's;^Config[.];;g' | \
	    pr -3at -o 8
    echo "Possible Motif-variants:"
    ( cd src/motif/server/ && ls -1 Config.* ) | sed 's;^Config[.];;g' | pr -3at -o 8
    exit 1
}

TARGET_DIR="$1"
case $TARGET_DIR in build-*) :;; *) usage; exit 2;; esac
[ -d $ "$TARGET_DIR" ] && echo "Error: Directory $1 exists already -- better remove it..." # && exit 2

if [ $# = 1 ]; then
    # Only target directory given.  Try to deduce the lisp-variant
    case `uname -s` in
    SunOS) 
	case `uname -m` in
	  i86pc) LISP_VARIANT=x86_solaris_sunc ;;
	  sun*) LISP_VARIANT=sparc_gcc ;;
	esac 
	;;
    Linux) LISP_VARIANT=x86_linux ;;
    Darwin) case `uname -m` in
            ppc) LISP_VARIANT=ppc_darwin ;;
	    i386) LISP_VARIANT=x86_darwin ;;
	    esac
	    ;;
    FreeBSD|freebsd) LISP_VARIANT=x86_freebsd ;;
    # Please fill in some other common systems
    *) echo "Sorry, please specify the desired Lisp variant." 
       exit 1 ;;
    esac
elif [ $# = 2 ]; then
    # Target directory and lisp-variant given 
    LISP_VARIANT="$2"
elif [ $# = 3 ]; then
    # Target directory, lisp-variant, and motif variant given 
    LISP_VARIANT="$2"
    MOTIF_VARIANT="$3"
else
    usage
fi


# Make sure the given variants exist
if [ ! -f src/lisp/Config.$LISP_VARIANT ]; then
	echo "No such lisp-variant could be found: Config.$LISP_VARIANT"
	exit 1
fi

# From the given variant, try to derive a motif variant
if [ "$MOTIF_VARIANT" = "" ]; then
    case $LISP_VARIANT in
      alpha_linux) MOTIF_VARIANT=alpha_linux ;;
      alpha_osf1) MOTIF_VARIANT=alpha_osf1 ;;
      x86_freebsd|FreeBSD*|freebsd*) MOTIF_VARIANT=FreeBSD ;;
      NetBSD*) MOTIF_VARIANT=NetBSD ;;
      OpenBSD*) MOTIF_VARIANT=OpenBSD ;;
      *_darwin) MOTIF_VARIANT=Darwin ;;
      sun4_solaris_gcc|sparc_gcc) MOTIF_VARIANT=solaris ;;
      sun4_solaris_sunc|sparc_sunc|x86_solaris_sunc) MOTIF_VARIANT=solaris_sunc ;;
      sun4c*) MOTIF_VARIANT=sun4c_411 ;;
      hp700*) MOTIF_VARIANT=hpux_cc ;;
      pmax_mach) MOTIF_VARIANT=pmax_mach ;;
      sgi*) MOTIF_VARIANT=irix ;;
      x86_linux|linux*) MOTIF_VARIANT=x86 ;;
    esac
elif [ ! -f src/motif/server/Config.$MOTIF_VARIANT ]; then
    echo "No such motif-variant could be found: Config.$MOTIF_VARIANT"
    exit 1
fi

# Tell user what's we've configured
echo "Lisp = $LISP_VARIANT"
echo "Motif = $MOTIF_VARIANT"

# Create a directory tree that mirrors the source directory tree
TARGET="`echo $TARGET_DIR | sed 's:/*$::'`"
echo TARGET_DIR=$TARGET_DIR TARGET=$TARGET
find -L src -type d -print | sed "s:^src:$TARGET:g" | xargs -t mkdir -p

# Link Makefile and Config files
(cd $TARGET/lisp && {
	ln -s ../../src/lisp/GNUmakefile ../../src/lisp/Config.$LISP_VARIANT ../../src/lisp/Config.*_common .
	ln -s Config.$LISP_VARIANT Config
    } || { echo "Can't cd $TARGET/lisp"; exit 1; }
)

# Create empty initial map file
echo 'Map file for lisp version 0' > $TARGET/lisp/lisp.nm

# Create dummy internals.h so we get warned to recompile
echo '#error You need to run genesis (via build-world.sh) before compiling the startup code!' > $TARGET/lisp/internals.h

SETENV=src/tools/setenv-scripts

# Create sample setenv.lisp file
cat $SETENV/base-features.lisp > $TARGET/setenv.lisp

# Put in some platform specific items
case $LISP_VARIANT in
  *linux*)
      gcname=":gencgc"
      sed "s;@@gcname@@;$gcname;" $SETENV/linux-features.lisp >> $TARGET/setenv.lisp
      ;;
  *OpenBSD*)
      case $LISP_VARIANT in
        *_gencgc*) gcname=":gencgc" ;;
	*) gcname=":cgc" ;;
      esac
      sed "s;@@gcname@@;$gcname;" $SETENV/openbsd-features.lisp >> $TARGET/setenv.lisp
      ;;
  *FreeBSD*|*freebsd*)
      gcname=":gencgc"
      sed "s;@@gcname@@;$gcname;" $SETENV/freebsd-features.lisp >> $TARGET/setenv.lisp
      ;;
  *solaris*)
      cat $SETENV/solaris-features.lisp >> $TARGET/setenv.lisp
      ;;
  *)
      sed "s;@@LISP@@;$LISP_VARIANT;" $SETENV/unknown.lisp >> $TARGET/setenv.lisp
      ;;
esac


# Do Motif setup
if [ "$MOTIF_VARIANT" != "" ]
then
    ( cd $TARGET/motif/server ; ln -s ../../../src/motif/server/GNUmakefile ./Makefile )
    ( cd $TARGET/motif/server ; ln -s ../../../src/motif/server/Config.$MOTIF_VARIANT ./Config )
fi
