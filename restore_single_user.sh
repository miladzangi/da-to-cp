#!/bin/bash

# فعال کردن حالت توقف در صورت بروز خطا
set -e

# فعال کردن حالت دیباگ
#set -x

# کدهای رنگ
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
BLUE="\033[0;34m"
RESET="\033[0m"

# sleep
sleep 3

# گرفتن نام فایل بکاپ به عنوان ورودی
BACKUP_FILE=$1

# بررسی اینکه ورودی داده شده است
if [ -z "$BACKUP_FILE" ]; then
    echo -e "${YELLOW}Enter the backup file name (must be in the same directory as the script):${RESET}"
    read BACKUP_FILE
fi

# بررسی اینکه ورودی داده شده و فایل بکاپ وجود دارد
if [[ -z "$BACKUP_FILE" || ! -f "$BACKUP_FILE" ]]; then
  echo -e "${RED}Error: Backup file '$BACKUP_FILE' not found or not specified!${RESET}"
  exit 1
fi

# فایل لاگ
LOG_FILE="${BACKUP_FILE}.log"  # فایل لاگ پیش‌فرض به نام BACKUP_FILE.log

# فعال کردن لاگ کردن تمام خروجی‌ها (stdout و stderr) به فایل
exec > >(tee -a "$LOG_FILE") 2>&1

# تابع برای چاپ پیغام‌ها با رنگ
log_message() {
    local message=$1
    local color=$2
    echo -e "${color}${message}${RESET}"
}

# استخراج نام فایل بکاپ بدون پسوند
case "$BACKUP_FILE" in
    *.tar.zst)
        BACKUP_NAME=$(basename "$BACKUP_FILE" .tar.zst)
        COMPRESS_OPTION="-I zstd"
        ;;
    *.tar.gz)
        BACKUP_NAME=$(basename "$BACKUP_FILE" .tar.gz)
        COMPRESS_OPTION="-z"
        ;;
    *)
        echo -e "${RED}Error: Unsupported backup file format. Only '.tar.zst' and '.tar.gz' are supported.${RESET}"
        exit 1
        ;;
esac

# مسیر فایل بکاپ
BACKUP_PATH=$(dirname "$BACKUP_FILE")

# نام دایرکتوری استخراج
EXTRACT_DIR="$BACKUP_PATH/$BACKUP_NAME"

# بررسی وجود دایرکتوری
if [[ -d "$EXTRACT_DIR" ]]; then
    echo -e "${YELLOW}Warning: Directory '$EXTRACT_DIR' already exists.${RESET}"
    echo -e "What do you want to do?"
    echo -e "1) Delete the directory and re-extract"
    echo -e "2) Skip extraction and continue"
    
    # خواندن انتخاب کاربر
    read -rp "Enter your choice (1/2): " CHOICE
    
    case "$CHOICE" in
        1)
            echo -e "Deleting directory: $EXTRACT_DIR"
            rm -rf "$EXTRACT_DIR" || { echo -e "${RED}Error: Failed to delete directory '$EXTRACT_DIR'${RESET}"; exit 1; }
            mkdir -p "$EXTRACT_DIR" || { echo -e "${RED}Error: Failed to recreate directory '$EXTRACT_DIR'${RESET}"; exit 1; }
            ;;
        2)
            echo -e "${GREEN}Skipping extraction and using existing directory: $EXTRACT_DIR${RESET}"
            SKIP_EXTRACTION=true
            ;;
        *)
            echo -e "${RED}Invalid choice. Exiting...${RESET}"
            exit 1
            ;;
    esac
else
    # اگر دایرکتوری وجود ندارد، آن را ایجاد می‌کنیم
    echo -e "Creating extract directory at: $EXTRACT_DIR"
    mkdir -p "$EXTRACT_DIR" || { echo -e "${RED}Error: Failed to create extract directory '$EXTRACT_DIR'${RESET}"; exit 1; }
fi

# بررسی فلگ اکسترکت
if [[ "$SKIP_EXTRACTION" != true ]]; then
    # استخراج فایل بکاپ به دایرکتوری جدید
    echo -e "Extracting backup file to: $EXTRACT_DIR"
    tar $COMPRESS_OPTION -xf "$BACKUP_FILE" -C "$EXTRACT_DIR" || {
        echo -e "${RED}Error: Failed to extract backup file '$BACKUP_FILE'. Cleaning up...${RESET}"
        rm -rf "$EXTRACT_DIR"
        exit 1
    }
    echo -e "${GREEN}Backup file extracted successfully!${RESET}"
