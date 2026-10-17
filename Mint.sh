#!/bin/bash
AUTH_ADMINS="Legolas Gimli Gloin Boromir arwen aragorn"
AUTH_USERS="thorin sting gandalf thorin radagast"

if [ "$(id -u)" -ne 0 ]; then
    echo "Error: please run with sudo, Gimli"
    exit 1
fi

REAL_USER="${SUDO_USER:-$(logname 2>/dev/null || whoami)}"
AUTH_ADMINS="$AUTH_ADMINS $REAL_USER"

echo "I am securing users -Gimli, I am securing users better -legolas"

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
            echo "[ADMIN] Ensuring $user is in sudo/adm..."
            usermod -aG sudo,adm "$user"

        elif [ "$is_user" = true ]; then
            echo "[USER] Stripping adm rights from $user..."
            gpasswd -d "$user" sudo >/dev/null 2>&1 || true
            gpasswd -d "$user" adm >/dev/null 2>&1 || true

        else
            echo "Found [Unauthorised], deleting user $user (keeping files)..."
            userdel "$user" || true
        fi
    fi
done < /etc/passwd

echo "I did way better than that beastly dwarf >Legolas, nope >Gimli"
echo "========== SECURING COMPLETE =========="
