# Use CentOS 7 base image from Docker Hub
# FROM centos:centos7.6
FROM almalinux:8.7
MAINTAINER Shane Mc Cormack <dataforce@dataforce.org.uk>

# Environment variables
ENV PATH $PATH:/opt/dell/srvadmin/bin:/opt/dell/srvadmin/sbin

# Do overall update and install missing packages needed for OpenManage
RUN dnf -y update && \
    dnf -y install wget perl passwd which procps


#    dnf -y install gcc wget perl passwd which tar libstdc++.so.6 procps

# Add OMSA repo.
RUN wget -q -O -  https://linux.dell.com/repo/hardware/dsu/bootstrap.cgi | bash

# Let's "install all", however we can select specific components instead
RUN dnf -y install srvadmin-all && dnf clean all

# Remove unneeded files
RUN rm -Rfv /usr/lib/systemd/system/autovt@.service /usr/lib/systemd/system/getty@.service

# Make OMSA start..."
COPY ./docker/rc.local /etc/rc.local

# Prevent daemon helper scripts from making systemd calls
ENV SYSTEMCTL_SKIP_REDIRECT=1

COPY ./docker/run.sh /run.sh

# Run the application
CMD /run.sh
