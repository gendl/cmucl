#!/bin/sh

while getopts "h?" arg
do
    case $arg in
      h) usage ;;
      \?) usage ;;
    esac
done

usage() 
{
    echo "rebuild.-lisp.sh [-h?] target-directory"
    echo "    -h        this help"
    echo "    -?        this help"
    echo ""
    echo "Force recompiling all the C code in the specified directory".
}

shift `expr $OPTIND - 1`

if [ "$1" = "" ]
then
	usage
	exit 1
fi

if [ ! -d "$1" ]
then
	echo "$1" must be a directory.
	exit 2
fi

TARGET="`echo $1 | sed 's:/*$::'`"

# Find GNU make:

if [ "$MAKE" = "" ]
then	
	MAKE="`which gmake`" || MAKE="`which make`"
fi

export MAKE

${MAKE} -C $TARGET/lisp clean && ${MAKE} -C $TARGET/lisp
