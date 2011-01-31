#!/bin/bash
#
# opkg.sh: script to build an opk package from an installed directory and
#          matching control files.
#
#          Copyright (C) 2011 Stefan Seyfried
#          Released under the GNU General Public License (GPL) Version 2
#
# $1 == $(CONTROL_DIR)
#
# Parameters are passed with environment variables:
# * mandatory parameters
# STRIP		- strip binary for target
# MAINTAINER	- maintainer entry, @MAINT@ in control files is replaced with it.
# ARCH		- package arch, @ARCH@ in control files is replaced with it.
# SOURCE	- targetprefix, where the files where installed.
# BUILD_TMP	- tempdir to build the package
# * non mandatory parameters
# PACKAGE_DIR	- directory to copy the built package to. If the same package
#		  version is already present there, compare and skip copying if equal
# DONT_STRIP	- if this is not empty, don't strip files
# CMP_IGNORE	- list of files to ignore for package compare (full path)
#
# This is intended to be used in Makefiles, so only ever exit with non-zero
# if there was an error.

# exit on errors. Don't cover up.
set -e
ME=${0##*/}

CONTROL_DIR="$1"

test -n "$STRIP"
test -n "$ARCH"
test -n "$SOURCE"
test -n "$BUILD_TMP"
if test -z "$MAINTAINER"; then
	echo "MAINTAINER must not be empty!" >&2
	exit 42
fi

# checks if an old package of the same name and version is already present in $PACKAGE_DIR.
# if not present, return -1
# if different, retur the revision (build number) of that package
# if equal, return 0
#
# translate "return" with "echo'ed to stdout".
check_oldpackage() {
	local R r FILE # revision
	# for backwards compatibility, just succeed if PACKAGE_DIR is not set
	if test -z "$PACKAGE_DIR"; then
		echo 0
		return
	fi

	# check if the package already exists...
	TEST=$(ls ${PACKAGE_DIR}/${NAME}-${VERS}-*.opk 2>/dev/null)
	if test -z "$TEST"; then
		echo "${ME}: package does not exist yet" >&2
		echo "-1"
		return
	fi

	if [ $(echo "$TEST" | wc -w) -gt 1 ]; then
		echo "${ME}: WARNING: seems more than one old package revision is present." >&2
		echo "${ME}:          unpredictable results may follow." >&2
	fi
	# crappy version-sort routine, in case more than one old package is present...
	r=-1; FILE=""
	for i in $TEST; do
		R=${i#${PACKAGE_DIR}/${NAME}-${VERS}-} # strip $NAME-$VERS-
		R=${R%.opk}
		[ $R -lt $r ] && continue
		r=$R; FILE=$i
	done
	test -z "$FILE" && { echo "check_oldpackage: \$FILE is empty" >&2; exit 1; } # assert
	echo "${ME}: package $FILE already exists, comparing..." >&2
	mkdir oldroot oldCONTROL
	ar p $FILE control.tar.gz | tar -xzf - -C oldCONTROL
	ar p $FILE data.tar.gz    | tar -xzf - -C oldroot
	#
	# check for symlink differences, diff does not like dangling symlinks
	NEWLINKS=$(cd root && find . -type l | sort)
	OLDLINKS=$(cd oldroot && find . -type l | sort)
	if test "$NEWLINKS" != "$OLDLINKS"; then # the trivial case... list of links differs
		echo "${ME}: package content differs..." >&2
		echo $r
		return
	fi
	for link in $NEWLINKS; do # less trivial check if link targets differ
		test $(readlink oldroot/$link) = $(readlink root/$link) && continue || true
		echo "${ME}: package content differs..." >&2
		echo $r
		return
	done
	cp -al root newroot
	for i in $CMP_IGNORE; do
		rm -f oldroot/$i
		rm newroot/$i || { echo "CMP_IGNORE file $i not present" >&2 ; exit 1; }
	done
	cp -a CONTROL newCONTROL
	oldver=$(awk '/^Version:/ {print $2}' oldCONTROL/control)
	newver=$(awk '/^Version:/ {print $2}' newCONTROL/control)
	oldver=${oldver%-*} # strip build rev
	newver=${newver%-*}
	sed -i '/^Version:/d' {old,new}CONTROL/control # do not diff versions
	# remove symlinks, already checked above.
	find {old,new}root -type l | xargs --no-run-if-empty rm
	if ! diff -r {old,new}root > /dev/null; then
		echo "${ME}: package content differs..." >&2
		echo $r
		return
	elif ! diff -r {old,new}CONTROL >&2 || test "$oldver" != "$newver"; then
		echo "${ME}: package metadata differs...$oldver $newver" >&2
		echo $r
		return
	fi
	echo "${ME}: package content and metadata is identical, keeping old package" >&2
	echo 0
	return
}


cd $BUILD_TMP/
rm -rf .opkg
mkdir .opkg
cd .opkg
mkdir root

# copy all that's needed into the buildroot
cp -a $SOURCE/. root/.
cp -a $CONTROL_DIR CONTROL

# extract package name and version from control file...
eval $(awk -F":[[:space:]*]" \
	'/^Package:/{print "PACKAGE=\""$2"\""};
	 /^Version:/{print "VERSION=\""$2"\""}' CONTROL/control)
echo "2.0" > debian-binary

# strip binaries
if test -z "$DONT_STRIP"; then
	# || true because failure to strip is not fatal
	find root/ -type f ! -name '*.ko' -print0| xargs -0 --no-run-if-empty ${STRIP} || true
else
	echo "${ME}: DONT_STRIP is set, not stripping anything"
fi

# modify / fix up control files
sed -i -e "s!@MAINT@!${MAINTAINER}!" -e "s!@ARCH@!${ARCH}!" CONTROL/control
chmod 0755 CONTROL/p* || true	# prerm, postrm, preinst, postinst
if test -e CONTROL/conffiles; then
	touch CONTROL/conffiles.new
	while read a; do
		if ! test -e root/$a; then
			echo "${ME}: WARNING conffile $a does not exist, skipping"
			continue;
		fi
		echo $a >> CONTROL/conffiles.new
	done < CONTROL/conffiles
	rm CONTROL/conffiles
	test -s CONTROL/conffiles.new && mv CONTROL/conffiles.new CONTROL/conffiles
fi

# the package name, needed for detection of already built old version...
NAME=$(awk '/^Package:/ {print $2}' CONTROL/control)
VERS=${VERSION%-*}  # strip off build revision
BREV=${VERSION##*-} # strip off package version

CACHEDIR=${PACKAGE_DIR}/.cache
CACHEFILE=${CACHEDIR}/${NAME}-${VERS}
# the version from the control file is overridden by the cached value
if test -e $CACHEFILE; then
	read BREV < $CACHEFILE
fi

rm -fr old* new*
# check if there is an old package and if yes, if it differs...
OPKGREV=`check_oldpackage`
if test $OPKGREV = 0; then
	# no action necessary...
	exit 0
fi

test $OPKGREV -gt $BREV && BREV=$OPKGREV
# if the package is not present, use the cached revision
test $OPKGREV != -1 && BREV=$(($BREV + 1))

#
# fix up build revision in control file
sed -i "s/^\(Version:.*-\)[0-9]*[[:space:]]*\$/\1${BREV}/" CONTROL/control
#
# update VERSION, used to pack the package
VERSION=${VERS}-${BREV}

# pack up root, list contents:
echo "${ME}: root contents:"
out=$(tar -cvzf data.tar.gz    --owner=0 --group=0 -C root .)
for file in $out; do
	# skip directories, they are not that interesting
	test "${file:$((${#file}-1))}" = "/" && continue
	# mark configfiles, makes it easier to check if everything is ok in control/conffiles
	if test -e CONTROL/conffiles && grep -q "^${file#.}$" CONTROL/conffiles; then
		echo "conf $file"
	elif test -L root/$file; then
		link=$(readlink root/$file)
		ldir=${file%/*}
		stat="  WARNING: broken link, check your package setup!"
		# tricky: absolute links needs to be resolved inside chroot...
		# echo "link: '${link}' ldir: '${ldir}' file: '${file}'"
		case $link in
		/proc/*)stat="" ;; # skip links to /proc/mounts etc...
		/*)	test -e root/$link  && stat="" || true ;;
		*)	readlink -qe root/$file >/dev/null && stat="" || true ;;
		esac
		echo "link $file -> $link $stat";
	else
		echo "     $file"
	fi
done

# pack control
echo "${ME}: control contents:"
tar -cvzf control.tar.gz --owner=0 --group=0 -C CONTROL .

# create the package...
PKG=${PACKAGE}-${VERSION}.opk
ar -r ${SOURCE}/${PKG} ./debian-binary ./data.tar.gz ./control.tar.gz

for i in $(ls ${PACKAGE_DIR}/${NAME}-${VERS}-*.opk 2>/dev/null); do
	test -d ${PACKAGE_DIR}/.old || mkdir ${PACKAGE_DIR}/.old
	echo "moving old package $i to ${PACKAGE_DIR}/.old"
	mv -v $i ${PACKAGE_DIR}/.old
done

cd $SOURCE
mv -v $PKG $PACKAGE_DIR
#
# update cache dir...
test -d $CACHEDIR || mkdir $CACHEDIR
rm -f $CACHEFILE
echo $BREV > $CACHEFILE

