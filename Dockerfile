# Copyright (c) 2020 Oracle and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl.
FROM oraclelinux:8-slim

# Install and enable the ULN client then disable the default repos from yum.oracle.com
RUN microdnf install dnf jq && \
    echo > /etc/dnf/vars/ociregion && \
    dnf -y module install satellite-5-client && \
    sed -i.bak -z 's/\[main\]\nenabled = 0/\[main\]\nenabled = 1/' /etc/dnf/plugins/spacewalk.conf && \
    dnf config-manager --disable ol8_baseos_latest --disable ol8_appstream && \
    dnf clean all

COPY /config/repo-map.json /config/
COPY entrypoint.sh /
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]

CMD ["sync"]
