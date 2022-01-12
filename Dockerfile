# Copyright (c) 2020, 2021 Avi Miller.
# Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl.
FROM ghcr.io/oracle/oraclelinux8-python:3.9

RUN  echo > /etc/dnf/vars/ociregion && \
     dnf -y module enable satellite-5-client && \
     dnf -y install cpio jq dnf-plugin-spacewalk python3-dnf-plugin-ulninfo rhn-setup rhnlib rhnsd rhn-client-tools tar && \
     sed -i.bak -z 's/\[main\]\nenabled = 0/\[main\]\nenabled = 1/' /etc/dnf/plugins/spacewalk.conf && \
     dnf clean all

COPY rootfs/ /

RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]

CMD ["sync"]
