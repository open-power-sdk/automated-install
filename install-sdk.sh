#!/bin/bash
: '

Copyright (C) 2017 IBM Corporation

Licensed under the Apache License, Version 2.0 (the “License”);
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an “AS IS” BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

	Contributors:
		* Paul Clarke <pacman@us.ibm.com>
'

while [ $# -gt 0 ]; do
	case "$1" in
		"-y"|"--yes") PROCEED=yes;;
		"--repos-only") REPOS_ONLY=yes;;
		"--quiet") QUIET="yes";;
	esac
	shift
done

if [ "$QUIET" != "yes" ]; then
	echo
	echo "Installation of IBM Software Development Kit for Linux on Power"
	echo
fi

[[ "$(id -u)" != 0 ]] && echo "This script must be run with root priviledges." && exit 1

if [ "$PROCEED" != "yes" ]; then
	echo "This script will configure and enable new software repositories on this system, and install the IBM SDK for Linux on Power."
	read -N 1 -p 'Proceed? (y/N) ' p
	echo
	if [[ ! ( "$p" =~ [yY] ) ]]; then
		exit 1
	fi
fi

if [ "$QUIET" = "yes" ]; then
	package_manager_quiet="--quiet"
fi

source /etc/os-release
case "$ID" in
	sles|sled)
		package_manager="zypper $package_manager_quiet";;
	rhel|centos)
		package_manager="yum $package_manager_quiet";;
	fedora)
		package_manager="dnf $package_manager_quiet";;
	ubuntu|debian)
		if [ "$QUIET" = "yes" ]; then
			package_manager_quiet="--quiet --quiet"
		fi
		package_manager="apt-get $package_manager_quiet";;
	*)
		echo unsupported operating system
		exit 1;;
esac

GET=""
GET2PIPE=""
if which curl >/dev/null; then
	if [ "$QUIET" = "yes" ]; then
		GETQUIET="--silent"
	fi
	GET="curl $GETQUIET -O"
	GET2PIPE="curl $GETQUIET"
elif which wget >/dev/null; then
	if [ "$QUIET" = "yes" ]; then
		GETQUIET="--quiet"
	fi
	GET="wget $GETQUIET"
	GET2PIPE="wget $GETQUIET -O-"
fi

function download {
	if [ -z "$GET" ]; then
		echo "I need curl or wget to continue"; exit 1
	fi
	$GET $@
}

function download2pipe {
	if [ -z "$GET2PIPE" ]; then
		echo "I need curl or wget to continue"; exit 1
	fi
	$GET2PIPE $@
}