else
    echo -e "${YELLOW}Extraction skipped. Continuing with existing directory.${RESET}"
fi

# مسیر پوشه backup در داخل فایل استخراج شده
BACKUP_FOLDER="$EXTRACT_DIR/backup"

# بررسی وجود پوشه backup
if [[ ! -d "$BACKUP_FOLDER" ]]; then
  echo -e "${RED}Error: 'backup' folder not found in '$EXTRACT_DIR'${RESET}"
  exit 1
fi

# شناسایی پوشه‌ای که دامنه اصلی با آن ساخته شده
DOMAIN_FOLDERS=()
for folder in "$BACKUP_FOLDER"/*; do
  if [[ -d "$folder" && "$folder" =~ \.[a-zA-Z]+$ ]]; then
    DOMAIN_FOLDERS+=("$(basename "$folder")")
  fi
done

# مسیر فایل user.conf در پوشه backup
USER_CONF="$EXTRACT_DIR/backup/user.conf"
echo -e "Looking for user.conf at: $USER_CONF"

# بررسی وجود فایل user.conf
if [[ ! -f "$USER_CONF" ]]; then
  echo -e "${RED}Error: user.conf not found in '$EXTRACT_DIR/backup'!${RESET}"
  exit 1
fi

# بررسی ورودی برای username
if [[ "$2" == username:* ]]; then
  USERNAME="${2#username:}"
  echo -e "Using provided username: $USERNAME"
  
  # دامنه و ایمیل را از فایل user.conf استخراج کنیم
  DOMAIN=$(grep -oP '^domain=\K.*' "$USER_CONF")
  EMAIL=$(grep -oP '^email=\K.*' "$USER_CONF")
  
  if [[ -z "$DOMAIN" || -z "$EMAIL" ]]; then
    echo -e "${RED}Error: Failed to extract domain or email from user.conf!${RESET}"
    exit 1
  fi

  echo -e "Extracted values from user.conf:"
  echo -e "Domain: $DOMAIN"
  echo -e "Email: $EMAIL"

else
  # در صورتی که نام کاربری داده نشده باشد، از user.conf استخراج کنیم
  DOMAIN=$(grep -oP '^domain=\K.*' "$USER_CONF")
  EMAIL=$(grep -oP '^email=\K.*' "$USER_CONF")
  USERNAME=$(grep -oP '^username=\K.*' "$USER_CONF")

  if [[ -z "$DOMAIN" || -z "$EMAIL" || -z "$USERNAME" ]]; then
    echo -e "${RED}Error: Failed to extract domain, email, or username from user.conf!${RESET}"
    exit 1
  fi

  echo -e "Extracted values from user.conf:"
  echo -e "Username: $USERNAME"
  echo -e "Domain: $DOMAIN"
  echo -e "Email: $EMAIL"
fi


# تولید پسورد رندوم با استفاده از openssl
cppassword=$(openssl rand -base64 12)

# ایجاد حساب کاربری با دستور whmapi1
echo -e "Creating WHM account..."
response=$(whmapi1 createacct username="$USERNAME" domain="$DOMAIN" password="$cppassword" contactemail="$EMAIL")

# بررسی نتیجه
if echo -e "$response" | grep -q "result: 0"; then
    # استخراج پیام خطا از خروجی
    error_reason=$(echo -e "$response" | grep -oP '(?<=reason: ).*')
    echo -e "${RED}Error: Failed to create account in WHM!${RESET}"
    echo -e "${RED}Reason: $error_reason${RESET}"
    exit 1
fi

echo -e "${GREEN}Account created successfully: Username: $USERNAME, Domain: $DOMAIN, Email: $EMAIL, Password: $cppassword${RESET}"


# کپی محتویات پوشه public_html دامنه اصلی به پوشه اصلی یوزر
MAIN_DOMAIN_PUBLIC_HTML="$EXTRACT_DIR/domains/$DOMAIN/public_html"
TARGET_PUBLIC_HTML="/home/$USERNAME/public_html"

if [[ -d "$MAIN_DOMAIN_PUBLIC_HTML" ]]; then
  echo -e "Copying contents of '$MAIN_DOMAIN_PUBLIC_HTML' to '$TARGET_PUBLIC_HTML'..."
  rsync -avh "$MAIN_DOMAIN_PUBLIC_HTML/" "$TARGET_PUBLIC_HTML/" || {
    echo -e "${RED}Error: Failed to copy contents from '$MAIN_DOMAIN_PUBLIC_HTML' to '$TARGET_PUBLIC_HTML'${RESET}";
    exit 1;
  }
  echo -e "${GREEN}Contents copied successfully!${RESET}"
else
  echo -e "${YELLOW}Warning: '$MAIN_DOMAIN_PUBLIC_HTML' does not exist, skipping copy.${RESET}"
fi

# تغییر مالکیت فایل‌ها
chown -R $USERNAME:$USERNAME /home/$USERNAME

# بررسی وجود فایل fixperms.sh
if [[ ! -f /root/fixperms.sh ]]; then
  echo -e "/root/fixperms.sh not found. Downloading and setting it up..."
  wget https://raw.githubusercontent.com/PeachFlame/cPanel-fixperms/master/fixperms.sh -O /root/fixperms.sh || {
    echo -e "${RED}Error: Failed to download fixperms.sh!${RESET}";
    exit 1;
  }
  chmod +x /root/fixperms.sh
  echo -e "fixperms.sh downloaded and ready to use."
fi

# اجرای fixperms.sh
sudo sh /root/fixperms.sh -a $USERNAME

# تغییر محدودیت اددان دامنه و پارک دامنه برای کاربر مشخص
echo -e "Modifying account limits for user: $USERNAME..."

# اجرای دستور whmapi1 برای تغییر محدودیت‌های اددان دامنه و پارک دامنه
output=$(whmapi1 modifyacct user="$USERNAME" MAXADDON=unlimited MAXPARK=unlimited --output=json)

# بررسی نتیجه عملیات
success=$(echo "$output" | jq -r '.metadata.result')
reason=$(echo "$output" | jq -r '.metadata.reason // empty')

if [[ "$success" == "1" ]]; then
  echo -e "${GREEN}Account limits for user '$USERNAME' modified successfully!${RESET}"
else
  echo -e "${RED}Error: Failed to modify account limits for user '$USERNAME'. Reason: $reason${RESET}"
  exit 1
fi

# اکنون باید به پوشه دامنه اصلی برویم و فایل domain.pointers را بخوانیم
MAIN_DOMAIN_DIR="$BACKUP_FOLDER/$DOMAIN"

# بررسی اینکه پوشه دامنه اصلی وجود دارد
if [[ ! -d "$MAIN_DOMAIN_DIR" ]]; then
  echo -e "${RED}Error: Domain folder '$MAIN_DOMAIN_DIR' not found!${RESET}"
  exit 1
fi

# مسیر فایل domain.pointers در پوشه دامنه اصلی
POINTERS_FILE="$MAIN_DOMAIN_DIR/domain.pointers"

# بررسی وجود فایل domain.pointers
if [[ ! -f "$POINTERS_FILE" ]]; then
  echo -e "${YELLOW}Warning: domain.pointers file not found in '$MAIN_DOMAIN_DIR', skipping parked domains...${RESET}"
else
  # خواندن فایل domain.pointers و اضافه کردن دامنه‌های پارک‌شده
  echo -e "Reading domain.pointers to add parked domains..."

  while IFS='=' read -r domain value; do
    # استخراج نام دامنه
    newdomain=$(echo -e "$domain" | tr -d '[:space:]')
    
    # اگر نوع آن alias باشد، آن را به عنوان پارک دامنه اضافه می‌کنیم
    if [[ "$value" == "type=alias" ]]; then
      echo -e "Adding parked domain: $newdomain"
      
      # اجرای دستور cpapi2 برای اضافه کردن دامنه
      output=$(cpapi2 --user="$USERNAME" Park park domain="$newdomain" --output=json)
      
      # استخراج مقادیر کلیدی از خروجی JSON
      result=$(echo "$output" | jq -r '.cpanelresult.data[0].result')
      reason=$(echo "$output" | jq -r '.cpanelresult.data[0].reason')
      error=$(echo "$output" | jq -r '.cpanelresult.error')
      
      if [[ "$result" -eq 1 ]]; then
        echo -e "${GREEN}Parked domain '$newdomain' added successfully!${RESET}"
      else
        # نمایش دلیل خطا (از reason یا error)
        if [[ -n "$reason" ]]; then
          echo -e "${RED}Error: Failed to add parked domain '$newdomain'. Reason: $reason${RESET}"
        elif [[ -n "$error" ]]; then
          echo -e "${RED}Error: Failed to add parked domain '$newdomain'. Reason: $error${RESET}"
        else
          echo -e "${RED}Error: Failed to add parked domain '$newdomain'. Unknown reason.${RESET}"
        fi
        exit 1
      fi
    fi
  done < "$POINTERS_FILE"
fi

# اضافه کردن اددان دامنه‌ها
echo -e "Adding addon domains..."


for newdomain in "${DOMAIN_FOLDERS[@]}"; do
  # اگر دامنه، دامنه اصلی نیست، آن را به عنوان اددان دامنه اضافه می‌کنیم
  if [[ "$newdomain" != "$DOMAIN" ]]; then
    echo -e "Adding addon domain: $newdomain"

    # اجرای دستور cpapi2 و ذخیره خروجی آن
    output=$(cpapi2 --user="$USERNAME" AddonDomain addaddondomain dir="/home/$USERNAME/public_html/$newdomain" newdomain="$newdomain" subdomain="$newdomain" --output=json)

    # بررسی نتیجه
    result=$(echo "$output" | jq -r '.cpanelresult.data[0].result')
    reason=$(echo "$output" | jq -r '.cpanelresult.data[0].reason // empty')

    if [[ "$result" == "1" ]]; then
      echo -e "${GREEN}Addon domain '$newdomain' added successfully!${RESET}"

      # پس از افزودن اددان دامنه، محتویات مربوطه را کپی می‌کنیم
      ADDON_PUBLIC_HTML="$EXTRACT_DIR/domains/$newdomain/public_html"
      TARGET_ADDON_PUBLIC_HTML="/home/$USERNAME/public_html/$newdomain"

      if [[ -d "$ADDON_PUBLIC_HTML" ]]; then
        echo -e "Copying contents of '$ADDON_PUBLIC_HTML' to '$TARGET_ADDON_PUBLIC_HTML'..."
        rsync -avh "$ADDON_PUBLIC_HTML/" "$TARGET_ADDON_PUBLIC_HTML/" || {
          echo -e "${RED}Error: Failed to copy contents from '$ADDON_PUBLIC_HTML' to '$TARGET_ADDON_PUBLIC_HTML'${RESET}"
          exit 1
        }
        echo -e "${GREEN}Contents copied successfully!${RESET}"
      else
        echo -e "${YELLOW}Warning: '$ADDON_PUBLIC_HTML' does not exist, skipping copy.${RESET}"
      fi
    else
      echo -e "${RED}Error: Failed to add addon domain '$newdomain'. Reason: $reason${RESET}"
      exit 1
    fi
  fi
done


# تغییر مالکیت فایل‌ها
chown -R $USERNAME:$USERNAME /home/$USERNAME
# اجرای fixperms.sh
sudo sh /root/fixperms.sh -a $USERNAME



# استخراج تعداد دامنه‌های Addon
ADDON_COUNT=$(cpapi2 --user=$USERNAME AddonDomain listaddondomains | grep -o ' domain:' | wc -l)

# نمایش تعداد دامنه‌های Addon
echo -e "Number of Addon Domains: $ADDON_COUNT"

# حالا باید ساب دامنه‌ها را اضافه کنیم
echo -e "Adding subdomains..."

# بررسی هر پوشه دامنه در /backup
for folder in "$BACKUP_FOLDER"/*; do
  if [[ -d "$folder" && "$folder" =~ \.[a-zA-Z]+$ ]]; then
    # مسیر فایل subdomain.list در پوشه دامنه
    SUBDOMAIN_FILE="$folder/subdomain.list"
    
    # اگر فایل subdomain.list موجود بود
    if [[ -f "$SUBDOMAIN_FILE" ]]; then
      # خواندن هر ساب دامنه و اضافه کردن آن به هاست
      while IFS= read -r subdomain; do
        subdomain=$(echo -e "$subdomain" | tr -d '[:space:]')  # حذف فضاهای اضافی
        if [[ -n "$subdomain" ]]; then
          if [[ "$folder" == "$MAIN_DOMAIN_DIR" ]]; then
            # اگر پوشه متعلق به دامنه اصلی است
            echo -e "Adding subdomain '$subdomain' to main domain '$DOMAIN'"
            cpapi2 --user="$USERNAME" SubDomain addsubdomain domain="$subdomain" rootdomain="$DOMAIN" dir="/home/$USERNAME/public_html/$subdomain" disallowdot=1 || {
              echo -e "${RED}Error: Failed to add subdomain '$subdomain'!${RESET}";
              exit 1;
            }
            echo -e "${GREEN}Subdomain '$subdomain' added successfully to main domain!${RESET}"

            # کپی کردن محتویات پس از اضافه کردن ساب دامنه به دامنه اصلی
            SUBDOMAIN_PUBLIC_HTML="$EXTRACT_DIR/domains/$subdomain.$DOMAIN/public_html"
            TARGET_SUBDOMAIN_PUBLIC_HTML="/home/$USERNAME/public_html/$subdomain"

            if [[ -d "$SUBDOMAIN_PUBLIC_HTML" ]]; then
              echo -e "Copying contents of '$SUBDOMAIN_PUBLIC_HTML' to '$TARGET_SUBDOMAIN_PUBLIC_HTML'..."
              rsync -avh "$SUBDOMAIN_PUBLIC_HTML/" "$TARGET_SUBDOMAIN_PUBLIC_HTML/" || {
                echo -e "${RED}Error: Failed to copy contents from '$SUBDOMAIN_PUBLIC_HTML' to '$TARGET_SUBDOMAIN_PUBLIC_HTML'${RESET}";
                exit 1;
              }
              echo -e "${GREEN}Contents copied successfully!${RESET}"
            else
              echo -e "${YELLOW}Warning: '$SUBDOMAIN_PUBLIC_HTML' does not exist, skipping copy.${RESET}"
            fi
          else
            # اگر پوشه متعلق به یک دامنه اددان است
            newdomain=$(basename "$folder")
            echo -e "Adding subdomain '$subdomain' to addon domain '$newdomain'"
            cpapi2 --user="$USERNAME" SubDomain addsubdomain domain="$subdomain" rootdomain="$newdomain" dir="/home/$USERNAME/public_html/$newdomain/$subdomain" disallowdot=1 || {
              echo -e "${RED}Error: Failed to add subdomain '$subdomain'!${RESET}";
              exit 1;
            }
            echo -e "${GREEN}Subdomain '$subdomain' added successfully to addon domain!${RESET}"

            # کپی کردن محتویات پس از اضافه کردن ساب دامنه به دامنه اددان
            ADDON_SUBDOMAIN_PUBLIC_HTML="$EXTRACT_DIR/domains/$subdomain.$newdomain/public_html"
            TARGET_ADDON_SUBDOMAIN_PUBLIC_HTML="/home/$USERNAME/public_html/$newdomain/$subdomain"

            if [[ -d "$ADDON_SUBDOMAIN_PUBLIC_HTML" ]]; then
              echo -e "Copying contents of '$ADDON_SUBDOMAIN_PUBLIC_HTML' to '$TARGET_ADDON_SUBDOMAIN_PUBLIC_HTML'..."
              rsync -avh "$ADDON_SUBDOMAIN_PUBLIC_HTML/" "$TARGET_ADDON_SUBDOMAIN_PUBLIC_HTML/" || {
                echo -e "${RED}Error: Failed to copy contents from '$ADDON_SUBDOMAIN_PUBLIC_HTML' to '$TARGET_ADDON_SUBDOMAIN_PUBLIC_HTML'${RESET}";
                exit 1;
              }
              echo -e "${GREEN}Contents copied successfully!${RESET}"
            else
              echo -e "${YELLOW}Warning: '$ADDON_SUBDOMAIN_PUBLIC_HTML' does not exist, skipping copy.${RESET}"
            fi
          fi
        fi
      done < "$SUBDOMAIN_FILE"
    fi
  fi
done

# تغییر مالکیت فایل‌ها
chown -R $USERNAME:$USERNAME /home/$USERNAME
# اجرای fixperms.sh
sudo sh /root/fixperms.sh -a $USERNAME

echo -e "${GREEN}All subdomains added successfully!${RESET}"



# تولید یک پسورد تصادفی و استفاده از آن برای همه دیتابیس‌ها
dbpass=$(openssl rand -base64 12 | tr -d "=+/")  # تولید یک پسورد تصادفی 12 کاراکتری
echo -e "Generated password for all databases: $dbpass"

# بررسی و شناسایی فایل‌های با پسوند .sql
for sql_file in "$BACKUP_FOLDER"/*.sql; do
  if [[ -f "$sql_file" ]]; then
    # استخراج بخش DB از نام فایل
    db_name=$(basename "$sql_file" .sql | awk -F'_' '{print $2}')  # بخش دوم بعد از _
    db="${USERNAME}_${db_name}"

    echo -e "Processing database: $db"

    # ساخت دیتابیس
    uapi --user="$USERNAME" Mysql create_database name="$db" || {
      echo -e "${RED}Error: Failed to create database '$db'!${RESET}";
      exit 1;
    }
    echo -e "${GREEN}Database '$db' created successfully!${RESET}"

    # ساخت کاربر دیتابیس با پسورد مشترک
    uapi --user="$USERNAME" Mysql create_user name="$db" password="$dbpass" || {
      echo -e "${RED}Error: Failed to create user for database '$db'!${RESET}";
      exit 1;
    }
    echo -e "${GREEN}User '$db' created successfully with password: $dbpass${RESET}"

    # دادن دسترسی کامل به کاربر روی دیتابیس
    uapi --user="$USERNAME" Mysql set_privileges_on_database user="$db" database="$db" privileges=ALL || {
      echo -e "${RED}Error: Failed to set privileges for user '$db' on database '$db'!${RESET}";
      exit 1;
    }
    echo -e "${GREEN}Privileges set successfully for user '$db' on database '$db'${RESET}"

    # ایمپورت فایل SQL به دیتابیس
    mysql --force "$db" < "$sql_file" || {
      echo -e "${RED}Error: Failed to import SQL file '$sql_file' into database '$db'!${RESET}";
      exit 1;
    }
    echo -e "${GREEN}SQL file '$sql_file' imported into database '$db' successfully!${RESET}"
  else
    echo -e "${YELLOW}No SQL file found in $BACKUP_FOLDER${RESET}"
  fi
done

echo -e "${GREEN}All SQL files processed successfully!${RESET}"




# جستجو برای فایل‌های wp-config.php در زیرشاخه‌ها
find "/home/$USERNAME" -type f -name "wp-config.php" | while read CONFIG_FILE; do
  echo -e "Found wp-config.php at: $CONFIG_FILE"

  # مرحله 1: پیدا کردن مقدار اصلی DB_NAME
  CURRENT_VALUE=$(grep "define( 'DB_NAME', " "$CONFIG_FILE" | sed -E "s/.*'([^']+)'.*/\1/")
  if [[ -z "$CURRENT_VALUE" ]]; then
    echo -e "${RED}Error: DB_NAME not found in $CONFIG_FILE${RESET}"
    continue
  fi
  echo -e "Current DB_NAME: $CURRENT_VALUE"

  # مرحله 2: تولید مقدار جدید با استفاده از نام کاربری
  NEW_VALUE=$(echo -e "$CURRENT_VALUE" | sed -E "s/^[^_]+/$USERNAME/")
  echo -e "New DB_NAME: $NEW_VALUE"

  # مرحله 3: جایگزینی مقدار جدید در فایل
  sed -i -E "s/(define\( 'DB_NAME', ')[^']+/\1${NEW_VALUE}/" "$CONFIG_FILE"

  # مرحله 3: جایگزینی مقدار جدید در DB_USER
  sed -i -E "s/(define\( 'DB_USER', ')[^']+/\1${NEW_VALUE}/" "$CONFIG_FILE"

  # مرحله 4: جایگزینی مقدار جدید در DB_PASSWORD
  sed -i -E "s/(define\( 'DB_PASSWORD', ')[^']+/\1${dbpass}/" "$CONFIG_FILE"

  # مرحله 5: بررسی تغییرات DB_NAME
  UPDATED_VALUE=$(grep "define( 'DB_NAME', " "$CONFIG_FILE" | sed -E "s/.*'([^']+)'.*/\1/")
  if [[ "$UPDATED_VALUE" == "$NEW_VALUE" ]]; then
    echo -e "${GREEN}DB_NAME successfully updated to: $UPDATED_VALUE in file: $CONFIG_FILE${RESET}"
  else
    echo -e "${RED}Error: Failed to update DB_NAME in $CONFIG_FILE${RESET}"
  fi

  # مرحله 6: بررسی تغییرات DB_USER
  UPDATED_DB_USER=$(grep "define( 'DB_USER', " "$CONFIG_FILE" | sed -E "s/.*'([^']+)'.*/\1/")
  if [[ "$UPDATED_DB_USER" == "$NEW_VALUE" ]]; then
    echo -e "${GREEN}DB_USER successfully updated to: $UPDATED_DB_USER in file: $CONFIG_FILE${RESET}"
  else
    echo -e "${RED}Error: Failed to update DB_USER in $CONFIG_FILE${RESET}"
  fi

  # مرحله 7: بررسی تغییرات DB_PASSWORD
  UPDATED_DB_PASS=$(grep "define( 'DB_PASSWORD', " "$CONFIG_FILE" | sed -E "s/.*'([^']+)'.*/\1/")
  if [[ "$UPDATED_DB_PASS" == "$dbpass" ]]; then
    echo -e "${GREEN}DB_PASSWORD successfully updated to: $UPDATED_DB_PASS in file: $CONFIG_FILE${RESET}"
  else
    echo -e "${RED}Error: Failed to update DB_PASSWORD in $CONFIG_FILE${RESET}"
  fi
