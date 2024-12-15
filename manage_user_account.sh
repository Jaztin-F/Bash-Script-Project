                                                                                                                                                                                                                                                                                                                                                                                                                                                   #!/bin/bash

# User Management Script

LOGFILE="var/log/user_management.log"

# Function to log actions
log_action() {
    local ACTION=$1
    echo "$(date): $ACTION" >> "$LOGFILE"
}

# Function to check password strength
check_password_strength() {
    local PASSWORD=$1
    if [[ ${#PASSWORD} -lt 8 || ! $PASSWORD =~ [A-Z] || ! $PASSWORD =~ [a-z] || ! $PASSWORD =~ [0-9] || ! $PASSWORD =~ [^a-zA-Z0-9] ]]; then
        echo "Weak password. Must be at least 8 characters long and include upper case, lower case, digit, and special character."
        return 1
    fi
    return 0
}

# Function to add user
add_user() {
    read -p "Enter username: " USERNAME

    # Prompt for a password and check its strength
    while true; do
        read -s -p "Enter password for $USERNAME: " PASSWORD
        echo
        check_password_strength "$PASSWORD"
        if [[ $? -eq 0 ]]; then
            break
        else
            echo "Please try again with a stronger password."
        fi
    done

    # Collect additional user details
    read -p "Full Name (press ENTER to skip): " FULLNAME
    read -p "Room Number (press ENTER to skip): " ROOM
    read -p "Work Phone (press ENTER to skip): " WORK_PHONE
    read -p "Home Phone (press ENTER to skip): " HOME_PHONE
    read -p "Other Info (press ENTER to skip): " OTHER

    # Create user with adduser command, passing the password and user details
    # Suppress verbose info while still using adduser
    echo -e "$PASSWORD\n$PASSWORD" | sudo adduser "$USERNAME" --gecos "$FULLNAME,$ROOM,$WORK_PHONE,$HOME_PHONE,$OTHER" > /dev/null 2>&1

    # Prompt for specific groups (optional)
    read -p "Enter specific groups for the user (comma-separated, or leave blank): " GRPS

    # Check if groups are provided and validate them
    if [[ -n "$GRPS" ]]; then
        # Validate if each group exists
        for group in $(echo "$GRPS" | tr ',' ' '); do
            if ! getent group "$group" > /dev/null; then
                echo "Error: Group '$group' does not exist."
                exit 1
            fi
        done

        # Assign user to groups
        # Suppress output of the usermod command while still executing it
        if sudo usermod -aG "$GRPS" "$USERNAME" > /dev/null 2>&1; then
            echo "Assigned user $USERNAME to groups: $GRPS"
            log_action "Assigned user $USERNAME to groups: $GRPS"
        else
            echo "Failed to assign user $USERNAME to groups: $GRPS"
            log_action "Failed to assign user $USERNAME to groups: $GRPS"
        fi
    else
        echo "No additional groups specified for user $USERNAME"
        log_action "No additional groups assigned for user $USERNAME"
    fi

    # Final message and logging
    echo "User $USERNAME added successfully."
    log_action "User $USERNAME added successfully."
}

# Function to delete a user
delete_user() {
    read -p "Enter username to delete: " USERNAME
    sudo userdel -r "$USERNAME"
    log_action "Deleted user $USERNAME"
    echo "User $USERNAME deleted successfully."
}

# Function to modify a user
modify_user() {
    read -p "Enter the current username to modify: " USERNAME

    # Check if the user exists
    if ! id "$USERNAME" &>/dev/null; then
        echo "Error: User '$USERNAME' does not exist."
        return
    fi

    echo "What would you like to modify?"
    echo "1. Change groups"
    echo "2. Change username"
    read -p "Choose an option (1 or 2): " MODIFY_OPTION

    case $MODIFY_OPTION in
        1)
            read -p "Enter new groups (comma-separated): " GRPS
            sudo usermod -G "$GRPS" "$USERNAME"
            log_action "Modified groups for $USERNAME to $GRPS"
            echo "User $USERNAME groups modified successfully."
            ;;
        2)
            read -p "Enter the new username: " NEW_USERNAME

            # Ensure the new username is not already taken
            if id -u "$NEW_USERNAME" &>/dev/null; then
                echo "Error: The username '$NEW_USERNAME' already exists."
                return
            fi

            # Change the username
            sudo usermod -l "$NEW_USERNAME" "$USERNAME"

            # Optionally rename the home directory
            read -p "Do you want to rename the home directory as well? (y/n): " RENAME_HOME
            if [[ "$RENAME_HOME" == "y" || "$RENAME_HOME" == "Y" ]]; then
                sudo usermod -d "/home/$NEW_USERNAME" -m "$NEW_USERNAME"
            fi

            log_action "Renamed user $USERNAME to $NEW_USERNAME"
            echo "User $USERNAME renamed to $NEW_USERNAME successfully."
            ;;
        *)
            echo "Invalid option. Please try again."
            ;;
    esac
}


