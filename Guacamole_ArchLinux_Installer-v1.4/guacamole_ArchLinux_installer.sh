#!/bin/bash

###########################################
## Arch Linux Guacamole Installer Script ##
## Updated: 2025-05-19                   ##
###########################################

# Define variables
# It's generally better to let package managers handle versions for main components
# GUACAMOLE_VERSION="1.5.9" # As an example, check the AUR for the latest

# Database credentials (CHANGE THESE!)
DB_ROOT_USER="root"
DB_ROOT_PASSWORD="CHANGEME_DB_ROOT_PASSWORD" # Set this if your MariaDB root user has a password, or configure MariaDB securely first.
GUAC_DB_NAME="guacamole_db"
GUAC_DB_USER="guacamole_user"
GUAC_DB_PASSWORD="CHANGEME_GUAC_DB_PASSWORD" # Ensure this matches guacamole.properties

# SSL Certificate details (CHANGE THESE!)
SSL_COUNTRY="US"
SSL_STATE="California"
SSL_CITY="SanFrancisco"
SSL_ORG="MyOrg"
SSL_CERT_HOSTNAME="guacamole.example.com" # Use your actual domain

# Tomcat version (adjust if needed, check Arch repos)
TOMCAT_VERSION_DIR="tomcat10" # Or tomcat9, check /usr/share/

# --- PRE-FLIGHT CHECKS & INFO ---
echo "INFO: This script will install and configure Apache Guacamole."
echo "INFO: It assumes you have an AUR helper (like yay or paru) or will install AUR packages manually."
echo "WARNING: Default passwords are used. Change them for production!"
echo "Press Ctrl+C to cancel, or Enter to continue..."
read

# --- SYSTEM UPDATE ---
echo "INFO: Updating system packages..."
sudo pacman -Syu --noconfirm

# --- INSTALL REQUIRED PACKAGES FROM OFFICIAL REPOSITORIES ---
echo "INFO: Installing base dependencies..."
sudo pacman -S --noconfirm \
    cairo pango libpng libjpeg-turbo libwebp libvncserver \
    ghostscript \
    ffmpeg \
    pulseaudio-alsa \
    openssh mariadb nginx \
    jdk-openjdk # Current recommended LTS or stable Java for Tomcat/Guacamole
    # For Tomcat (Arch usually provides one main version, e.g., tomcat10 or tomcat9)
    # Check available tomcat version: pacman -Ss tomcat
    # tomcat10 # or tomcat9
    # tomcat-native # For Tomcat performance

# Attempt to install a common Tomcat version
if pacman -Ss tomcat10 > /dev/null; then
    echo "INFO: Installing Tomcat 10..."
    sudo pacman -S --noconfirm tomcat10 tomcat-native
    TOMCAT_VERSION_DIR="tomcat10"
    TOMCAT_SERVICE_NAME="tomcat10"
elif pacman -Ss tomcat9 > /dev/null; then
    echo "INFO: Installing Tomcat 9..."
    sudo pacman -S --noconfirm tomcat9 tomcat-native
    TOMCAT_VERSION_DIR="tomcat9"
    TOMCAT_SERVICE_NAME="tomcat9"
else
    echo "ERROR: Neither tomcat10 nor tomcat9 found in repositories. Please install Tomcat manually and adjust script."
    exit 1
fi


# --- INSTALL AUR PACKAGES (using an AUR helper or manually) ---
echo "INFO: The following AUR packages are required:"
echo "  - guacamole-server"
echo "  - guacamole-client (provides the .war)"
echo "  - freerdp (ensure it's a recent version with Guacamole-compatible flags, or look for specific freerdp-guacamole if needed)"
echo "  - libtelnet"
echo "  - libssh2"
echo "  - libwebsockets"
echo "  - libpulse" # If not pulled by other dependencies
echo "Please install them using your AUR helper (e.g., yay -S guacamole-server guacamole-client freerdp libtelnet libssh2 libwebsockets libpulse) or build them manually."
echo "Press Enter to acknowledge and continue (assuming you'll install them)..."
read

# Example for manual AUR installation (commented out, use an AUR helper ideally)
# mkdir -p ~/aur_builds
# cd ~/aur_builds

# echo "INFO: Building freerdp (example - ensure it's the correct version/variant)..."
# if ! pacman -Q freerdp > /dev/null; then
#   git clone https://aur.archlinux.org/freerdp.git
#   cd freerdp && makepkg -si --noconfirm && cd ..
# else
#   echo "INFO: freerdp already installed."
# fi

