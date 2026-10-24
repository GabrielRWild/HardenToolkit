#!/bin/bash

AUTH_ADMINS="pparker tstark ppotta hhogan nfury"
AUTH_USERS="bbanner cbarton swilson bbarnes sstrange wmaximoff slang slang cdanvers jrhodes hvandyne shuri okoye "

echo "########### STARTING UP ###############"

read -r -p "Would you like to continue [y/n] " answer

case "$answer" in
    [Yy]) ;;
    [Nn]) echo "Quitting."; exit 0 ;;
    *)    echo "Please answer y or n."; exit 1 ;;
esac

if [ "$(id -u)" -ne 0 ]; then
    echo "Error: please run with sudo."
    exit 1
fi

REAL_USER="${SUDO_USER:-$(logname 2>/dev/null || whoami)}"
AUTH_ADMINS="$AUTH_ADMINS $REAL_USER"

echo "Scanning user accounts..."
echo "Allowed admins: $AUTH_ADMINS"
echo "Allowed users:  $AUTH_USERS"
echo ""

while IFS=: read -r user pass uid gid info home shell; do
    [ -n "${user:-}" ] || continue
    [ -n "${uid:-}" ] || continue

    if [ "$uid" -ge 1000 ] && [ "$uid" -lt 60000 ]; then
        is_admin=false
        is_user=false

        case " $AUTH_ADMINS " in
            *" $user "*) is_admin=true ;;
        esac

        case " $AUTH_USERS " in
            *" $user "*) is_user=true ;;
        esac

        if [ "$is_admin" = true ]; then
            echo "[ADMIN] $user - explicitly allowed admin"
        elif [ "$is_user" = true ]; then
            echo "[USER] $user - normal allowed user"
        else
            echo "[UNAUTHORIZED] $user - not in allowlists"
        fi
    fi
done < /etc/passwd

echo "User scan complete."

echo "-------- starting user commands --------"
echo ""
sudo apt update
sudo apt upgrade -y


#add any commands you think should be run such as sudo apt update, the script will run them in order.


echo "########### SHUTTING DOWN ##############"
