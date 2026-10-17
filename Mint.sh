#!/usr/bin/env bash
set -u

AUTH_ADMINS=(bob jim otherbob otherjim)
AUTH_USERS=(emma henry eugine excalibur sting gandalf thorin)
DRY_RUN="${DRY_RUN:-true}"

contains() {
    local needle="$1"
    shift
    local item
    for item in "$@"; do
        if [[ "$item" == "$needle" ]]; then
            return 0
        fi
    done
    return 1
}

if [[ "$(id -u)" -ne 0 ]]; then
    echo "Error: please run with sudo, Gimli"
    exit 1
fi

if [[ -n "${SUDO_USER:-}" ]]; then
    AUTH_ADMINS+=("${SUDO_USER}")
fi

if getent group sudo >/dev/null 2>&1; then
    ADMIN_GROUP="sudo"
elif getent group adm >/dev/null 2>&1; then
    ADMIN_GROUP="adm"
elif getent group wheel >/dev/null 2>&1; then
    ADMIN_GROUP="wheel"
else
    ADMIN_GROUP="sudo"
fi

UID_MIN=$(awk '$1 == "UID_MIN" { print $2; exit }' /etc/login.defs 2>/dev/null || echo 1000)
UID_MAX=$(awk '$1 == "UID_MAX" { print $2; exit }' /etc/login.defs 2>/dev/null || echo 60000)

echo "I am securing users -Gimli, I am securing users better -legolas"

while IFS=: read -r user pass uid gid info home shell; do
    [[ -n "${user:-}" ]] || continue
    [[ -n "${uid:-}" ]] || continue
    [[ "$uid" =~ ^[0-9]+$ ]] || continue

    if (( uid >= UID_MIN && uid <= UID_MAX )); then
        is_admin=false
        is_user=false

        if contains "$user" "${AUTH_ADMINS[@]}"; then
            is_admin=true
        fi

        if contains "$user" "${AUTH_USERS[@]}"; then
            is_user=true
        fi

        if [[ "$is_admin" == true ]]; then
            echo "[ADMIN] Ensuring $user is in $ADMIN_GROUP..."
            if [[ "$DRY_RUN" != "true" ]]; then
                usermod -aG "$ADMIN_GROUP" "$user"
            else
                echo "[DRY RUN] usermod -aG $ADMIN_GROUP $user"
            fi

        elif [[ "$is_user" == true ]]; then
            echo "[USER] Removing admin rights from $user..."
            if [[ "$DRY_RUN" != "true" ]]; then
                gpasswd -d "$user" sudo >/dev/null 2>&1 || true
                gpasswd -d "$user" adm >/dev/null 2>&1 || true
            else
                echo "[DRY RUN] gpasswd -d $user sudo"
                echo "[DRY RUN] gpasswd -d $user adm"
            fi

        else
            echo "Found [Unauthorised], deleting user $user (keeping files)..."
            if [[ "$DRY_RUN" != "true" ]]; then
                userdel "$user"
            else
                echo "[DRY RUN] userdel $user"
            fi
        fi
    fi
done < <(getent passwd)

echo "I did way better than that beastly dwarf >Legolas, nope >Gimli"
echo "========== SECURING COMPLETE =========="
