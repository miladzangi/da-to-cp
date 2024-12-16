#!/bin/bash

# URL فایل اسکریپت
SCRIPT_URL="https://raw.githubusercontent.com/miladzangi/da-to-cp/main/restore_single_user.sh"

# نام فایل اسکریپت که دانلود می‌شود
SCRIPT_FILE="restore_single_user.sh"

# دانلود فایل
echo "Downloading the script from GitHub..."
curl -s -o $SCRIPT_FILE $SCRIPT_URL

# تغییر دسترسی به فایل (اجرا کردن آن)
echo "Making the script executable..."
chmod +x $SCRIPT_FILE

# اجرای اسکریپت
echo "Executing the script..."
./$SCRIPT_FILE
