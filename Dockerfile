# Use CentOS 7 base image from Docker Hub
# FROM centos:centos7.6
FROM almalinux:8.7
MAINTAINER Shane Mc Cormack <dataforce@dataforce.org.uk>

# Environment variables
ENV PATH $PATH:/opt/dell/srvadmin/bin:/opt/dell/srvadmin/sbin

# Do overall system update, install missing packages needed for OpenManage,
# Add OMSA repo and install OMSA ("install all"), then clean up afterwards
#
# `passwd` is needed by our startup script
# `procps` is needed by some of the startup scripts
# `kmod` is needed to allow `/etc/init.d/instsvcdrv` to run
#
# Other requirements should be pulled in automatically by the bootstrap file
ADD https://linux.dell.com/repo/hardware/dsu/bootstrap.cgi /tmp/bootstrap.sh
RUN dnf -y update && \
    dnf -y install passwd procps kmod && \
    cat /tmp/bootstrap.sh | bash && \
    dnf -y install srvadmin-all && \
    dnf clean all && \
    rm -Rfv /usr/lib/systemd/system/autovt@.service /usr/lib/systemd/system/getty@.service /tmp/bootstrap.sh

# Make OMSA start..."
COPY ./docker/rc.local /etc/rc.local

# Prevent daemon helper scripts from making systemd calls
ENV SYSTEMCTL_SKIP_REDIRECT=1

COPY ./docker/run.sh /run.sh

# Run the application
CMD /run.sh
