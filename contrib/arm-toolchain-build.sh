#!/bin/bash
#
# Written by Uwe Hermann <uwe@hermann-uwe.de>, released as public domain.
# Modified by Piotr Esden-Tempski <piotr@esden.net>, released as public domain.
# Modified by Christophe Duparquet <e39@free.fr>, released as public domain.

# NOTE by esden:
#
# This script was contributed by Cristophe it contains several implementation
# improvements. I did not test it myself and I know that it lacks support for
# linaro GCC. I currenty have no time to integrate the improvements into the
# original summon-arm-toolchain. It is a nice reference where SAR should go
# implementationwise, IMHO. Maybe someone with some more time on their hands
# would help out here and incorporate the improvements into the original SAR
# that more up to date and has additional features. It would be very
# appreciated.
#
# Also take a look into the HOW-TO-SUBMIT section of the main README what is
# the prefered way to submit patches to SAR.

# This script will build a GNU ARM toolchain in the directory arm-toolchain.
# Process can be suspended and restarted at will.
# Packages are downloaded to arm-toolchain/archives/.
# Packages are extracted to arm-toolchain/sources/.
# Packages are built in arm-toolchain/build/.
# arm-toolchain/install contains the result of make install for each tool.
# arm-toolchain/status contains the status of each part of the process (logs, errors...)


# PACKAGE_DESCRIPTION = BASE_URL ARCHIVE_BASENAME PACKAGE_VERSION ARCHIVE_TYPE URL_OPTIONS
#
BINUTILS="http://ftp.gnu.org/gnu/binutils binutils 2.19.1 tar.bz2"
GCC="ftp://ftp.lip6.fr/pub/gcc/releases/gcc-4.4.4 gcc 4.4.4 tar.bz2"
GDB="http://ftp.gnu.org/gnu/gdb gdb 7.1 tar.bz2"
NEWLIB="ftp://sources.redhat.com/pub/newlib newlib 1.18.0 tar.gz --no-passive-ftp"
INSIGHT="ftp://sourceware.org/pub/insight/releases insight 6.8-1 tar.bz2"

LIBCMSIS="git://git.open-bldc.org libcmsis git dir"
LIBSTM32="git://git.open-bldc.org libstm32 git dir"
LIBSTM32USB="git://git.open-bldc.org libstm32usb git dir"
LIBOPENSTM32="git://libopenstm32.git.sourceforge.net/gitroot/libopenstm32 libopenstm32 git dir"


TARGET=arm-none-eabi			# Or: TARGET=arm-elf

BASEDIR=$(pwd)/arm-toolchain		# Base directory
ARCHIVES=${BASEDIR}/archives		# Where to store downloaded packages
SOURCES=${BASEDIR}/sources		# Where to extract packages
BUILD=${BASEDIR}/build			# Where to build packages
STATUS=${BASEDIR}/status		# Where to store building process status
PREFIX=${BASEDIR}/install		# Install location of your final toolchain

PARALLEL=-j$(getconf _NPROCESSORS_ONLN)

export PATH="${PREFIX}/bin:${PATH}"
mkdir -p ${ARCHIVES} ${SOURCES} ${BUILD} ${STATUS}


die() {
    echo -e "\n\n**FAIL**"
    tail ${CMD}
    # echo -e "\nIn ${ERR} :"
    tail ${ERR}
    echo
    exit
}


context() {
    URL=$1
    ANAME=$2
    AVERSION=$3
    ATYPE=$4
    URL_OPTIONS=$5

    SOURCE=$ANAME-$AVERSION
    ARCHIVE=$SOURCE.$ATYPE
}


