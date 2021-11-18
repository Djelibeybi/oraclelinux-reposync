#!/bin/bash
#
# Copyright (c) 2020, 2022 Avi Miller.
# Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl.
# shellcheck disable=SC1091
#
set -e

# If the container is called with something besides sync or register, run that then exit.
if [ "$1" != "register" ] && [ "$1" != "sync" ] && [ "$1" != "update" ]; then
    exec "$@"
    exit 0
fi

# Check that all our directories are mounted
DIRS=("/repo" "/config")
REQ_FILES=("/config/repo-map.json" "/config/repos.json")
ULN_FILES=("/config/uln.conf" "/etc/sysconfig/rhn/systemid")
MISSING_DIRS=0

echo "Verifying required volume mounted directories have be configured:"
for DIR in "${DIRS[@]}"; do
    if [ ! -d "$DIR" ]; then
        echo "  => required directory $DIR not mounted."
        MISSING_DIRS=1
    else
        echo "  => required directory $DIR found."
    fi
done
echo ""

# Exit if any mounts are missing
if [ "$MISSING_DIRS" == 1 ]; then
    echo "One or more directories are missing. Exiting."
    echo ""
    exit 1
fi

echo "Verifying files required to sync:"
for FILE in "${REQ_FILES[@]}"; do
    if [ ! -f "$FILE" ]; then
        echo "  => required file $FILE not found: all repo sync disabled."
        NO_SYNC=1
    else
        echo "  => required file $FILE found."
    fi
done
echo ""

echo "Verifying files required for ULN sync:"
for FILE in "${ULN_FILES[@]}"; do
    if [ ! -f "$FILE" ]; then
        echo "  => required ULN configuration file $FILE not found: ULN repo sync disabled."
        NO_ULN_SYNC=1
    else
        echo "  => required ULN configuration file $FILE found."
    fi
done
echo ""

if [ "$1" == "update" ] || [ ! -f /config/repo-map.json ]; then
    . /update/repo-files.sh
    exit 0
fi

# Register with ULN first
if [ "$1" == "register" ] && [ -f /config/uln.conf ] && [ ! -f /etc/sysconfig/rhn/systemid ]; then
    . /config/uln.conf
    ULNREG_KS_OPTS=(--profilename=container-reposync --nohardware --nopackages --novirtinfo --norhnsd)
    ULNREG_KS_OPTS=("${ULNREG_KS_OPTS[@]}"  --username="${ULN_USERNAME}" --password "${ULN_PASSWORD}" --csi "${ULN_CSI}")

    # Try registering the server and if that works, enable the yum-server option
    if ulnreg_ks "${ULNREG_KS_OPTS[@]}"; then
        uln-channel --enable-yum-server
        echo "Successfully registered with ULN. Exiting."
    else
        echo "Error occured during ULN registration. Exiting."
        exit 1
    fi

    # Exit after registration
    exit 0
fi

####
## REPO SYNC
####

if [ "$NO_SYNC" = 1 ]; then
    exit 99
fi

# Test the repo configuration
if jq empty /config/repos.json 2>/dev/null; then
    echo "Verified /config/repos.json contains valid JSON."
else
    echo "Invalid JSON syntax in /config/repos.json. Stopping sync."
    exit 1
fi

# Find and sync the yum.oracle.com repos
if [ -f /config/repos.json ] && [ -d /repo ]; then
    echo "Starting sync."
    YUM_REPOS=$(jq -r 'select(.yum != null) | .yum[]' < /config/repos.json)
fi

DNF_ARG_DEFAULTS=(--norepopath --delete --download-metadata --remote-time)

if [ "$SYNC_SRC"  ]; then
    DNF_ARGS=("${DNF_ARGS[@]}" --excludepkgs=*src.rpm)
fi

if [ -z "$YUM_REPOS" ] || [ "$YUM_REPOS" == "" ]; then
    echo "No yum repos found to sync."
else
    for YUM_REPO in ${YUM_REPOS}; do
        DNF_ARGS=("${DNF_ARG_DEFAULTS[@]}")
        REPOPATH=$(jq -r --arg LABEL "$YUM_REPO" '.[] | select(.label==$LABEL) | .baseurl' < /config/repo-map.json)

        if [ "$REPOPATH" != "null" ]; then
            REPO_URL="https://yum.oracle.com${REPOPATH}"
            DNF_ARGS=("${DNF_ARGS[@]}" --repofrompath "$YUM_REPO,$REPO_URL" --repoid="$YUM_REPO" --download-path "${REPOPATH}")

            # Run DNF to sync the repo.
            dnf reposync "${DNF_ARGS[@]}"
        else
            echo "No yum.oracle.com repo URL found for label: $YUM_REPO."
        fi

    done
fi

if [ "$NO_ULN_SYNC" = 1 ]; then
    echo "ULN sync disabled. Exiting."
    exit 0
fi

# Enable, sync and then disable the ULN repos
if [ -f /etc/sysconfig/rhn/systemid ] && [ -f /config/uln.conf ]; then
    . /config/uln.conf
    ULN_REPOS=$(jq -r 'select(.uln != null) | .uln[]' < /config/repos.json)
fi

if [ -z "${ULN_REPOS}" ] || [ "${ULN_REPOS}" == "" ]; then
    echo "No ULN repos found to sync."
else
    for ULN_REPO in ${ULN_REPOS}; do

        # Try to subscribe to the ULN channel
        if uln-channel -u "${ULN_USERNAME}" -p "${ULN_PASSWORD}" -a -c "${ULN_REPO}" >/dev/null 2>&1; then

            REPOPATH=$(jq -r --arg ULN_REPO "$ULN_REPO" '.[] | select(.label==$ULN_REPO) | .baseurl' < /config/repo-map.json)
            DNF_ARGS=("${DNF_ARG_DEFAULTS[@]}" --repoid="${ULN_REPO}" --download-path "${REPOPATH}")

            # Sync the selected channel from ULN if the subscription was successful
            dnf reposync "${DNF_ARGS[@]}"

            # Unsubscribe from th channel
            uln-channel -u "${ULN_USERNAME}" -p "${ULN_PASSWORD}" -r -c "${ULN_REPO}" >/dev/null 2>&1
        else
            echo "No ULN repo found for label: ${ULN_REPO}."
        fi

    done
fi
