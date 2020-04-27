#!/bin/bash
: '

Copyright (C) 2018 IBM Corporation

Licensed under the Apache License, Version 2.0 (the “License”);
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

https://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an “AS IS” BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

	Contributors:
		* Paul Clarke <pacman@us.ibm.com>
'

function help () {
	cat <<EOF
Usage: $0 [--yes|-y] [--quiet]

This script configures the OpenPower SDK software repositories.
See https://developer.ibm.com/linuxonpower/sdk/ for more information.

  --yes
  -y            Proceed with configuration without a prompt to proceed.

  --quiet       Suppress progress output from commands being executed.
EOF
}

while [ $# -gt 0 ]; do
	case "$1" in
		"-y"|"--yes") PROCEED=yes;;
		"--quiet") QUIET="yes";;
		"--help"|"-h"|'-?') help; exit 0;;
	esac
	shift
done

if [ "$QUIET" != "yes" ]; then
	echo
	echo "Configuration of OpenPower SDK software repositories."
	echo
fi

[[ "$(id -u)" != 0 ]] && echo "This script must be run with root priviledges." && exit 1

if [ "$PROCEED" != "yes" ]; then
	echo "This script will configure and enable new software repositories on this system."
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
		package_manager="zypper $package_manager_quiet"
		if [ "$PROCEED" = "yes" ]; then
			package_manager="$package_manager --no-confirm"
		fi
		;;
	rhel|centos)
		package_manager="yum $package_manager_quiet"
		if [ "$PROCEED" = "yes" ]; then
			package_manager="$package_manager --assumeyes"
		fi
		;;
	fedora)
		package_manager="dnf $package_manager_quiet"
		if [ "$PROCEED" = "yes" ]; then
			package_manager="$package_manager --assumeyes"
		fi
		;;
	ubuntu|debian)
		package_manager="apt-get"
		if [ "$QUIET" = "yes" ]; then
			package_manager="$package_manager --quiet --quiet"
		fi
		if [ "$PROCEED" = "yes" ]; then
			package_manager="$package_manager --yes"
		fi
		;;
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
			REPORPM=ibm-power-repo-3.0.0-19.noarch.rpm
			download https://public.dhe.ibm.com/software/server/POWER/Linux/yum/download/$REPORPM \
				|| { echo "Download of IBM Power Tools Repository configuration RPM failed."; exit 1; }
			$package_manager install ./$REPORPM
			\rm -f ./$REPORPM

			if [ "$PROCEED" = yes ]; then
				# hack to configure without asking
				(function more { cat $*; }; export -f more; echo y | /opt/ibm/lop/configure)
			else
				/opt/ibm/lop/configure
			fi
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

		if [ "$QUIET" != "yes" ]; then echo "Install sofware-properties-common..."; fi
		$package_manager install software-properties-common # for apt-add-repository

		REPO_URI=https://public.dhe.ibm.com/software/server/POWER/Linux/toolchain/at/ubuntu

		if [ "$QUIET" != "yes" ]; then echo "Download $REPO_URI/dists/$CODENAME/6976a827.gpg.key..."; fi
		key="$(download2pipe $REPO_URI/dists/$CODENAME/6976a827.gpg.key)"
		if [ $? -eq 0 ]; then
			if [ "$QUIET" != "yes" ]; then echo "Add key 6976a827..."; fi
			echo "$key" | apt-key add -
		else
			echo "Download key 6976a827 FAILed!"
			exit 1
		fi

		if [ "$(uname -p)" = x86_64 ]; then
			arch=' [arch=amd64]'
		fi
		AT_RELEASES="$(download2pipe $REPO_URI/dists/$CODENAME/Release | sed '/Components/s/^Components: \(.*\)$/\1/;tcontinue;d;:continue')"
		if [ "$QUIET" != "yes" ]; then echo "Add repository \"deb$arch $REPO_URI $CODENAME $AT_RELEASES\""; fi
		apt-add-repository "deb$arch $REPO_URI $CODENAME $AT_RELEASES"

		REPO_URI=https://public.dhe.ibm.com/software/server/iplsdk/latest/packages/deb/repo

		if [ "$QUIET" != "yes" ]; then echo "Download $REPO_URI/dists/$CODENAME/B346CA20.gpg.key..."; fi
		key="$(download2pipe $REPO_URI/dists/$CODENAME/B346CA20.gpg.key)"
		if [ $? -eq 0 ]; then
			if [ "$QUIET" != "yes" ]; then echo "Add key B346CA20..."; fi
			echo "$key" | apt-key add -
		else
			echo "Download FAILed!"
			exit 1
		fi

		if [ "$(uname -p)" = x86_64 ]; then
			arch=' [arch=amd64]'
		fi
		if [ "$QUIET" != "yes" ]; then echo "Add repository \"deb$arch $REPO_URI $CODENAME sdk\""; fi
		apt-add-repository "deb$arch $REPO_URI $CODENAME sdk"

		if [ "$QUIET" != "yes" ]; then echo "Update repositories information..."; fi
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
	XL_REPO_ROOT=https://public.dhe.ibm.com/software/server/POWER/Linux/xl-compiler/eval/$arch
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
			if [[ ${VERSION_ID%%.*} -ge 7 ]]; then
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

if [ "$arch" = ppc64le -a "$QUIET" != yes ]; then
	echo
	echo "To install IBM XL C/C++ for Linux Community Edition, issue the following commands:"
	echo
	echo -e "\t/usr/bin/sudo $package_manager install xlc"
	echo -e "\t/usr/bin/sudo /opt/ibm/xlC/__version__/bin/xlc_configure"
fi

if [ "$QUIET" != "yes" ]; then
	echo "Configuration of OpenPower SDK software repositories is complete!"
fi