fetch() {
    CMD=${STATUS}/${SOURCE}.fetch.cmd
    LOG=${STATUS}/${SOURCE}.fetch.log
    ERR=${STATUS}/${SOURCE}.fetch.errors
    DONE=${STATUS}/${SOURCE}.fetch.done

    if [ -e ${DONE} ]; then
     	echo "${SOURCE} already fetched"
     	return
    fi

    case ${URL} in
	http://*)
	    COMMAND=wget
	    ;;
	ftp://*)
	    COMMAND=wget
	    ;;
	git://*)
	    COMMAND=git
	    ;;
	*)
	    echo "${URL}: unknown protocol." >${ERR}
	    die
    esac

    case $COMMAND in
	wget)
	    cd "$ARCHIVES"
	    echo -n "Downloading $ARCHIVE ... "
	    echo wget -c $URL_OPTIONS "$URL/$ARCHIVE" >${CMD}
	    wget -c $URL_OPTIONS "$URL/$ARCHIVE" >${LOG} 2>${ERR} || die
	    ;;
	git)
	    cd "$SOURCES"
	    rm -rf "$ANAME-git"
	    echo -n "Downloading $SOURCE ... "
	    echo git clone "$URL/$ANAME.git" >${CMD}
	    ((git clone "$URL/$ANAME.git" || git clone "$URL/$ANAME") \
		&& mv ${ANAME} ${ANAME}-git) >${LOG} 2>${ERR} || die
	    ;;
    esac
    echo "OK."
    touch ${DONE}
}


extract() {
    CMD=${STATUS}/${SOURCE}.extract.cmd
    LOG=${STATUS}/${SOURCE}.extract.log
    ERR=${STATUS}/${SOURCE}.extract.errors
    DONE=${STATUS}/${SOURCE}.extract.done

    cd ${BASEDIR}
    if [ -e ${DONE} ] ; then
	echo "${SOURCE} already extracted"
    else
	echo -n "Extracting ${SOURCE} ... "
	cd ${SOURCES}
	case ${ATYPE} in
	    tar.gz)
		COMMAND=xvzf
		;;
	    tar.bz2)
		COMMAND=xvjf
		;;
	    dir)
		COMMAND=""
		cp -a "$SOURCES/$SOURCE" "$BUILD/$SOURCE"
		;;
	    *)
		if [ -d ${ARCHIVES}/${ARCHIVE} ] ; then
		    ln -s ${ARCHIVES}/${ARCHIVE} .
		    ln -s ${ARCHIVES}/${ARCHIVE} ${BUILD}
		    touch ${DONE}
		    return
		else
		    echo "${ARCHIVE}: unknown archive format." >${ERR}
		    die
		fi
	esac
	if [ -n "$COMMAND" ] ; then
	    echo "tar $COMMAND ${ARCHIVES}/${ARCHIVE}" >${CMD}
	    tar $COMMAND ${ARCHIVES}/${ARCHIVE} >${LOG} 2>${ERR} || die
	fi
	echo "OK."
	touch ${DONE}
    fi
}


configure() {
    OPTIONS=$*

    unset ZPASS
    [ -z "$PASS" ] || ZPASS=".$PASS"
    CMD=${STATUS}/${SOURCE}.configure${ZPASS}.cmd
    LOG=${STATUS}/${SOURCE}.configure${ZPASS}.log
    ERR=${STATUS}/${SOURCE}.configure${ZPASS}.errors
    DONE=${STATUS}/${SOURCE}.configure${ZPASS}.done

    cd ${BASEDIR}
    if [ -e ${DONE} ]; then
	echo "${SOURCE} already configured"
    else
	echo -n "Configuring ${SOURCE} ... "
	mkdir -p ${BUILD}/${SOURCE}
	cd ${BUILD}/${SOURCE}
	echo "${SOURCES}/${SOURCE}/configure $OPTIONS" >${CMD}
	${SOURCES}/${SOURCE}/configure $OPTIONS >${LOG} 2>${ERR} || die
	echo "OK."
	touch ${DONE}
    fi
    unset PASS ZPASS
}


