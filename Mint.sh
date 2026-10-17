#!/bin/bash

# 1. DEFINE YOUR CONFIGURATION HERE BEFORE RUNNING
AUTH_ADMINS="root benjamin"
AUTH_USERS="user1 user2"

# 2. ENFORCE ROOT ACCESS
if [ "$(id -u)" -ne 0 ]; then
    echo "Error: Run with sudo."
    exit 1
fi

# Automatically add the current sudo operator to the admin list to prevent lockouts
REAL_USER=$SUDO_USER
AUTH_ADMINS="$AUTH_ADMINS $REAL_USER"

echo "=== SECURING USERS ==="

# 3. PARSE /ETC/PASSWD AND EXECUTE
while IFS=: read -r user pass uid gid info home shell; do
    # Only target standard human accounts (UID 1000 - 59999)
    if [ -n "$uid" ] && [ "$uid" -ge 1000 ] && [ "$uid" -lt 60000 ]; then
        
        # Check authorization status using clean text matching
        is_admin=false
        is_user=false
        case " $AUTH_ADMINS " in *" $user "*) is_admin=true ;; esac
        case " $AUTH_USERS " in *" $user "*) is_user=true ;; esac

        if [ "$is_admin" = true ]; then
            echo "[ADMIN] Ensuring $user is in sudo/adm..."
            usermod -aG sudo,adm "$user"
            
        elif [ "$is_user" = true ]; then
            echo "[USER] Stripping admin rights from $user..."
            gpasswd -d "$user" sudo >/dev/null 2>&1
            gpasswd -d "$user" adm >/dev/null 2>&1
            
        else
            echo "[UNAUTHORIZED] Deleting user $user (keeping files)..."
            userdel "$user"
        fi
    fi
done < /etc/passwd

echo "=== SECURING COMPLETE ==="
