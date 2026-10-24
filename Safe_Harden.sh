#!/bin/bash

AUTH_ADMINS="Legolas Gimli Gloin Boromir arwen aragorn"
AUTH_USERS="thorin sting gandalf radagast"

if [ "$(id -u)" -ne 0 ]; then
    echo "Error: please run with sudo."
    exit 1
fi

REAL_USER="${SUDO_USER:-$(logname 2>/dev/null || whoami)}"
AUTH_ADMINS="$AUTH_ADMINS $REAL_USER"

echo "Scanning user accounts..."
echo "Allowed admins: $AUTH_ADMINS"
echo "Allowed users:  $AUTH_USERS"
echo "----------------------------------------"

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

echo "----------------------------------------"
echo "User scan complete."