domake() {
    WHAT=$1 ; shift
    OPTIONS=$*

    [ -z "$WHAT" ] || ZWHAT=".$WHAT"
    [ -z "$PASS" ] || ZPASS=".$PASS"
    CMD=${STATUS}/${SOURCE}.make${ZWHAT}${ZPASS}.cmd
    LOG=${STATUS}/${SOURCE}.make${ZWHAT}${ZPASS}.log
    ERR=${STATUS}/${SOURCE}.make${ZWHAT}${ZPASS}.errors
    DONE=${STATUS}/${SOURCE}.make${ZWHAT}${ZPASS}.done

    cd ${BASEDIR}
    if [ -e ${DONE} ]; then
	echo "Make ${SOURCE} \"${WHAT}\" already done"
    else
	echo -n "Make ${SOURCE} \"${WHAT}\" ... "
	cd ${BUILD}/${SOURCE}
	echo "make ${WHAT} $OPTIONS" >${CMD}
	make ${PARALLEL} ${WHAT} $OPTIONS >${LOG} 2>${ERR} || die
	echo "OK."
	touch ${DONE}
    fi
    unset PASS ZPASS ZWHAT
}


# Binutils
#
context $BINUTILS
fetch
extract
configure \
    --target=${TARGET} \
    --prefix=${PREFIX} \
    --enable-interwork \
    --enable-multilib \
    --with-gnu-as \
    --with-gnu-ld \
    --disable-nls \
    --disable-werror
domake
domake install


# GCC pass 1
#
context $GCC
fetch
extract
PASS=1 configure \
    --target=${TARGET} \
    --prefix=${PREFIX} \
    --enable-interwork \
    --enable-multilib \
    --enable-languages="c" \
    --with-newlib \
    --without-headers \
    --disable-shared \
    --with-gnu-as \
    --with-gnu-ld \
    --disable-nls \
    --disable-werror
PASS=1 domake all-gcc
PASS=1 domake install-gcc


# Newlib
#
context $NEWLIB
fetch
extract
configure \
    --target=${TARGET} \
    --prefix=${PREFIX} \
    --enable-interwork \
    --enable-multilib \
    --with-gnu-as \
    --with-gnu-ld \
    --disable-nls \
    --disable-werror \
    --disable-newlib-supplied-syscalls
domake
domake install


# GCC pass 2
#
context $GCC
# rm -rf ${BUILD}/${SOURCE}
# rm ${STATUS}/${SOURCE}.configure.done
PASS=2 configure \
    --target=${TARGET} \
    --prefix=${PREFIX} \
    --enable-interwork \
    --enable-multilib \
    --enable-languages="c,c++" \
    --with-newlib \
    --disable-shared \
    --with-gnu-as \
    --with-gnu-ld \
    --disable-nls \
    --disable-werror
PASS=2 domake
PASS=2 domake install


# GDB
#
context $GDB
fetch
extract
configure \
    --target=${TARGET} \
    --prefix=${PREFIX} \
    --enable-interwork \
    --enable-multilib \
    --disable-werror
domake
domake install


# Insight
#
context $INSIGHT
fetch
extract
configure \
    --target=${TARGET} \
    --prefix=${PREFIX} \
    --enable-languages=c,c++ \
    --enable-thumb \
    --enable-interwork \
    --enable-multilib \
    --enable-tui \
    --with-newlib \
    --disable-werror \
    --disable-libada \
    --disable-libssp \
    --with-expat
domake
domake install


# libcmsis
#
context $LIBCMSIS
fetch
extract
domake "" arch_prefix=${TARGET} prefix=${PREFIX}
domake install arch_prefix=${TARGET} prefix=${PREFIX}


# libstm32
#
context $LIBSTM32
fetch
extract
domake "" arch_prefix=${TARGET} prefix=${PREFIX}
domake install arch_prefix=${TARGET} prefix=${PREFIX}


# libstm32usb
#
context $LIBSTM32USB
fetch
extract
domake "" arch_prefix=${TARGET} prefix=${PREFIX}
domake install arch_prefix=${TARGET} prefix=${PREFIX}


# libopenstm32
#
context $LIBOPENSTM32
fetch
extract
domake "" DESTDIR=${PREFIX} PREFIX=${TARGET}
domake install DESTDIR=${PREFIX} PREFIX=${TARGET}
