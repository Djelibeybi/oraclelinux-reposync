#!/usr/bin/env python3
# Copyright (c) 2020, 2022 Avi Miller.
# Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl.

import json
import logging
import configparser
import http.client
import datetime
import os
import xmlrpc.client
from urllib.parse import urlparse
import re
import sys
import urllib.request

ARCHS = ["aarch64", "ia64", "i386", "x86_64"]
REP_EL = "EnterpriseLinux"
REP_OL = "OracleLinux"
REP_ENG = "EngineeredSystems"
REP_OVM = "OracleVM"
REP_UNK = "unknown"
MAIN_KEEP = "exadata"
REGEX = r"^[Uu](\d+)"


log_level = logging.DEBUG if os.environ.get("DEBUG") is not None else logging.INFO

logging.basicConfig(
    level=log_level, format="%(asctime)s :: %(levelname)s :: %(message)s"
)
log = logging.getLogger("repo-map")


if len(sys.argv) != 2:
    log.error(f"Missing required parameter: repo_dir")
    exit(99)

YUM_REPOS_D = sys.argv[1]

if not os.path.exists(YUM_REPOS_D):
    log.error(f"Repo config path [{YUM_REPOS_D}] does not exist.")
    exit(98)


ULN_API = "https://linux-update.oracle.com/XMLRPC"
ULN_USERNAME = os.getenv("ULN_USERNAME", None)
ULN_PASSWORD = os.getenv("ULN_PASSWORD", None)

PROXY = (
    os.getenv("HTTPS_PROXY")
    if os.getenv("https_proxy") is None
    else os.getenv("https_proxy")
)


def check_repo_exists(url):
    """Checks if the URL is accessible."""
    request = urllib.request.Request(url)
    request.get_method = lambda: "HEAD"

    try:
        urllib.request.urlopen(request)
        return True
    except urllib.request.HTTPError:
        return False


def remove_suffix(input_string, suffix):
    if suffix and input_string.endswith(suffix):
        return input_string[: -len(suffix)]
    return input_string


def build_repo_dir(label):
    """
    This is a reimplementation of the same repo path generation logic as used
    by the existing uln-yum-mirror script.
    """

    repo_arch = [arch for arch in ARCHS if (arch in label)][0]
    label_noarch = (
        str(label).replace(repo_arch, "").replace(r"__", "_").replace("-", "_")
    )

    split = label_noarch.split("_", 1)
    rep_main = split[0].capitalize() if MAIN_KEEP in split[0] else split[0].upper()
    remain = split[1]

    rep_remain = (
        re.sub(REGEX, "\\1", remain)
        .replace("oracle_addons", "oracle-addons")
        .replace("Dtrace_", "Dtrace-")
        .replace("gdm_", "gdm")
        .replace("_", "/")
        .replace("-", "_")
    )

    dir = f"{rep_main}/{rep_remain}/{repo_arch}"
    if label.startswith("exadata"):
        repo_dir = f"/repo/{REP_ENG}/{dir}"
    elif label.startswith("el"):
        repo_dir = f"/repo/{REP_EL}/{dir}"
    elif label.startswith("ol"):
        repo_dir = f"/repo/{REP_OL}/{dir}"
    elif label.startswith("ovirt"):
        repo_dir = f"/repo/{REP_OL}/{dir}"
    elif label.startswith("ovm"):
        repo_dir = f"/repo/{REP_OVM}/{dir}"
    else:
        repo_dir = f"/repo/{REP_UNK}/{dir}"

    return repo_dir


class ProxiedTransport(xmlrpc.client.Transport):
    def set_proxy(self, host, port=None, headers=None):
        self.proxy = host, port
        self.proxy_headers = headers

    def make_connection(self, host):
        connection = http.client.HTTPConnection(*self.proxy)
        connection.set_tunnel(host, headers=self.proxy_headers)
        self._connection = host, connection
        return connection


repo_map = []
uln_channel_map = {}
yum_repo_map = {}
yum_repo_conf = configparser.ConfigParser()
backup_date = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
uln_channel_update = False

log.info(f"Updating repo definitions: {YUM_REPOS_D}")
repos_processed = 0

