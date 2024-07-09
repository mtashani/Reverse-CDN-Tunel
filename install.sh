# Set the owner and repo variables
OWNER="radkesvat"
REPO="WaterWall"

# Determine the architecture and set the ASSET_NAME accordingly
ARCH=$(uname -m)
if [ "$ARCH" == "aarch64" ]; then
  ASSET_NAME="Waterwall-linux-arm64.zip"
elif [ "$ARCH" == "x86_64" ]; then
  ASSET_NAME="Waterwall-linux-64.zip"
else
  echo "Unsupported architecture: $ARCH"
  exit 1
fi

# Function to download and unzip the release
download_and_unzip() {
  local url="$1"
  local dest="$2"
  

  echo "Downloading $dest from $url..."
  wget -q -O "$dest" "$url"
  if [ $? -ne 0 ]; then
    echo "Error: Unable to download file."
    return 1
  fi

  echo "Unzipping $dest..."
  unzip -o "$dest"
  if [ $? -ne 0 ]; then
    echo "Error: Unable to unzip file."
    return 1
  fi

  sleep 0.5
  chmod +x Waterwall
  rm "$dest"

  echo "Download and unzip completed successfully."
}

get_latest_release_url() {
  local api_url="https://api.github.com/repos/$OWNER/$REPO/releases/latest"

  echo "Fetching latest release data..." >&2
  local response=$(curl -s "$api_url")
  if [ $? -ne 0 ]; then
    echo "Error: Unable to fetch release data." >&2
    return 1
  fi

  local asset_url=$(echo "$response" | jq -r ".assets[] | select(.name == \"$ASSET_NAME\") | .browser_download_url")
  if [ -z "$asset_url" ]; then
    echo "Error: Asset not found." >&2
    return 1
  fi

  echo "$asset_url"
}

handle_download_and_unzip() {
  mkdir /root/CDNTunel
  cd /root/CDNTunel
  apt install unzip -y
  apt install jq -y
  local url=$(get_latest_release_url)
  if [ $? -ne 0 ]; then
    exit 1
  fi
  download_and_unzip "$url" "$ASSET_NAME"
  core_config
}


core_config() {

  local github_url="https://raw.githubusercontent.com/mtashani/Reverse-CDN-Tunel/main/core.json"
  local dest_file="core.json"

  echo "Downloading core.json from $github_url..."
  wget -q -O "$dest_file" "$github_url"
  if [ $? -ne 0 ]; then
    echo "Error: Unable to download core.json."
    return 1
  fi

  read -p "Enter number of workers (default 0): " workers
  read -p "Enter ram-profile (minimal/client/server, default server): " ram_profile


  workers=${workers:-0}
  ram_profile=${ram_profile:-server}


  case $ram_profile in
    minimal|client|server)
      ;;
    *)
      echo "Invalid ram-profile value. Setting default to server."
      ram_profile="server"
      ;;
  esac


  jq ".misc.workers = $workers | .misc.\"ram-profile\" = \"$ram_profile\"" "$dest_file" > temp.json && mv temp.json "$dest_file"

  echo "core.json updated successfully."
}

function main_menu {
    while true; do
        clear
        display_logo
        echo "Main Menu:"
        echo "1 - Iran"
        echo "2 - Kharej"
        echo "0 - Exit"
        read -p "Enter your choice: " main_choice
        case $main_choice in
            1)
                config_iran_server
                ;;
            2)
                config_kharej_server
                ;;
            0)
                exit 0
                ;;
            *)
                echo "Invalid choice, please try again."
                sleep 0.5
                ;;
        esac
    done
}

ERROR_LOG=""

log_error() {
    local msg="$1"
    ERROR_LOG="$ERROR_LOG$msg\n"
}

show_errors() {
    if [ -n "$ERROR_LOG" ]; then
        echo -e "\nErrors encountered:"
        echo -e "$ERROR_LOG"
    fi
}

