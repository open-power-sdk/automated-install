#!/bin/bash
###############################################################################
# Copyright (c) 2016 IBM Corporation.
# All rights reserved. This program is made available under the terms of
# the Eclipse Public License v1.0, which is available at
# http://www.eclipse.org/legal/epl-v10.html
###############################################################################

source /etc/os-release
case "$NAME" in
	SLES|SLED)
		package_manager=zypper;;
	"Red Hat "*|"CentOS"*)
		package_manager=yum;;
	Fedora)
		package_manager=dnf;;
	Ubuntu)
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

case "$package_manager" in
	yum|zypper|dnf)
		if ! rpm -q ibm-power-repo >/dev/null; then
			REPORPM=ibm-power-repo-3.0.0-8.noarch.rpm
			download ftp://public.dhe.ibm.com/software/server/POWER/Linux/yum/download/$REPORPM \
				|| { echo "Download of IBM Power Tools Repository configuration RPM failed."; exit 1; }
			$package_manager install ./$REPORPM
			\rm -f ./$REPORPM

			/opt/ibm/lop/configure
		fi
		;;
	apt-get)
		apt-get install software-properties-common # for apt-add-repository

		# apt-key add 6976a827.gpg.key
		key="$(download2pipe ftp://ftp.unicamp.br/pub/linuxpatch/toolchain/at/ubuntu/dists/precise/6976a827.gpg.key)"
		if [ $? -eq 0 ]; then
			echo "$key" | apt-key add -
		fi

		if [ "$(uname -p)" = x86_64 ]; then
			arch=' [arch=i386]'
		fi
		apt-add-repository "deb$arch ftp://ftp.unicamp.br/pub/linuxpatch/toolchain/at/ubuntu trusty at9.0"

		# apt-key add F20E8D79.gpg.key
		key="$(download2pipe ftp://public.dhe.ibm.com/software/server/iplsdk/v1.8.0/packages/deb/repo/dists/trusty/F20E8D79.gpg.key)"
		if [ $? -eq 0 ]; then
			echo "$key" | apt-key add -
		fi

		if [ "$(uname -p)" = x86_64 ]; then
			arch=' [arch=amd64]'
		fi
		apt-add-repository "deb$arch ftp://public.dhe.ibm.com/software/server/iplsdk/v1.8.0/packages/deb/repo trusty sdk-1.8"

		apt-get update

		#apt-get install advance-toolchain-at9.0-runtime advance-toolchain-at9.0-devel advance-toolchain-at9.0-perf advance-toolchain-at9.0-mcore-libs
		;;
	*)
		echo "I don't know how to set up your package management system.  Please refer to https://www-304.ibm.com/support/customercare/sas/f/lopdiags/home.html."
		exit 1
		;;
esac

$package_manager install ibm-sdk-lop