# echo "INFO: Building libtelnet from AUR..."
# if ! pacman -Q libtelnet > /dev/null; then
#   git clone https://aur.archlinux.org/libtelnet.git
#   cd libtelnet && makepkg -si --noconfirm && cd ..
# else
#   echo "INFO: libtelnet already installed."
# fi

# echo "INFO: Building guacamole-server from AUR..."
# if ! pacman -Q guacamole-server > /dev/null; then
#   git clone https://aur.archlinux.org/guacamole-server.git
#   cd guacamole-server && makepkg -si --noconfirm && cd ..
# else
#   echo "INFO: guacamole-server already installed."
# fi

# echo "INFO: Building guacamole-client from AUR..."
# # This will typically place the .war file into /usr/share/webapps/ or similar,
# # and provide a tomcat context file.
# if ! pacman -Q guacamole-client > /dev/null; then
#   git clone https://aur.archlinux.org/guacamole-client.git
#   cd guacamole-client && makepkg -si --noconfirm && cd ..
# else
#   echo "INFO: guacamole-client already installed."
# fi
# cd ~

# --- CONFIGURE MARIADB ---
echo "INFO: Configuring MariaDB..."
sudo mariadb-install-db --user=mysql --basedir=/usr --datadir=/var/lib/mysql
sudo systemctl enable mariadbd
sudo systemctl start mariadbd

# Secure MariaDB installation (interactive) - consider automating if needed
# echo "INFO: Consider running 'sudo mariadb-secure-installation' manually after this script."
# For a scripted approach to set root password (less secure than interactive):
# sudo mysql -u $DB_ROOT_USER -e "ALTER USER '$DB_ROOT_USER'@'localhost' IDENTIFIED BY '$DB_ROOT_PASSWORD'; FLUSH PRIVILEGES;"
# The above command assumes MariaDB 10.4+ and root user without a password initially.
# If $DB_ROOT_PASSWORD is set, use:
# sudo mysql -u $DB_ROOT_USER -p"$DB_ROOT_PASSWORD" -e "CREATE DATABASE IF NOT EXISTS ${GUAC_DB_NAME};"
# sudo mysql -u $DB_ROOT_USER -p"$DB_ROOT_PASSWORD" -e "CREATE USER IF NOT EXISTS '${GUAC_DB_USER}'@'localhost' IDENTIFIED BY '${GUAC_DB_PASSWORD}';"
# sudo mysql -u $DB_ROOT_USER -p"$DB_ROOT_PASSWORD" -e "GRANT SELECT,INSERT,UPDATE,DELETE ON ${GUAC_DB_NAME}.* TO '${GUAC_DB_USER}'@'localhost';"
# sudo mysql -u $DB_ROOT_USER -p"$DB_ROOT_PASSWORD" -e "FLUSH PRIVILEGES;"

echo "INFO: Creating Guacamole database and user..."
# Create a temporary SQL script
cat <<EOF_SQL > /tmp/guacamole_db_setup.sql
CREATE DATABASE IF NOT EXISTS ${GUAC_DB_NAME} CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '${GUAC_DB_USER}'@'localhost' IDENTIFIED BY '${GUAC_DB_PASSWORD}';
GRANT SELECT,INSERT,UPDATE,DELETE ON ${GUAC_DB_NAME}.* TO '${GUAC_DB_USER}'@'localhost';
FLUSH PRIVILEGES;
EOF_SQL

# Execute the SQL script
# You might need to enter the MariaDB root password if already set and not using passwordless sudo access for root
if [ -n "$DB_ROOT_PASSWORD" ]; then
    sudo mysql -u "$DB_ROOT_USER" -p"$DB_ROOT_PASSWORD" < /tmp/guacamole_db_setup.sql
else
    # Try without password, common for fresh installs where root has no password yet or uses socket auth
    sudo mysql -u "$DB_ROOT_USER" < /tmp/guacamole_db_setup.sql
fi
rm /tmp/guacamole_db_setup.sql

# --- CONFIGURE GUACAMOLE (guacd and guacamole.properties) ---
echo "INFO: Configuring Guacamole..."
sudo systemctl enable guacd
sudo systemctl start guacd

# Create Guacamole configuration directory if it doesn't exist
sudo mkdir -p /etc/guacamole

# Create GUACAMOLE_HOME for Tomcat if not handled by package
# This directory is for extensions and guacamole.properties
# The AUR package for guacamole-client might handle this, or Tomcat's context.
# Standard location for extensions: /etc/guacamole/extensions
# Standard location for lib: /etc/guacamole/lib
sudo mkdir -p /etc/guacamole/extensions
sudo mkdir -p /etc/guacamole/lib