done



# مسیر پوشه IMAP
IMAP_DIR="$EXTRACT_DIR/imap"

# تولید یک پسورد رندوم برای همه ایمیل‌ها
mailpassword=$(openssl rand -base64 12)  # پسورد رندوم با طول 12
echo -e "Generated password for all emails: $mailpassword"

# بررسی پوشه‌های داخل دایرکتوری IMAP
for domain_dir in "$IMAP_DIR"/*; do
  if [[ -d "$domain_dir" && ! -L "$domain_dir" ]]; then
    # استخراج نام دامنه از نام پوشه
    domain_name=$(basename "$domain_dir")

    echo -e "Processing domain: $domain_name"

    # بررسی پوشه‌های داخل دایرکتوری دامنه
    for folder in "$domain_dir"/*; do
      if [[ -d "$folder" && ! -L "$folder" ]]; then  # اسکیپ کردن پوشه‌های لینک شده
        # استخراج نام پوشه برای استفاده به عنوان ایمیل
        folder_name=$(basename "$folder")

        # ساخت ایمیل با استفاده از دستور addpop
        email="$folder_name@$domain_name"
        /scripts/addpop "$email" "$mailpassword" 20480

        if [[ $? -eq 0 ]]; then
          echo -e "${GREEN}Email $email created successfully with password: $mailpassword${RESET}"

          # مسیر ایمیل
          email_dir="/home/$USERNAME/mail/$domain_name/$folder_name"
          
          # پاک کردن تمام محتویات پوشه ایمیل، شامل فایل‌های پنهان
          if [[ -d "$email_dir" ]]; then
            echo -e "Cleaning up email directory: $email_dir"
          
            # حلقه برای حذف محتویات دایرکتوری
            for item in "$email_dir"/{*,.*}; do
              # جلوگیری از حذف . و .. 
              if [[ "$item" != "$email_dir/." && "$item" != "$email_dir/.." ]]; then
                rm -rf "$item"
                if [[ $? -eq 0 ]]; then
                  echo -e "Deleted: $item"
                else
                  echo -e "${RED}Error deleting: $item${RESET}"
                fi
              fi
            done
          
            echo -e "${GREEN}Contents of $email_dir cleaned successfully!${RESET}"
          fi

          # کپی کردن محتویات از Maildir به پوشه مقصد
          maildir_source="$folder/Maildir"
          maildir_destination="/home/$USERNAME/mail/$domain_name/$folder_name"

          if [[ -d "$maildir_source" ]]; then
            echo -e "Copying Maildir contents from $maildir_source to $maildir_destination"
            cp -a "$maildir_source"/. "$maildir_destination"  # کپی کردن همه محتویات (از جمله فایل‌های پنهان)
            if [[ $? -eq 0 ]]; then
              echo -e "${GREEN}Maildir contents copied successfully!${RESET}"
            else
              echo -e "${RED}Error copying Maildir contents.${RESET}"
            fi
          fi
        else
          echo -e "${RED}Error creating email $email${RESET}"
        fi
      fi
    done
  fi
done

echo -e "${GREEN}All emails processed, cleaned, and Maildir contents copied successfully!${RESET}"

# تغییر مالکیت فایل‌ها
chown -R $USERNAME:$USERNAME /home/$USERNAME
# اجرای fixperms.sh
sudo sh /root/fixperms.sh -a $USERNAME

# جستجو در مسیر /home/$USERNAME برای فایل‌های خاص
for file in $(find /home/$USERNAME -type f \( -name ".htaccess" -o -name "aios-bootstrap.php" -o -name "wp-config.php" -o -name ".user.ini" \)); do

    echo -e "Processing file: $file"
    
    # استخراج مسیر والد از فایل
    PARENT_DIR=$(dirname "$file")
    
    # تغییر مسیرها در فایل
    sed -i "s|/home.*/domains/.*/public_html/|$PARENT_DIR/|g" "$file"
    
    echo -e "Updated paths in $file"