for file in os.scandir(YUM_REPOS_D):
    if file.is_file() and file.name.endswith(".repo"):
        yum_repo_conf.read(os.path.join(YUM_REPOS_D, file.name))
        for repo in yum_repo_conf.sections():
            log.debug(f"Processing {repo}")
            repos_processed += 1
            yum_repo_map[repo] = remove_suffix(
                str(yum_repo_conf.get(repo, "baseurl"))
                .replace("$ociregion", "")
                .replace("$ocidomain", "oracle.com")
                .replace("https://yum.oracle.com", "")
                .strip()
                if yum_repo_conf.has_option(repo, "baseurl")
                else None,
                "/",
            )
            log.debug(f"Stored {repo}: {yum_repo_map[repo]}")


if repos_processed == 0:
    log.error("No repo files found.")
    exit(96)


if ULN_USERNAME is not None and ULN_PASSWORD is not None:

    transport = None
    if PROXY is not None:
        proxy_config = urlparse(PROXY)
        transport = ProxiedTransport()
        transport.set_proxy(proxy_config.hostname, proxy_config.port)
        log.info(f"Setting proxy to: {proxy_config.hostname}:{proxy_config.port}")

    uln = (
        xmlrpc.client.ServerProxy(ULN_API)
        if transport is None
        else xmlrpc.client.ServerProxy(ULN_API, transport=transport)
    )

    sessionKey = ""
    channels = ""
    try:
        log.info("Retrieving channel definitions from ULN.")
        sessionKey = uln.auth.login(ULN_USERNAME, ULN_PASSWORD)
        channels = uln.channel.listSoftwareChannels(sessionKey)
    except xmlrpc.client.Error as err:
        log.error("ERROR: %s", err)

    uln_channel_update = True

    if len(channels) > 0:
        for channel in channels:
            arch = str(channel["channel_arch"])
            label = str(channel["channel_label"])
            name = str(channel["channel_name"])
            if label not in uln_channel_map:
                uln_channel_map[label] = {"name": name, "archs": [arch]}
            else:
                uln_channel_map[label]["archs"] += [arch]

if uln_channel_update:
    for channel in uln_channel_map:
        yum_channel = channel.replace(f"{arch}_", "")
        log.info(f"Processing: [{channel}]")
        if yum_channel in yum_repo_map:
            repo_dir = str(yum_repo_map[yum_channel]).replace("$basearch", arch)
        else:
            repo_dir = build_repo_dir(channel)

        channel = str(channel).replace("-", "_")
        repo_map.append({"label": channel, "baseurl": repo_dir})
        log.debug(f"Configuring ULN channel [{channel}] to use path: {repo_dir}")
else:
    for yum_repo in yum_repo_map:
        log.info(f"Processing {yum_repo}: {yum_repo_map[yum_repo]}")
        for arch in ["x86_64", "aarch64"]:
            arch_url = f"https://yum.oracle.com{str(yum_repo_map[yum_repo]).replace('$basearch', arch)}/repodata/repomd.xml"
            if check_repo_exists(arch_url):
                new_label = str(yum_repo).replace("-", "_")
                if "_" in str(yum_repo):
                    tmp_label = str(yum_repo).split("_", 1)
                    new_label = "_".join([tmp_label[0], arch, tmp_label[1]])

                log.debug(
                    f"Verified: {arch} for {yum_repo}. Saving {new_label} as {yum_repo_map[yum_repo].replace('$basearch', arch)}."
                )
                repo_map.append(
                    {
                        "label": new_label,
                        "baseurl": yum_repo_map[yum_repo].replace("$basearch", arch),
                    }
                )


# Write out the new repo map
if os.path.exists("/config/repo-map.json"):
    log.info(f"Moving existing repo map to /config/repo-map.json.{backup_date}")
    os.rename("/config/repo-map.json", f"/config/repo-map.json.{backup_date}")

with open("/config/repo-map.json", "w") as new_repo_map:
    new_repo_map.write(json.dumps(repo_map, indent=4, sort_keys=True))
    new_repo_map.close()

log.info("Wrote new repo map to /config/repo-map.json")
