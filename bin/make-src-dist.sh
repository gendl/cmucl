#!/bin/sh

usage() {
    echo "make-src-dist.sh: [-bgh] [-t gnutar] [-I destdir] version"
    echo "  -h           This help"
    echo "  -b           Use bzip2 compression"
    echo "  -g           Use gzip compression"
    echo "  -t tar       Name/path to GNU tar"
    echo "  -I destdir   Install directly to given directory instead of creating a tarball"
    echo ""
    echo 'Create a tar ball of the cmucl sources.  The tarball is named '
    echo 'cmucl-src-$version.tar.bz2  (or gz if using gzip compression)'
}

while getopts "bgh?t:I:" arg
do
    case $arg in
	b) ENABLE_BZIP=-b ;;
	g) ENABLE_GZIP=-g  ;;
        t) GTAR=$OPTARG ;;
        I) INSTALL_DIR=$OPTARG ;;
	h | \?) usage; exit 1 ;;
    esac
done

shift `expr $OPTIND - 1`

# If no compression given, default to gzip (on the assumption that
# that is available everywhere.)
if [ -z "$ENABLE_BZIP" -a -z "$ENABLE_GZIP" ]; then
    ENABLE_GZIP=-b
fi

# If no version is given, default to today's date
if [ -n "$1" ]; then
    VERSION=$1
else
    VERSION="`date '+%Y-%m-%d-%H:%M:%S'`"
fi

echo Creating source distribution
if [ -n "$ENABLE_GZIP" ]; then
    ZIP="gzip -c"
    ZIPEXT="gz"
fi
if [ -n "$ENABLE_BZIP" ]; then
    ZIP="bzip2"
    ZIPEXT="bz2"
fi

GTAR_OPTIONS="--exclude=.git --exclude='*.pot.~*~'"
if [ -z "$INSTALL_DIR" ]; then
    echo "  Compressing with $ZIP"
    ${GTAR:-tar} ${GTAR_OPTIONS} -cf - bin src tests | ${ZIP} > cmucl-src-$VERSION.tar.$ZIPEXT
else
    # Install in the specified directory
    ${GTAR:-tar} ${GTAR_OPTIONS} -cf - bin src tests | (cd $INSTALL_DIR; ${GTAR:-tar} xf -)
fi