done

echo -e "${GREEN}All files updated successfully!${RESET}"

# تغییر مالکیت فایل‌ها
chown -R $USERNAME:$USERNAME /home/$USERNAME
# اجرای fixperms.sh
sudo sh /root/fixperms.sh -a $USERNAME

# حذف فایل بکاپ و دایرکتوری استخراج
echo -e "Cleaning up backup file and extract directory..."

# حذف فایل بکاپ
#if [[ -f "$BACKUP_PATH/$BACKUP_FILE" ]]; then
#  echo -e "Removing backup file: $BACKUP_PATH/$BACKUP_FILE"
#  rm -f "$BACKUP_PATH/$BACKUP_FILE"
#  if [[ $? -eq 0 ]]; then
#    echo -e "${GREEN}Backup file removed successfully!${RESET}"
#  else
#    echo -e "${RED}Error removing backup file.${RESET}"
#  fi
#else
#  echo -e "${RED}Backup file not found: $BACKUP_PATH/$BACKUP_FILE${RESET}"
#fi

# حذف دایرکتوری استخراج
if [[ -d "$EXTRACT_DIR" ]]; then
  echo -e "Removing extract directory: $EXTRACT_DIR"
  rm -rf "$EXTRACT_DIR"
  if [[ $? -eq 0 ]]; then
    echo -e "${GREEN}Extract directory removed successfully!${RESET}"
  else
    echo -e "${RED}Error removing extract directory.${RESET}"
  fi
else
  echo -e "${RED}Extract directory not found: $EXTRACT_DIR${RESET}"
fi

echo -e "
╔═══════════════════════════════════════════════════════════════════════╗
║ ✅ Everything is done! 🎉
║ 🗂 Backup '${GREEN}${BACKUP_NAME}${RESET}' has been restored!
║ 🌐 CPanel domain: '${GREEN}$DOMAIN${RESET}'
║ 👤 CPanel user: '${GREEN}$USERNAME${RESET}'
║ 🔑 CPanel pass: '${GREEN}$cppassword${RESET}'
║ 💾 DB pass: '${GREEN}$dbpass${RESET}'
║ ✉ MAIL pass: '${GREEN}$mailpassword${RESET}'
║ 🌐 AddonDomain count: '${RED}$ADDON_COUNT${RESET}'
║ 📜 Log file: '${RED}$LOG_FILE${RESET}'
║ 📧 Email: ${BLUE}zangimds@gmail.com${RESET}
╚═══════════════════════════════════════════════════════════════════════╝
"
