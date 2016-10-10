#!/bin/bash
#
# LICENSE INFORMATION
# 
# Copyright (c) 2016 IBM Corporation.
# All rights reserved.
#
# The Programs listed below are licensed under the following terms and
# conditions in addition to those of the IBM International License
# Agreement for Non-Warranted Programs (IBM form number Z125-5589-05).
#
# Program Name: IBM Software Development Kit for Linux on Power v1
# Program Number: SDK
#
# Source Components and Sample Materials
#
# The Program may include some components in source code form ("Source
# Components") and other materials identified as Sample Materials.
# Licensee may copy and modify Source Components and Sample Materials
# for internal use only provided such use is within the limits of the
# license rights under this Agreement, provided however that Licensee
# may not alter or delete any copyright information or notices
# contained in the Source Components or Sample Materials. IBM provides
# the Source Components and Sample Materials without obligation of
# support and "AS IS", WITH NO WARRANTY OF ANY KIND, EITHER EXPRESS OR
# IMPLIED, INCLUDING THE WARRANTY OF TITLE, NON-INFRINGEMENT OR
# NON-INTERFERENCE AND THE IMPLIED WARRANTIES AND CONDITIONS OF
# MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE.
#
# L/N:  L-WSMA-9PYJJ6
# D/N:  L-WSMA-9PYJJ6
# P/N:  L-WSMA-9PYJJ6
#
#   IBM Corporation, Paul Clarke- initial implementation and documentation.

echo
echo "Installation of IBM Software Development Kit for Linux on Power"
echo

[[ "$(id -u)" != 0 ]] && echo "This script must be run with root priviledges." && exit 1

if [[ ! ( "$1" == "--yes" || "$1" == "-y" ) ]]; then
	echo "This script will configure and enable new software repositories on this system, and install the IBM SDK for Linux on Power."
	read -N 1 -p 'Proceed? (y/N) ' p
	echo
	if [[ ! ( "$p" =~ [yY] ) ]]; then
		exit 1
	fi
fi

source /etc/os-release
case "$ID" in
	sles|sled)
		package_manager=zypper;;
	rhel|centos)
		package_manager=yum;;
	fedora)
		package_manager=dnf;;
	ubuntu)
		package_manager=apt-get;;
	*)
		echo unsupported operating system
		exit 1;;
esac

GET=""
GET2PIPE=""
if which curl >/dev/null; then
	GET="curl -O"
	GET2PIPE="curl"
elif which wget >/dev/null; then
	GET="wget"
	GET2PIPE="wget -O-"
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

# show the command to install IBM XL C/C++ for Linux, V13.1.4, Community Edition
function install_yum_distros {
	echo
	echo "To install IBM XL C/C++ for Linux, V13.1.4, Community Edition, issue the following commands:"
	echo
	echo "	sudo $package_manager install xlc.13.1.4 xlc-license-community.13.1.4 --exclude xlc-license-eval.13.1.4"
	echo "	sudo /opt/ibm/xlC/13.1.4/bin/xlc_configure"
}

function install_apt_distros {
	echo
        echo "To install IBM XL C/C++ for Linux, V13.1.4, Community Edition, issue the following commands:"
        echo
        echo "  sudo $package_manager install xlc.13.1.4 xlc-license-community.13.1.4"
        echo "  sudo /opt/ibm/xlC/13.1.4/bin/xlc_configure"
}

case "$package_manager" in
	yum|zypper|dnf)
		if ! rpm -q ibm-power-repo >/dev/null; then
			REPORPM=ibm-power-repo-latest.noarch.rpm
			download ftp://public.dhe.ibm.com/software/server/POWER/Linux/yum/download/$REPORPM \
				|| { echo "Download of IBM Power Tools Repository configuration RPM failed."; exit 1; }
			$package_manager install ./$REPORPM
			\rm -f ./$REPORPM

			/opt/ibm/lop/configure
		fi
		;;
	apt-get)
		apt-get install software-properties-common # for apt-add-repository

		REPO_URI=ftp://ftp.unicamp.br/pub/linuxpatch/toolchain/at/ubuntu

		# apt-key add 6976a827.gpg.key
		key="$(download2pipe $REPO_URI/dists/trusty/6976a827.gpg.key)"
		if [ $? -eq 0 ]; then
			echo "$key" | apt-key add -
		fi

		if [ "$(uname -p)" = x86_64 ]; then
			arch=' [arch=i386]'
		fi
		AT_RELEASES="$(download2pipe $REPO_URI/dists/trusty/Release | sed '/Components/s/^Components: \(.*\)$/\1/;tcontinue;d;:continue')"
		apt-add-repository "deb$arch $REPO_URI trusty $AT_RELEASES"

		REPO_URI=ftp://public.dhe.ibm.com/software/server/iplsdk/latest/packages/deb/repo

		# apt-key add B346CA20.gpg.key
		key="$(download2pipe $REPO_URI/dists/trusty/B346CA20.gpg.key)"
		if [ $? -eq 0 ]; then
			echo "$key" | apt-key add -
		fi

		if [ "$(uname -p)" = x86_64 ]; then
			arch=' [arch=amd64]'
		fi
		apt-add-repository "deb$arch $REPO_URI trusty sdk"

		apt-get update
		;;
	*)
		echo "I don't know how to set up your package management system.  Please refer to https://www-304.ibm.com/support/customercare/sas/f/lopdiags/home.html."
		exit 1
		;;
esac

# enable XL compiler repo
arch=$(uname -p)
if [ "$arch" = ppc64le ]; then
	XL_REPO_ROOT=http://public.dhe.ibm.com/software/server/POWER/Linux/xl-compiler/eval/$arch
	case "$ID" in
		sles|sled)
			# make sure it's 12!
			if [[ ${VERSION_ID%%.*} == 12 ]]; then
				zypper addrepo -c $XL_REPO_ROOT/sles12/ ibm-xl-compiler-eval
				zypper refresh
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
		ubuntu)
			download2pipe $XL_REPO_ROOT/ubuntu/public.gpg | apt-key add -
			apt-add-repository "deb $XL_REPO_ROOT/ubuntu/ trusty main"
			sudo apt-get update
			;;
	esac
fi

$package_manager install ibm-sdk-lop

case "$ID" in
	sles|sled|ubuntu)
		install_apt_distros
		;;
	rhel|centos|fedora)
		install_yum_distros
		;;
	*)
		echo unsupported operating system
		exit 1;;
esac

