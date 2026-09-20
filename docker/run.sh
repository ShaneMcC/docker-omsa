#!/bin/sh

echo "Started at $(date)"

HAS_ERROR=0
if [ -z "${OMSA_USER}" ] && [ -z "${OMSA_USER_FILE}" ]; then
	echo 'Please specify OMSA_USER or OMSA_USER_FILE env vars.'
	HAS_ERROR=1
elif [ -n "${OMSA_USER}" ] && [ -n "${OMSA_USER_FILE}" ]; then
	echo 'Please specify OMSA_USER or OMSA_USER_FILE env vars, not both.'
	HAS_ERROR=1
elif [ -n "${OMSA_USER_FILE}" ]; then
	if [ -r "${OMSA_USER_FILE}" ]; then
		OMSA_USER=$(head -n 1 "${OMSA_USER_FILE}")
		if [ -z "${OMSA_USER}" ]; then
			echo 'OMSA_USER_FILE does not contain a valid user.'
			HAS_ERROR=1
		fi;
	else
		echo 'OMSA_USER_FILE is not a valid file. ('"${OMSA_USER_FILE}"')'
		HAS_ERROR=1
	fi
fi

if [ "$(printf '%s' "${OMSA_USER}" | cut -c 1)" = '-' ]; then
	echo 'OMSA_USER can not start with a "-".'
	HAS_ERROR=1
fi

if [ -z "${OMSA_PASS}" ] && [ -z "${OMSA_PASS_FILE}" ]; then
	echo 'Please specify OMSA_PASS or OMSA_PASS_FILE env vars.'
	HAS_ERROR=1
elif [ -n "${OMSA_PASS}" ] && [ -n "${OMSA_PASS_FILE}" ]; then
	echo 'Please specify OMSA_PASS or OMSA_PASS_FILE env vars, not both.'
	HAS_ERROR=1
elif [ -n "${OMSA_PASS_FILE}" ]; then
	if [ -r "${OMSA_PASS_FILE}" ]; then
		OMSA_PASS=$(head -n 1 "${OMSA_PASS_FILE}")
		if [ -z "${OMSA_PASS}" ]; then
			echo 'OMSA_PASS_FILE does not contain a valid password.'
			HAS_ERROR=1
		fi;
	else
		echo 'OMSA_PASS_FILE is not a valid file. ('"${OMSA_PASS_FILE}"')'
		HAS_ERROR=1
	fi
fi

if [ "${HAS_ERROR}" = "1" ]; then
	exit 1
fi;

# Set login credentials
if ! getent passwd "${OMSA_USER}" >/dev/null; then
	echo "Creating user ${OMSA_USER}..."
	if ! adduser "${OMSA_USER}"; then
		echo "Failed to create user account, exiting."
		exit 1
	fi;
fi

echo "Setting login password for ${OMSA_USER}..."
if ! echo "$OMSA_USER:$OMSA_PASS" | chpasswd; then
	echo "Failed to set account password, exiting."
	exit 1
fi;

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