function get_certificate() {
    # Prompt the user for their email
    read -p "Please enter your email: " user_email
    # Prompt the user for their domain
    read -p "Please enter your domain: " user_domain

    # Install certbot if it is not already installed
    if ! command -v certbot &> /dev/null
    then
        echo "Installing certbot..."
        sudo apt-get update
        sudo apt-get install -y certbot
    fi

    # Obtain the SSL certificate using certbot
    sudo certbot certonly --standalone --preferred-challenges http --agree-tos --email "$user_email" -d "$user_domain"

    # Define the certificate paths
    cert_path="/etc/letsencrypt/live/$user_domain"
    dest_path="/root/CDNTunel"

    # Copy the certificate files to the destination directory
    sudo cp "$cert_path/fullchain.pem" "$dest_path"
    sudo cp "$cert_path/privkey.pem" "$dest_path"

    echo "Certificates have been successfully copied to $dest_path."
}

# Call the function


function config_iran_server {
    display_logo
    
    handle_download_and_unzip
    local github_url="https://raw.githubusercontent.com/mtashani/Reverse-CDN-Tunel/main/iran_config.json"
    local dest_file="config.json"

    echo "Downloading config.json from $github_url..."
    wget -q -O "$dest_file" "$github_url"
    if [ $? -ne 0 ]; then
        log_error "Error: Unable to download config.json."
        show_errors
        read -p "Press enter to retry..."
        config_iran_server
        return
    fi
    get_certificate

    read -p "Please enter your port: " port

    echo "Updating config.json with Port: $port"

    jq --arg port "$port" \
       '.nodes |= map(if .name == "inbound_users" then .settings.port = ($port | tonumber) else . end)' \
       "$dest_file" > temp.json && mv temp.json "$dest_file"

    if [ $? -ne 0 ]; then
        log_error "Error: Unable to update config.json."
        show_errors
        read -p "Press enter to retry..."
        config_iran_server
        return
    fi



    echo "config.json updated successfully."

    setup_waterwall_service
    systemctl status waterwall
    read -p "Press enter to continue..."
    main_menu
}

function config_kharej_server {
    display_logo
    handle_download_and_unzip
    local github_url="https://raw.githubusercontent.com/mtashani/Reverse-CDN-Tunel/main/khrej_config.json"
    local dest_file="config.json"

    echo "Downloading config.json from $github_url..."
    wget -q -O "$dest_file" "$github_url"
    if [ $? -ne 0 ]; then
        log_error "Error: Unable to download config.json."
        show_errors
        read -p "Press enter to retry..."
        config_kharej_server
        return
    fi

    read -p "Please enter your domain: " domain

    read -p "Please enter your port: " port

    echo "Updating config.json with domain: $domain, Port: $port"

    jq --arg domain "$domain" \
       --arg port "$port" \
       '.nodes |= map(if .name == "h2client" then .settings.host = $domain else . end) |
        .nodes |= map(if .name == "sslclient" then .settings.sni = $domain else . end) |
        .nodes |= map(if .name == "iran_outbound" then .settings.address = $domain else . end) |
        .nodes |= map(if .name == "core_outbound" then .settings.port = ($port | tonumber) else . end)' \
       "$dest_file" > temp.json && mv temp.json "$dest_file"

    if [ $? -ne 0 ]; then
        log_error "Error: Unable to update config.json."
        show_errors
        read -p "Press enter to retry..."
        config_kharej_server
        return
    fi


    echo "config.json updated successfully."

    setup_waterwall_service
    systemctl status waterwall
    read -p "Press enter to continue..."
    main_menu
}


setup_waterwall_service() {
    cat > /etc/systemd/system/waterwall.service << EOF
[Unit]
Description=Waterwall Service
After=network.target

[Service]
ExecStart=/root/CDNTunel/Waterwall
WorkingDirectory=/root/CDNTunel
Restart=always
RestartSec=5
User=root
StandardOutput=null
StandardError=null

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable waterwall
    systemctl start waterwall
}

# Function to display the logo
function display_logo {
    echo " _  _   __  ____  ____  ____  _  _   __   __    __    _   "
    echo "/ )( \ / _\(_  _)(  __)(  _ \/ )( \ / _\ (  )  (  )  / \  "
    echo "\ /\ //    \ )(   ) _)  )   /\ /\ //    \/ (_/\/ (_/\\_/  "
    echo "(_/\_)\_/\_/(__) (____)(__\_)(_/\_)\_/\_/\____/\____/(_)  "
}

# Start the script
main_menu