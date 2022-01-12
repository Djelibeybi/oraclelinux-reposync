#!/bin/bash
# Copyright (c) 2020, 2021 Avi Miller.
# Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl.
if [ "$DEBUG" ]; then
  set -x
  QUIET=''
else
  set -e
  QUIET="--quiet"
fi

if [ -f /config/uln.conf ]; then
    # shellcheck source=../etc/.config/uln.sample.conf
    source /config/uln.conf
fi

TEMP_REPO_CONF=$(mktemp --quiet --directory --suffix="dnf")
cd "$TEMP_REPO_CONF"

# Get the GPG keys from uln-yum-mirror
echo "Downloading GPG keys from yum.oracle.com..."
dnf download $QUIET \
    --repo=ol8_addons \
    --disableplugin=spacewalk \
    --downloaddir="$TEMP_REPO_CONF" \
    --assumeyes \
    "uln-yum-mirror"

# Import the GPG keys into the rpm database
cd "$TEMP_REPO_CONF"
for uln_pkg in *.rpm; do
    rpm2cpio $uln_pkg | cpio --extract --make-directories --preserve-modification-time $QUIET
    rpm --import "$TEMP_REPO_CONF"/etc/pki/rpm-gpg/RPM-GPG-KEY-oracle-*
    rm -f "$uln_pkg"
done

# Download all the release RPMs
echo "Downloading release packages for Oracle Linux from yum.oracle.com..."
dnf download $QUIET \
    --disablerepo=* \
    --enablerepo=*_release_packages \
    --disableplugin=spacewalk \
    --downloaddir="$TEMP_REPO_CONF" \
    --assumeyes \
    "*-release-el?"

# Unpack the release RPMs
cd "$TEMP_REPO_CONF"
for repo_pkg in *.rpm; do
    # shellcheck disable=SC2086
    rpm2cpio $repo_pkg | cpio --extract --make-directories --preserve-modification-time $QUIET
    rm -f "$repo_pkg"
done

exec /usr/bin/python3 -u /update/repo-map.py "$TEMP_REPO_CONF/etc/yum.repos.d/"