# Install MariaDB JDBC Driver (check Arch repos for package first)
echo "INFO: Installing MariaDB JDBC driver..."
if ! pacman -Q mariadb-java-client > /dev/null; then
    sudo pacman -S --noconfirm mariadb-java-client # Or equivalent name like mariadb-connector-java
else
    echo "INFO: MariaDB JDBC driver already installed."
fi
# Ensure Tomcat can find it. The guacamole-client AUR package usually handles linking.
# If not, symlink or copy to /etc/guacamole/lib/ or Tomcat's lib.
# Example: sudo ln -s /usr/share/java/mariadb-java-client.jar /etc/guacamole/lib/

# Download/Locate Guacamole Auth JDBC extension (MySQL variant works with MariaDB)
# The guacamole-client AUR package might install this too. If not:
# GUAC_AUTH_JDBC_VERSION=$(pacman -Q guacamole-server | awk '{print $2}' | cut -d'-' -f1) # Get version from server
# sudo wget -O /etc/guacamole/extensions/guacamole-auth-jdbc-mysql-${GUAC_AUTH_JDBC_VERSION}.jar \
#   https://dlcdn.apache.org/guacamole/${GUAC_AUTH_JDBC_VERSION}/binary/guacamole-auth-jdbc-mysql-${GUAC_AUTH_JDBC_VERSION}.jar
# Verify the download path and version from Apache Guacamole's official site if downloading manually.

echo "INFO: Creating guacamole.properties..."
sudo tee /etc/guacamole/guacamole.properties > /dev/null <<EOF
# Guacamole server connection
guacd-hostname: localhost
guacd-port: 4822

# Authentication provider
auth-provider: org.apache.guacamole.auth.jdbc.JDBCAuthenticationProvider
lib-directory: /etc/guacamole/lib
extension-directory: /etc/guacamole/extensions

# MariaDB/MySQL properties
mysql-hostname: localhost
mysql-port: 3306
mysql-database: ${GUAC_DB_NAME}
mysql-username: ${GUAC_DB_USER}
mysql-password: ${GUAC_DB_PASSWORD}
mysql-ssl-mode: disabled # Or preferred, require, verify-ca, verify-full
mysql-server-timezone: UTC # Recommended
mysql-auto-create-schema: false # We create it manually
EOF

# Import Guacamole database schema
# The schema files are typically included with guacamole-auth-jdbc or guacamole-client AUR package
# Find the schema path, it might be /usr/share/guacamole/schema/ or similar
SCHEMA_PATH="/usr/share/doc/guacamole-client/schema" # Example path, verify this!
if [ -d "$SCHEMA_PATH/mysql" ]; then
    echo "INFO: Importing Guacamole database schema..."
    # Concatenate all SQL schema files and pipe to mysql client
    cat "$SCHEMA_PATH/mysql/"*.sql | sudo mysql -u "$GUAC_DB_USER" -p"$GUAC_DB_PASSWORD" "$GUAC_DB_NAME"
else
    echo "WARNING: Guacamole schema directory not found at $SCHEMA_PATH. Database schema might not be initialized."
    echo "You may need to locate the schema files (001-create-schema.sql, etc.) from the guacamole-auth-jdbc download"
    echo "or the guacamole-client package and import them manually into the ${GUAC_DB_NAME} database."
fi


# --- CONFIGURE TOMCAT ---
# The guacamole-client AUR package should deploy guacamole.war to Tomcat's webapps
# and might set up a context file. If not, manual steps would be:
# sudo cp /path/to/guacamole.war /usr/share/$TOMCAT_VERSION_DIR/webapps/
# If GUACAMOLE_HOME is not automatically picked up, you might need to set it for Tomcat.
# This can be done via /etc/tomcatX/conf/catalina.properties or a setenv.sh file.
# Add to /etc/$TOMCAT_VERSION_DIR/conf/catalina.properties:
# GUACAMOLE_HOME=/etc/guacamole
# Or create /usr/share/$TOMCAT_VERSION_DIR/bin/setenv.sh (make executable):
# export GUACAMOLE_HOME=/etc/guacamole

# Ensure Tomcat user can access /etc/guacamole and its contents
# sudo chown -R $TOMCAT_SERVICE_NAME:root /etc/guacamole # Tomcat user might be 'tomcat' or '$TOMCAT_SERVICE_NAME'
# sudo chmod -R g+r /etc/guacamole
# sudo chmod g+x /etc/guacamole /etc/guacamole/extensions /etc/guacamole/lib
# The exact Tomcat user can be found via `ps aux | grep tomcat` or package details.
# Commonly 'tomcat' or e.g. 'tomcat10'.
TOMCAT_USER_NAME="${TOMCAT_SERVICE_NAME}" # Default to service name
if id "tomcat" &>/dev/null; then # Check if a generic 'tomcat' user exists
    TOMCAT_USER_NAME="tomcat"
