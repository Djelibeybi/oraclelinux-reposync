#!/bin/bash
#
# Copyright (c) 2020, 2021 Avi Miller.
# Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl.
# shellcheck disable=SC1091
#
set -e

# If the container is called with something besides sync or register, run that
if [ "${1}" != "register" ] && [ "${1}" != "sync" ]; then
    exec "$@"
fi

# Register with ULN first
if [ "${1}" == "register" ] && [ -f /config/uln.conf ] && [ ! -f /etc/sysconfig/rhn/systemid ]; then
    source /config/uln.conf
    ULNREG_KS_OPTS="--profilename=container-reposync --username=${ULN_USERNAME} \
                    --password ${ULN_PASSWORD} --csi ${ULN_CSI} \
                    --nohardware --nopackages --novirtinfo --norhnsd"

    if ulnreg_ks "${ULNREG_KS_OPTS}"; then
        uln-channel --enable-yum-server
    else
        echo "Error occured during ULN registration."
        exit 1
    fi
fi

# Test the repo configuration
if ! jq . >/dev/null 2>&1 <<</config/repos.json; then
    echo "Invalid JSON syntax in /config/repos.json"
    exit 1
fi

# Find and sync the yum.oracle.com repos
if [ -f /config/repos.json ] && [ -d /repo ]; then
    echo "Starting sync."
    YUM_REPOS=$(jq -r 'select(.yum != null) | .yum[]' < /config/repos.json)
fi

if [ -z "${YUM_REPOS}" ] || [ "${YUM_REPOS}" == "" ]; then
    echo "No yum repos found to sync."
else
    for YUM_REPO in ${YUM_REPOS}; do
        REPOPATH=$(jq -r ".${YUM_REPO}" < /config/repo-map.json)

        if [ "$REPOPATH" != "null" ]; then
            REPO_URL="https://yum.oracle.com${REPOPATH}"
            dnf reposync --repofrompath "${YUM_REPO},${REPO_URL}" \
                     --repoid="${YUM_REPO}" --norepopath \
                     --delete --download-metadata --remote-time \
                     --download-path "${REPOPATH}"
        else
            echo "No yum.oracle.com repo URL found for label: ${YUM_REPO}."
        fi

    done
fi

# Enable, sync and then disable the ULN repos
if [ -f /etc/sysconfig/rhn/systemid ] && [ -f /config/uln.conf ]; then
    source /config/uln.conf
    ULN_REPOS=$(jq -r 'select(.uln != null) | .uln[]' < /config/repos.json)
fi

if [ -z "${ULN_REPOS}" ] || [ "${ULN_REPOS}" == "" ]; then
    echo "No ULN repos found to sync."
else
    for ULN_REPO in ${ULN_REPOS}; do

        if uln-channel -u "${ULN_USERNAME}" -p "${ULN_PASSWORD}" -a -c "${ULN_REPO}" >/dev/null 2>&1; then
            REPOPATH=$(jq -r ".${ULN_REPO}" < /config/repo-map.json)
            dnf reposync --repoid="${ULN_REPO}" --remote-time \
                         --delete --download-metadata --norepopath \
                         --download-path "${REPOPATH}"
            uln-channel -u "${ULN_USERNAME}" -p "${ULN_PASSWORD}" -r -c "${ULN_REPO}" >/dev/null 2>&1
        else
            echo "No ULN repo found for label: ${ULN_REPO}."
        fi

    done
fi