case "$package_manager" in
	yum*|zypper*|dnf*)
		if ! rpm -q ibm-power-repo >/dev/null; then
			REPORPM=ibm-power-repo-latest.noarch.rpm
			download ftp://public.dhe.ibm.com/software/server/POWER/Linux/yum/download/$REPORPM \
				|| { echo "Download of IBM Power Tools Repository configuration RPM failed."; exit 1; }
			$package_manager install ./$REPORPM
			\rm -f ./$REPORPM

			/opt/ibm/lop/configure
		fi
		;;
	apt-get*)
		if [ -z "$VERSION_CODENAME" ]; then
			if [ -z "$UBUNTU_CODENAME" ]; then
				if [ -r /etc/lsb-release ]; then
					source /etc/lsb-release
					UBUNTU_CODENAME="$DISTRIB_CODENAME"
				elif [ "$ID" = debian ]; then
					case "$VERSION_ID" in
						8) UBUNTU_CODENAME=trusty;;
						9) UBUNTU_CODENAME=xenial;;
					esac
				fi
			fi
			VERSION_CODENAME="$UBUNTU_CODENAME"
		fi
		CODENAME="$VERSION_CODENAME"
		if [ "$CODENAME" = "" ]; then
			echo "I am unable to determine your release name, which I need to retrieve keys and set up the repositories."
			exit 1
		fi

		$package_manager install software-properties-common # for apt-add-repository

		REPO_URI=ftp://ftp.unicamp.br/pub/linuxpatch/toolchain/at/ubuntu

		# apt-key add 6976a827.gpg.key
		key="$(download2pipe $REPO_URI/dists/$CODENAME/6976a827.gpg.key)"
		if [ $? -eq 0 ]; then
			echo "$key" | apt-key add -
		fi

		if [ "$(uname -p)" = x86_64 ]; then
			arch=' [arch=amd64]'
		fi
		AT_RELEASES="$(download2pipe $REPO_URI/dists/$CODENAME/Release | sed '/Components/s/^Components: \(.*\)$/\1/;tcontinue;d;:continue')"
		apt-add-repository "deb$arch $REPO_URI $CODENAME $AT_RELEASES"

		REPO_URI=ftp://public.dhe.ibm.com/software/server/iplsdk/latest/packages/deb/repo

		# apt-key add B346CA20.gpg.key
		key="$(download2pipe $REPO_URI/dists/$CODENAME/B346CA20.gpg.key)"
		if [ $? -eq 0 ]; then
			echo "$key" | apt-key add -
		fi

		if [ "$(uname -p)" = x86_64 ]; then
			arch=' [arch=amd64]'
		fi
		apt-add-repository "deb$arch $REPO_URI $CODENAME sdk"

		$package_manager update
		;;
	*)
		echo "I don't know how to set up your package management system.  Please refer to https://www-304.ibm.com/support/customercare/sas/f/lopdiags/home.html."
		exit 1
		;;
esac

# enable XL compiler repo
arch=$(uname -m)
if [ "$arch" = ppc64le ]; then
	XL_REPO_ROOT=http://public.dhe.ibm.com/software/server/POWER/Linux/xl-compiler/eval/$arch
	case "$ID" in
		sles|sled)
			# make sure it's 12!
			if [[ ${VERSION_ID%%.*} == 12 ]]; then
				zypper addrepo -c $XL_REPO_ROOT/sles12/ ibm-xl-compiler-eval
				$package_manager refresh
			fi
			;;
		rhel|centos)
			# make sure it's 7
			if [[ ${VERSION_ID%%.*} == 7 ]]; then
				download $XL_REPO_ROOT/rhel7/repodata/repomd.xml.key
				rpm --import repomd.xml.key
				rm -f repomd.xml.key
				download2pipe $XL_REPO_ROOT/rhel7/ibm-xl-compiler-eval.repo > /etc/yum.repos.d/ibm-xl-compiler-eval.repo
			fi
			;;
		fedora)
			download $XL_REPO_ROOT/rhel7/repodata/repomd.xml.key
			rpm --import repomd.xml.key
			rm -f repomd.xml.key
			download2pipe $XL_REPO_ROOT/rhel7/ibm-xl-compiler-eval.repo > /etc/yum.repos.d/ibm-xl-compiler-eval.repo
			;;
		ubuntu|debian)
			key="$(download2pipe $XL_REPO_ROOT/ubuntu/public.gpg)"
			if [ $? -eq 0 ]; then
				echo "$key" | apt-key add -
			fi
			apt-add-repository "deb $XL_REPO_ROOT/ubuntu/ $CODENAME main"
			sudo $package_manager update
			;;
	esac
fi

if [ "$REPOS_ONLY" != yes ]; then
	$package_manager install ibm-sdk-lop

	echo
	echo "Installation of IBM Software Development Kit for Linux on Power complete!"
fi

if [ "$arch" = ppc64le -a "$QUIET" != yes ]; then
	echo
	echo "To install IBM XL C/C++ for Linux Community Edition, issue the following commands:"
	echo
	echo -e "\t/usr/bin/sudo $package_manager install xlc"
	echo -e "\t/usr/bin/sudo /opt/ibm/xlC/__version__/bin/xlc_configure"
fi