fi
echo "INFO: Setting permissions for Guacamole configuration for Tomcat user '$TOMCAT_USER_NAME'..."
sudo chown -R root:"${TOMCAT_USER_NAME}" /etc/guacamole
sudo chmod -R 750 /etc/guacamole # Read and execute for group
# Make properties file readable by Tomcat user
sudo chmod 640 /etc/guacamole/guacamole.properties

# Restart Tomcat
echo "INFO: Restarting Tomcat (${TOMCAT_SERVICE_NAME})..."
sudo systemctl enable ${TOMCAT_SERVICE_NAME}
sudo systemctl restart ${TOMCAT_SERVICE_NAME}

# --- CONFIGURE NGINX AS A REVERSE PROXY ---
echo "INFO: Configuring Nginx..."
sudo mkdir -p /etc/nginx/ssl
sudo openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
    -keyout /etc/nginx/ssl/nginx.key \
    -out /etc/nginx/ssl/nginx.crt \
    -subj "/C=${SSL_COUNTRY}/ST=${SSL_STATE}/L=${SSL_CITY}/O=${SSL_ORG}/CN=${SSL_CERT_HOSTNAME}"

# Nginx configuration for Guacamole
sudo tee /etc/nginx/conf.d/guacamole.conf > /dev/null <<EOF
server {
    listen 80;
    server_name ${SSL_CERT_HOSTNAME};

    # Redirect HTTP to HTTPS
    location / {
        return 301 https://\$host\$request_uri;
    }
}

server {
    listen 443 ssl http2;
    server_name ${SSL_CERT_HOSTNAME};

    ssl_certificate      /etc/nginx/ssl/nginx.crt;
    ssl_certificate_key  /etc/nginx/ssl/nginx.key;

    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers off;
    ssl_ciphers ECDH+AESGCM:ECDH+CHACHA20:ECDH+AES; # Modern ciphers
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 1d; # Adjust as needed
    # ssl_dhparam /etc/nginx/ssl/dhparam.pem; # Optional: Generate with openssl dhparam -out /etc/nginx/ssl/dhparam.pem 4096

    # Add HSTS header for security
    add_header Strict-Transport-Security "max-age=63072000; includeSubDomains; preload" always;

    # Security headers
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-XSS-Protection "1; mode=block" always;
    # add_header Content-Security-Policy "default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; font-src 'self' data:; connect-src 'self' wss://\${SSL_CERT_HOSTNAME}; form-action 'self'; frame-ancestors 'self';" always;


    access_log /var/log/nginx/guacamole-access.log;
    error_log /var/log/nginx/guacamole-error.log;

    location / { # Or /guacamole/ if you prefer, adjust proxy_pass and client paths
        proxy_pass http://localhost:8080/guacamole/; # Ensure this matches your Tomcat port and Guacamole context path
        proxy_buffering off;
        proxy_http_version 1.1;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection \$http_connection; # Changed to general "Connection"
        proxy_cookie_path /guacamole/ /; # Adjust if Guacamole is at root
        # Add a read timeout for the proxy
        proxy_read_timeout 3600s; # 1 hour, for long sessions. Guacamole handles its own timeouts for inactivity.
    }
}
EOF

# Test Nginx configuration and restart
sudo nginx -t
sudo systemctl enable nginx
sudo systemctl restart nginx

# --- FIREWALL CONFIGURATION (Placeholder) ---
echo "INFO: Firewall configuration needed."
echo "INFO: Ensure ports 80 (for HTTP redirect) and 443 (for HTTPS) are open for Nginx."
# Example using ufw:
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw enable

# --- FINAL STEPS & CLEANUP ---
echo "INFO: Guacamole installation and basic configuration complete."
echo "INFO: Access Guacamole at https://${SSL_CERT_HOSTNAME}/"
echo "INFO: Default login (if schema was applied and you haven't changed it): guacadmin / guacadmin"
echo "      You should change this default user/password immediately via the Guacamole UI."
echo "INFO: Remember to replace the self-signed SSL certificate with one from a trusted CA for production."
echo "INFO: Check logs if you encounter issues:"
echo "      Tomcat: journalctl -u ${TOMCAT_SERVICE_NAME}"
echo "      guacd: journalctl -u guacd"
echo "      Nginx: /var/log/nginx/guacamole-error.log and /var/log/nginx/guacamole-access.log"
echo "      MariaDB: Check MariaDB logs (e.g., /var/log/mariadb/mariadb.log or journalctl -u mariadbd)"

# Optional: remove temporary files
# rm -f /tmp/guacamole_db_setup.sql

exit 0
