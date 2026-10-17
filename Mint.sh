#!/bin/bash

# ==============================================================================
# CyberPatriot User Management Script
# Purpose: Secures local user accounts based on authorized admin and standard lists.
# Usage: sudo ./manage_users.sh [--dry-run]
# ==============================================================================

# ------------------------------------------------------------------------------
# 1. INITIALIZATION, COLORS, AND LOGGING SETUP
# ------------------------------------------------------------------------------

# Color codes for terminal output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

LOG_FILE="/root/user_mgmt_log.txt"
DRY_RUN=false

# Check if --dry-run flag is passed
if [[ "$1" == "--dry-run" ]]; then
    DRY_RUN=true
    echo -e "${BLUE}[INFO] Running in DRY-RUN mode. No changes will be made.${NC}"
fi

# Ensure the script is run as root/sudo
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}[ERROR] This script must be run with sudo or as root.${NC}"
   exit 1
fi

# Identify the actual user running the sudo command to prevent self-lockout
REAL_USER=$SUDO_USER
if [[ -z "$REAL_USER" ]]; then
    REAL_USER=$(whoami)
fi

# Function to log actions with timestamps
log_action() {
    local message="$1"
    # Strips ANSI color codes for clean text logging
    local clean_message=$(echo -e "$message" | sed 'r s/\x1B\[[0-9;]*[mK]//g')
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $clean_message" >> "$LOG_FILE"
}

# ------------------------------------------------------------------------------
# 2. INTERACTIVE USER INPUT AND VALIDATION
# ------------------------------------------------------------------------------

while true; do
    echo -e "${BLUE}==================================================${NC}"
    echo -e "${BLUE}       CyberPatriot User Configuration            ${NC}"
    echo -e "${BLUE}==================================================${NC}"
    
    read -p "Enter AUTHORIZED ADMINISTRATORS (space-separated): " -a INPUT_ADMINS
    read -p "Enter AUTHORIZED STANDARD USERS (space-separated): " -a INPUT_USERS

    # Automatically enforce that the current user running the script is an admin
    if [[ ! " ${INPUT_ADMINS[@]} " =~ " ${REAL_USER} " ]]; then
        INPUT_ADMINS+=("$REAL_USER")
    fi

    echo -e "\n${YELLOW}Please review the configuration:${NC}"
    echo -e "Authorized Admins: ${GREEN}${INPUT_ADMINS[*]}${NC}"
    echo -e "Standard Users:    ${GREEN}${INPUT_USERS[*]}${NC}"
    
    read -p "Is this correct? (y/n): " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        break
    fi
    echo -e "${YELLOW}Let's try again...\n${NC}"
done

# Convert arrays into associative arrays for rapid lookup later
declare -A AUTH_ADMINS
declare -A AUTH_USERS

for u in "${INPUT_ADMINS[@]}"; do AUTH_ADMINS[$u]=1; done
for u in "${INPUT_USERS[@]}"; do AUTH_USERS[$u]=1; done

# Arrays to keep track of planned changes for the user summary
declare -a PLAN_DELETE
declare -a PLAN_CREATE_ADMIN
declare -a PLAN_CREATE_USER
declare -a PLAN_ADD_SUDO
declare -a PLAN_REM_SUDO

# ------------------------------------------------------------------------------
# 3. ANALYSIS & PLANNING PHASE (Parsing /etc/passwd)
# ------------------------------------------------------------------------------

echo -e "\n${BLUE}[INFO] Scanning system accounts...${NC}"

# Check for unauthorized UID 0 accounts (Backdoor check)
while IFS=: r user uid _; do
    if [[ "$uid" -eq 0 && "$user" != "root" ]]; then
        echo -e "${RED}[WARNING] User '$user' has UID 0 (root privileges)!${NC}"
        log_action "[WARNING] User '$user' has UID 0!"
    fi
done < /etc/passwd

# Read human accounts: UIDs between 1000 and 59999
declare -A EXISTING_HUMANS
while IFS=: r user _ uid _ _ _ _; do
    if [[ "$uid" -ge 1000 && "$uid" -lt 60000 ]]; then
        EXISTING_HUMANS[$user]=1
        
        # Scenario A: Existing user is not authorized anywhere -> Plan deletion
        if [[ -z "${AUTH_ADMINS[$user]}" && -z "${AUTH_USERS[$user]}" ]]; then
            PLAN_DELETE+=("$user")
        fi
        
        # Scenario B: Existing user is an authorized admin -> Check groups
        if [[ -n "${AUTH_ADMINS[$user]}" ]]; then
            if ! groups "$user" | grep -qE '\b(sudo|adm)\b'; then
                PLAN_ADD_SUDO+=("$user")
            fi
        fi
        
        # Scenario C: Existing user is a standard user -> Check if they shouldn't have sudo
        if [[ -n "${AUTH_USERS[$user]}" ]]; then
            if groups "$user" | grep -qE '\b(sudo|adm)\b'; then
                PLAN_REM_SUDO+=("$user")
            fi
        fi
    fi
done < /etc/passwd

# Scenario D: Authorized users missing from the system entirely
for u in "${!AUTH_ADMINS[@]}"; do
    if [[ -z "${EXISTING_HUMANS[$u]}" ]]; then
        PLAN_CREATE_ADMIN+=("$u")
    fi
