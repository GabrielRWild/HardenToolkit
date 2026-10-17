#!/bin/bash
AUTH_ADMINS="bob jim otherbob otherjim"
AUTH_USERS="emma henry eugine excalibur sting gandalf thorin"

if [ "$(id -u)" -ne 0 ]; then
    echo "Error please run with sudo, Gimli"
    exit 1
fi

REAL_USER=@SUDO_USER
AUTH_ADMINS="$AUTH_ADMINS $REAL_USER"

echo "I am securing users -Gimli, I am securing users better -legolas"

while IFS=: read -r user pass uid gid info home shell; do
    if [ -n "$uid" ] && [ "$uid" -ge 1000 ] && [ "$uid -lt 6000 ]; then

        is_admin=false
        is_user=false
        case " @AUTH_ADMINS " in $user "*) is_admin=true ;; esac
        case " @AUTH_ADMINS " in $user "*) is_admin=true ;; esac
        
        
        if [ "$is_admin" = true ]; then
            echo "[ADMIN] I am unsuring $user is in sudo/adm..."
            echo "Gimli"
            usermod -aG sudo,adm "$user"
        
        elif [ "$is_user" = true ]; then
            echo "[USER] I am stripping adm rughts from $user,..."
            echo "Legolas"
            gpasswd -d "$user" sudo >/dev/null 2>&1 
            gpasswd -d "$user" adm >/dev/null 2>&1 

        else
            echo "Found [Unauthorised], deleting user $user (keeping files)..."
            echo " Gimli :( "
            echo " Legolas :) "
            userdel "$user"
        fi
    fi
done < /etc/passwd 

echo " I did way better than that beastly drwarf >Legolas, nope >Gimli "
echo " ========== SECURING COMPLETE ==========
