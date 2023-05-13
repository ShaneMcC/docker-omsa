FROM almalinux:9.2-minimal-20230512
MAINTAINER Shane Mc Cormack <dataforce@dataforce.org.uk>
LABEL org.opencontainers.image.authors "Shane Mc Cormack <dataforce@dataforce.org.uk>"
LABEL org.opencontainers.image.description "Dell OpenManage Server Administrator in Docker."
LABEL org.opencontainers.image.url "https://github.com/ShaneMcC/docker-omsa"

# Environment variables
ENV PATH $PATH:/opt/dell/srvadmin/bin:/opt/dell/srvadmin/sbin

# Do overall system update, install missing packages needed for OpenManage,
# Add OMSA repo and install OMSA ("install all"), then clean up afterwards
#
# `passwd` is needed by our startup script
# `procps` is needed by some of the startup scripts
# `kmod` is needed to allow `/etc/init.d/instsvcdrv` to run
# `crb` repo is needed for `openwsman-client` which is needed by `srvadmin-tomcat`
# `yum` symlink is required for `dsu` to install the catalog
# `tar` and `which` are required for `dsu` to generate it's inventory
#
# Other requirements should be pulled in automatically by the bootstrap file
#
ADD https://linux.dell.com/repo/hardware/dsu/bootstrap.cgi /tmp/bootstrap.sh-e91e4f6d6a4b8b1b618bd5b8b6a4c484
ADD https://linux.dell.com/repo/hardware/dsu/copygpgkeys.sh /tmp/copygpgkeys.sh-7f7d16b78bc4f06e6bb8b6a217cbbd40
RUN sed -i 's/enabled=0/enabled=1/' /etc/yum.repos.d/almalinux-crb.repo && \
    ln -s /usr/bin/microdnf /usr/bin/dnf && \
    ln -s /usr/bin/microdnf /usr/bin/yum && \
    dnf -y update && \
    dnf -y install passwd procps kmod tar which && \
    cat /tmp/copygpgkeys.sh-7f7d16b78bc4f06e6bb8b6a217cbbd40 | bash && \
    sed -i 's/IMPORT_GPG_CONFIRMATION="na"/IMPORT_GPG_CONFIRMATION="yes"/' /tmp/bootstrap.sh-e91e4f6d6a4b8b1b618bd5b8b6a4c484 && \
    cat /tmp/bootstrap.sh-e91e4f6d6a4b8b1b618bd5b8b6a4c484 | bash && \
    dnf -y install srvadmin-all-11.0.0.0-5268.el9 dell-system-update-2.0.2.0-23.03.00 && \
    dnf clean all && \
    rm -Rfv /usr/lib/systemd/system/autovt@.service /usr/lib/systemd/system/getty@.service /tmp/bootstrap.sh-e91e4f6d6a4b8b1b618bd5b8b6a4c484 /tmp/copygpgkeys.sh-7f7d16b78bc4f06e6bb8b6a217cbbd40

# Make OMSA start..."
COPY ./docker/rc.local /etc/rc.local

# Prevent daemon helper scripts from making systemd calls
ENV SYSTEMCTL_SKIP_REDIRECT=1

COPY ./docker/run.sh /run.sh

# Run the application
CMD /run.sh
