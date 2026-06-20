#!/bin/sh
# Set a recovery-friendly default password only when root has no password yet.

ROOT_PASSWORD_HASH='$6$JDCAX1800$Ek21stJaoHuQL1eMkRxLANJRCZrVlBnAAv3aZEvJ30Gm68jnTR8bBdoIR.sUGhf7hXsXULTwEf1/jG1ERcwnJ1'

if grep -q '^root::' /etc/shadow 2>/dev/null; then
  sed -i "s|^root:[^:]*:|root:${ROOT_PASSWORD_HASH}:|" /etc/shadow
fi

exit 0