done

for u in "${!AUTH_USERS[@]}"; do
    if [[ -z "${EXISTING_HUMANS[$u]}" ]]; then
        PLAN_CREATE_USER+=("$u")
    fi
done

# ------------------------------------------------------------------------------
# 4. SAFETY CONFIRMATION SUMMARY
# ------------------------------------------------------------------------------

echo -e "\n${YELLOW}==================================================${NC}"
echo -e "${YELLOW}               PLANNED CHANGES SUMMARY            ${NC}"
echo -e "${YELLOW}==================================================${NC}"
echo "The following modifications will be performed:"
echo -e "To Delete:             ${RED}${PLAN_DELETE[*]:-None}${NC}"
echo -e "To Demote (Rem Sudo):  ${YELLOW}${PLAN_REM_SUDO[*]:-None}${NC}"
echo -e "To Promote (Add Sudo):  ${GREEN}${PLAN_ADD_SUDO[*]:-None}${NC}"
echo -e "Missing Admins to Add: ${BLUE}${PLAN_CREATE_ADMIN[*]:-None}${NC}"
echo -e "Missing Users to Add:  ${BLUE}${PLAN_CREATE_USER[*]:-None}${NC}"
echo "=================================================="

read -p "Do you want to proceed with these changes? (y/n): " proceed
if [[ ! "$proceed" =~ ^[Yy]$ ]]; then
    echo -e "${YELLOW}Operation cancelled by user.${NC}"
    exit 0
fi

# ------------------------------------------------------------------------------
# 5. EXECUTION PHASE
# ------------------------------------------------------------------------------

# Track execution statistics for final output
COUNT_DEL=0; COUNT_ADD=0; COUNT_MOD=0

# Step 5a: Execute Deletions (Keeping home directories for forensics)
for user in "${PLAN_DELETE[@]}"; do
    echo -e "${RED}[DELETED] Removing unauthorized user: $user${NC}"
    log_action "[DELETED] Removing unauthorized user: $user"
    if [ "$DRY_RUN" = false ]; then
        userdel "$user"
    fi
    ((COUNT_DEL++))
done

# Step 5b: Promote Admins (Add to sudo and adm groups)
for user in "${PLAN_ADD_SUDO[@]}"; do
    echo -e "${GREEN}[ADDED TO SUDO] Granting admin groups to: $user${NC}"
    log_action "[ADDED TO SUDO] Granting admin groups to: $user"
    if [ "$DRY_RUN" = false ]; then
        usermod -aG sudo,adm "$user"
    fi
    ((COUNT_MOD++))
done

# Step 5c: Demote Standard Users (Remove from sudo and adm groups)
for user in "${PLAN_REM_SUDO[@]}"; do
    echo -e "${YELLOW}[REMOVED FROM SUDO] Stripping admin privileges from: $user${NC}"
    log_action "[REMOVED FROM SUDO] Stripping admin privileges from: $user"
    if [ "$DRY_RUN" = false ]; then
        gpasswd -d "$user" sudo 2>/dev/null
        gpasswd -d "$user" adm 2>/dev/null
    fi
    ((COUNT_MOD++))
done

# Step 5d: Handle Missing Admins
for user in "${PLAN_CREATE_ADMIN[@]}"; do
    read -p "Authorized admin '$user' doesn't exist. Create them? (y/n): " create_choice
    if [[ "$create_choice" =~ ^[Yy]$ ]]; then
        echo -e "${BLUE}[ADDED] Creating admin user: $user${NC}"
        log_action "[ADDED] Creating admin user: $user"
        if [ "$DRY_RUN" = false ]; then
            useradd -m -s /bin/bash "$user"
            usermod -aG sudo,adm "$user"
            echo "$user:CyberPatriot1!" | chpasswd  # Set a default temp password
        fi
        ((COUNT_ADD++))
    fi
done

# Step 5e: Handle Missing Standard Users
for user in "${PLAN_CREATE_USER[@]}"; do
    read -p "Authorized standard user '$user' doesn't exist. Create them? (y/n): " create_choice
    if [[ "$create_choice" =~ ^[Yy]$ ]]; then
        echo -e "${BLUE}[ADDED] Creating standard user: $user${NC}"
        log_action "[ADDED] Creating standard user: $user"
        if [ "$DRY_RUN" = false ]; then
            useradd -m -s /bin/bash "$user"
            echo "$user:CyberPatriot1!" | chpasswd
        fi
        ((COUNT_ADD++))
    fi
done

# ------------------------------------------------------------------------------
# 6. FINAL SUMMARY
# ------------------------------------------------------------------------------

echo -e "\n${GREEN}==================================================${NC}"
echo -e "${GREEN}               EXECUTION COMPLETE                 ${NC}"
echo -e "${GREEN}==================================================${NC}"
echo -e "Total Users Deleted:  $COUNT_DEL"
echo -e "Total Users Created:  $COUNT_ADD"
echo -e "Total Users Modified: $COUNT_MOD"
echo -e "Full details logged to: ${BLUE}$LOG_FILE${NC}"
echo "=================================================="

if [ "$DRY_RUN" = true ]; then
    echo -e "${BLUE}Reminder: Script was run with --dry-run. No assets were altered.${NC}"
fi
