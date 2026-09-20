#!/bin/sh

echo "Started at $(date)"

if [ -z "${OMSA_USER}" ] || [ -z "${OMSA_PASS}" ]; then
	echo 'Please specify OMSA_USER and OMSA_PASS env vars.'
	exit 1
fi

# Set login credentials
#
# "--" ends the options: without it a username that begins with "-" is read as
# an option rather than as a name. "getent passwd -x" answers "invalid option
# -- 'x'" and exits 64, not "no such user", so the lookup fails for the wrong
# reason and we go on to create an account that useradd then refuses too.
if ! getent passwd -- "${OMSA_USER}" >/dev/null; then
	echo "Creating user ${OMSA_USER}..."
	if ! adduser -- "${OMSA_USER}"; then
		echo "Failed to create user ${OMSA_USER}." >&2
		exit 1
	fi
fi

# printf rather than echo, because echo has no portable way of being told to
# stop looking for options: a username beginning with "-n" or "-e" is eaten as
# one instead of reaching chpasswd.
echo "Setting login password for ${OMSA_USER}..."
if ! printf '%s:%s\n' "${OMSA_USER}" "${OMSA_PASS}" | chpasswd; then
	echo "Failed to set the password for ${OMSA_USER}." >&2
	exit 1
fi

echo "Allowing ${OMSA_USER} access to openmanage..."
echo "${OMSA_USER}    *       Administrator" > /opt/dell/srvadmin/etc/omarolemap

if [ "${UNCERTIFIED_DRIVES}" = "1" ] || [ "${UNCERTIFIED_DRIVES}" = "yes" ]; then
	echo "Allow non-certified drives..."
	sed -i 's/^NonDellCertifiedFlag=.*$/NonDellCertifiedFlag=no/' /opt/dell/srvadmin/etc/srvadmin-storage/stsvc.ini
else
	# Reset to default.
	sed -i 's/^NonDellCertifiedFlag=.*$/NonDellCertifiedFlag=yes/' /opt/dell/srvadmin/etc/srvadmin-storage/stsvc.ini
fi

echo "Clearing old tmp files..."
rm -Rf /tmp/* /var/tmp/*

echo "Starting init..."
exec /sbin/init
