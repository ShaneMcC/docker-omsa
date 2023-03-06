#!/bin/sh

if [ "" = "${OMSA_USER}" -o "" = "${OMSA_PASS}" ]; then
	echo 'Please specify OMSA_USER and OMSA_PASS env vars.'
	exit 1;
fi;

# Set login credentials
USER_EXISTS=`cat /etc/passwd | grep -i "^${OMSA_USER}:"`
if [ "${USER_EXISTS}" = "" ]; then
	echo "Creating user ${OMSA_USER}..."
	adduser "${OMSA_USER}"
fi;

echo "Setting login password for ${OMSA_USER}..."
echo "$OMSA_USER:$OMSA_PASS" | chpasswd

echo "Allowing ${OMSA_USER} access to openmanage..."
echo "${OMSA_USER}    *       Administrator" > /opt/dell/srvadmin/etc/omarolemap

echo "Setting up OMSA to start..."
echo '#!/bin/sh' > /etc/rc.local
echo "/opt/dell/srvadmin/sbin/srvadmin-services.sh restart" >> /etc/rc.local
chmod a+x /etc/rc.local

# Remove some things we don't want system starting.
if [ -e /usr/lib/systemd/system/getty@.service ]; then
	rm -Rfv /usr/lib/systemd/system/getty@.service
fi;

if [ -e /usr/lib/systemd/system/autovt@.service ]; then
	rm -Rfv /usr/lib/systemd/system/autovt@.service
fi;

# echo 'Enable rc.local';
# systemctl enable rc-local.service
# Removed due to https://bugzilla.redhat.com/show_bug.cgi?id=1516188

echo "Starting init..."
exec /sbin/init