# Function to assign directory permissions
assign_permissions() {
    read -p "Enter directory path: " DIR
    read -p "Enter username: " USERNAME
    read -p "Enter permissions (e.g., 755): " PERMISSIONS

    if sudo chown "$USERNAME" "$DIR" && sudo chmod "$PERMISSIONS" "$DIR"; then
        log_action "Successfully set permissions for $DIR to $PERMISSIONS for user $USERNAME."
        echo "Permissions for $DIR set successfully."
    else
        log_action "Failed to set permissions for $DIR with $PERMISSIONS for user $USERNAME."
        echo "Error: Failed to set permissions for $DIR."
    fi
}

# Function to generate user activity report
generate_report() {
    # Output file for the report
    echo "User Activity Report:" > report.txt
    echo "----------------------------------------------------------" >> report.txt
    echo "Username         Shell           Last Login Time" >> report.txt
    echo "----------------------------------------------------------" >> report.txt

    # Get a list of users with their shells and UIDs from /etc/passwd, excluding system users and nologin users
    awk -F: '{if ($3 >= 1000 && $7 != "/usr/sbin/nologin" && $7 != "/bin/false") print $1, $7}' /etc/passwd | while read -r user shell; do
        # Get the last login information using lastlog
        last_login=$(lastlog -u "$user")

        # Check if the lastlog entry shows "Never logged in"
        if echo "$last_login" | grep -q "Never logged in"; then
            last_time="**Never logged in**"
        else
            # Extract the last login time and avoid printing "Latest"
            last_time=$(echo "$last_login" | awk '{if ($4 != "Latest") print $4, $5, $6, $7, $8}')
        fi

        # Format and write the output to the report
        printf "%-15s %-15s %-40s\n" "$user" "$shell" "$last_time" >> report.txt
    done

    # Confirmation message
    echo "Report generated: report.txt"
}

# Function to set password expiration policy
set_password_policy() {
    read -p "Enter username: " USERNAME

    # Check if the user exists
    if ! id "$USERNAME" &>/dev/null; then
        echo "Error: User '$USERNAME' does not exist."
        return
    fi

    echo "Password Policy Options:"
    echo "1. Set expiration in days"
    echo "2. Expire password immediately"
    echo "3. Remove password expiration"
    read -p "Choose an option (1, 2, or 3): " OPTION

    case $OPTION in
        1)
            read -p "Enter days until password expiration: " DAYS
            sudo chage -M "$DAYS" "$USERNAME"
            log_action "Set password expiration for $USERNAME to $DAYS days"
            echo "Password expiration policy set for $USERNAME."
            ;;
        2)
            sudo chage -d 0 "$USERNAME"
            log_action "Set password for $USERNAME to expire immediately"
            echo "Password for $USERNAME has been set to expire immediately."
            ;;
        3)
            sudo chage -M -1 "$USERNAME"
            log_action "Removed password expiration for $USERNAME"
            echo "Password expiration has been removed for $USERNAME."
            ;;
        *)
            echo "Invalid option. Please try again."
            ;;
    esac
}

# Menu
while true; do
    echo "User Management Script"
    echo "1. Add User"
    echo "2. Delete User"
    echo "3. Modify User"
    echo "4. Assign Permissions"
    echo "5. Generate User Activity Report"
    echo "6. Set Password Expiration Policy"
    echo "7. Exit"
    read -p "Choose an option: " OPTION

    case $OPTION in
        1) add_user ;;
        2) delete_user ;;
        3) modify_user ;;
        4) assign_permissions ;;
        5) generate_report ;;
        6) set_password_policy ;;
        7) exit 0 ;;
        *) echo "Invalid option. Please try again." ;;
    esac
done


