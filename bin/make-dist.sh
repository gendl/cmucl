#!/bin/sh

# Build a binary distribution of CMUCL.  This script takes the result
# from build.sh and packages up everything into two tarballs.  One
# contains the core of cmucl; the other contains extras like clx, clm,
# and hemlock.  Optionally a source distrubition is also created.
#
# Alternatively, you can install everything into a directory, as if
# you extracted the two tarballs and the source distribution into that
# directory.
#
# $Header: /Volumes/share2/src/cmucl/cvs2git/cvsroot/src/tools/make-dist.sh,v 1.20 2011/04/11 16:34:49 rtoy Exp $

usage() {
    echo "make-dist.sh: [-hbg] [-G group] [-O owner] [-I destdir] [-M mandir] dir [version arch os]"
    echo "  -h           This help"
    echo "  -b           Use bzip2 compression"
    echo "  -g           Use gzip compression"
    echo "  -G group     Group to use"
    echo "  -O owner     Owner to use"
    echo "  -I destdir   Install directly to given directory instead of creating a tarball"
    echo "  -M mandir    Install manpages in this subdirectory.  Default is man/man1"
    echo "  -S           Create a source distribution (requires GNU tar)"
    echo "                 The compressed tar file is named cmucl-src-<VERSION>.tar.<ext>"
    echo "                 If -I is also given, the -S means that the sources are "
    echo "                 installed in the <destdir>/src"
    echo "   dir         Directory where the build is located"
    echo "   version     Version (usually date and/or other version info)"
    echo "   arch        Architecture (x86, sparc, etc.)"
    echo "   os          OS (linux, solaris8, etc.)"
    echo ""
    echo "If the -I option is given, directly install all of the files to the"
    echo "specified directory.  Otherwise, Make a CMUCL distribution consisting"
    echo "of two tar files.  One holds the main files including the C runtime,"
    echo "the lisp core, and PCL library. The second tar file contains extra"
    echo "libraries such as CLX, CLM, and Hemlock."
    echo ""
    echo "The tar files have the form cmucl-<version>-<arch>-<os>.tar.<c>"
    echo "and cmucl-<version>-<arch>-<os>.extra.tar.<c> where <version>,"
    echo "<arch>, and <os> are given values, and <c> is gz or bz2 depending"
    echo "on the selected compression method."
    echo ""
    echo "If version is not given, then a version is determined automatically"
    echo "based on the result of git describe."
    echo ""
    echo "If arch and os are not given, the script will attempt to figure an"
    echo "appropriate value for arch and os from the running system."
    echo ""
    echo "Creating a source distribution requires GNU tar.  If 'tar' is not GNU"
    echo "tar, use the environment variable 'GTAR' to specify GNU tar.  You can"
    echo "use 'GTAR=gtar make-dist.sh -S ...' in this case."
    exit 1
}

def_arch_os () {
    case `uname -s` in
      SunOS)
	  case `uname -m` in
	    sun*)
		ARCH=sparcv9 ;;
	    i*)
		ARCH=x86 ;;
	  esac
	  uname_r=`uname -r`
	  case $uname_r in
	    5.*) rel=`echo $uname_r | sed 's/5\.//'`;;
	    *) rel=$uname_r;;
	  esac
	  OS=solaris$rel
	  ;;
      Linux)
	  ARCH=x86
	  OS=linux
	  ;;
      Darwin)
          OS=darwin
          # x86 or ppc?
          case `uname -m` in
	      i386|x86_64) ARCH=x86 ;;
	      *) ARCH=ppc ;;
	  esac ;;
      NetBSD)
	  ARCH=x86
	  OS=netbsd
	  ;;
      FreeBSD)
	  ARCH=x86
	  OS=freebsd_`uname -r | tr 'A-Z' 'a-z'`
	  ;;
      esac
}

while getopts "G:O:I:M:bghS?" arg
do
    case $arg in
	G) GROUP=$OPTARG ;;
	O) OWNER=$OPTARG ;;
        I) INSTALL_DIR=$OPTARG ;;
        M) MANDIR=$OPTARG ;;
	b) ENABLE_BZIP=-b ;;
	g) ENABLE_GZIP=-g  ;;
        S) MAKE_SRC_DIST=yes ;;
	h | \?) usage; exit 1 ;;
    esac
done

shift `expr $OPTIND - 1`

# Figure out the architecture and OS
ARCH=
OS=

# Figure out the architecture and OS
def_arch_os

if [ -n "${INSTALL_DIR}" ]; then
    # Doing direct installation
    if [ $# -lt 1 ]; then
	usage
    else
	def_arch_os
    fi
elif [ $# -lt 2 ]; then
    # Version not specified so choose a version based on the git hash.
    GIT_HASH="`(cd src; git describe --dirty 2>/dev/null)`"

    if expr "X${GIT_HASH}" : 'Xsnapshot-[0-9][0-9][0-9][0-9]-[01][0-9]' > /dev/null; then
	VERSION=`expr "${GIT_HASH}" : "snapshot-\(.*\)"`
    fi

    if expr "X${GIT_HASH}" : 'X[0-9][0-9][a-f]' > /dev/null; then
	VERSION="${GIT_HASH}"
    fi

    echo "Defaulting version to $VERSION"
else
    VERSION="$2"
    if [ $# -eq 3 ]; then
	ARCH=$3
    elif [ $# -eq 4 ]; then
	ARCH=$3
	OS=$4
    fi
fi

if [ ! -d "$1" ]
then
	echo "$1 isn't a directory"
	exit 2
fi

if [ -z "$INSTALL_DIR" ]; then
    if [ -z "$ARCH" ]; then
	echo "Unknown architecture.  Please specify one"
	usage
    fi

    if [ -z "$OS" ]; then
	echo "Unknown OS.  Please specify one"
	usage
    fi
fi   

TARGET="`echo $1 | sed 's:/*$::'`"

if [ -n "$INSTALL_DIR" ]; then
    VERSION="today"
fi

ROOT=`dirname $0`

# If no compression options given, default to bzip
if [ -z "$ENABLE_GZIP" -a -z "$ENABLE_BZIP" ]; then
    ENABLE_BZIP="-b"
fi

OPTIONS="${GROUP:+ -G ${GROUP}} ${OWNER:+ -O ${OWNER}} ${INSTALL_DIR:+ -I ${INSTALL_DIR}} $ENABLE_GZIP $ENABLE_BZIP"
MANDIR="${MANDIR:+ -M ${MANDIR}}"

echo Creating distribution for $ARCH $OS
$ROOT/make-main-dist.sh $OPTIONS ${MANDIR} $TARGET $VERSION $ARCH $OS || exit 1
$ROOT/make-extra-dist.sh $OPTIONS $TARGET $VERSION $ARCH $OS || exit 2

if [ X"$MAKE_SRC_DIST" = "Xyes" ]; then
    # If tar is not GNU tar, set the environment variable GTAR to
    # point to GNU tar.
    OPTIONS="${INSTALL_DIR:+ -I ${INSTALL_DIR}} $ENABLE_GZIP $ENABLE_BZIP"
    $ROOT/make-src-dist.sh $OPTIONS -t ${GTAR:-tar} $VERSION
fi
