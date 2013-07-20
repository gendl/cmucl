#!/bin/sh

usage()
{
    echo "load-world.sh [-?p] target-directory [version-string]"
    echo "   -p    Skip loading of PCL (Mostly for cross-compiling)"
    echo "   -?    This help"
    echo " If the version-string is not given, the current date and time is used"
    exit 1
}

SKIP_PCL=
NO_PCL_FEATURE=
# Default version is the date with the git hash.  Older versions of
# git don't support --dirty, but the output in that case is what we
# want (except for ending with "dirty"), so we're set.
GIT_HASH="`(cd src; git describe --dirty 2>/dev/null || git describe 2>/dev/null)`"

# If the git hash looks like a snapshot tag or release, don't add the date.
VERSION="`date '+%Y-%m-%d %H:%M:%S'`${GIT_HASH:+ $GIT_HASH}"
if expr "X${GIT_HASH}" : 'Xsnapshot-[0-9][0-9][0-9][0-9]-[01][0-9]' > /dev/null; then
    VERSION="${GIT_HASH}"
fi

if expr "X${GIT_HASH}" : 'X[0-9][0-9][a-f]' > /dev/null; then
    VERSION="${GIT_HASH}"
fi
echo $VERSION

while getopts "p" arg
do
  case $arg in
      p) SKIP_PCL="yes"
         shift;;
      \?) usage ;;
  esac
done

if [ ! -d "$1" ]
then
	echo "$1 isn't a directory"
	exit 2
fi

TARGET="`echo $1 | sed 's:/*$::'`"

# If -p given, we want to skip loading of PCL.  Do this by pushing
# :no-pcl onto *features*

if [ -n "$SKIP_PCL" ]; then
    NO_PCL_FEATURE="(pushnew :no-pcl *features*)"
fi

# If version string given, use it, otherwise use the default.
if [ -n "$2" ]; then
    VERSION="$2"
fi

$TARGET/lisp/lisp -core $TARGET/lisp/kernel.core <<EOF
(in-package :cl-user)

(setf (ext:search-list "target:")
      '("$TARGET/" "src/"))

(load "target:setenv")

(pushnew :no-clx *features*)
(pushnew :no-clm *features*)
(pushnew :no-hemlock *features*)
$NO_PCL_FEATURE

(load "target:tools/worldload")
$VERSION

EOF
