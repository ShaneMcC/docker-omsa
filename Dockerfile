FROM almalinux:9.8-minimal-20260902
LABEL org.opencontainers.image.authors="Shane Mc Cormack <dataforce@dataforce.org.uk>"
LABEL org.opencontainers.image.description="Dell OpenManage Server Administrator in Docker."
LABEL org.opencontainers.image.url="https://github.com/ShaneMcC/docker-omsa"

# Environment variables
ENV PATH=$PATH:/opt/dell/srvadmin/bin:/opt/dell/srvadmin/sbin

# Do overall system update, install missing packages needed for OpenManage,
# Add OMSA repo and install OMSA ("install all"), then clean up afterwards
#
# `passwd` is needed by our startup script
# `procps` is needed by some of the startup scripts
# `kmod` is needed to allow `/etc/init.d/instsvcdrv` to run
# `crb` repo is needed for `openwsman-client` which is needed by `srvadmin-tomcat`
# `yum` symlink is required for `dsu` to install the catalog
# `tar` and `which` are required for `dsu` to generate it's inventory
# `crypto-policies-scripts` is needed to allow SHA1 hashes
#
# Other requirements should be pulled in automatically by the bootstrap file
#
# Also clean up unneeded tomcat files
RUN sed -i 's/enabled=0/enabled=1/' /etc/yum.repos.d/almalinux-crb.repo && \
    ln -s /usr/bin/microdnf /usr/bin/dnf && \
    ln -s /usr/bin/microdnf /usr/bin/yum && \
    dnf -y update && \
    dnf -y install passwd procps kmod tar which crypto-policies-scripts && \
    dnf clean all

ADD --checksum=sha256:4b78b378694dc78e96db40eccef8bf77f03dde534408a79bdeb0ee37c47abab7 https://linux.dell.com/repo/hardware/dsu/copygpgkeys.sh /tmp/copygpgkeys.sh
RUN bash /tmp/copygpgkeys.sh

ADD --checksum=sha256:39a9aa68a98be304072cdbff2e506808c2d2ec0dad0082e2ffde7f9e67a06d1c https://linux.dell.com/repo/hardware/dsu/bootstrap.cgi /tmp/bootstrap.sh
RUN sed -i 's/IMPORT_GPG_CONFIRMATION="na"/IMPORT_GPG_CONFIRMATION="yes"/' /tmp/bootstrap.sh && \
    bash /tmp/bootstrap.sh && \
    update-crypto-policies --set DEFAULT:SHA1

RUN dnf -y install srvadmin-all-11.1.0.0-5773.el9 dell-system-update-2.3.0.1-26.08.00 && \
    dnf clean all && \
    rm -Rfv /usr/lib/systemd/system/autovt@.service /usr/lib/systemd/system/getty@.service /tmp/bootstrap.sh /tmp/copygpgkeys.sh && \
    rm -Rfv /opt/dell/srvadmin/lib64/openmanage/apache-tomcat/webapps/manager /opt/dell/srvadmin/lib64/openmanage/apache-tomcat/webapps/host-manager /opt/dell/srvadmin/lib64/openmanage/apache-tomcat/webapps/ROOT/*

# Make OMSA start..."
COPY ./docker/rc.local /etc/rc.local

# Prevent daemon helper scripts from making systemd calls
ENV SYSTEMCTL_SKIP_REDIRECT=1

COPY ./docker/run.sh /run.sh

# Run the application
CMD ["/run.sh"]
