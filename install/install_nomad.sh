#!/usr/bin/env bash

# Project N.O.M.A.D. Installation Script (macOS / Apple Silicon)

###################################################################################################################################################################################################

# Script                | Project N.O.M.A.D. Installation Script (macOS)
# Version               | 2.1.0
# Original Author       | Crosstalk Solutions, LLC
# macOS Adaptation       | proximasan
# Website               | https://crosstalksolutions.com

###################################################################################################################################################################################################
#                                                                                                                                                                                                 #
#                                                                                           Color Codes                                                                                           #
#                                                                                                                                                                                                 #
###################################################################################################################################################################################################

RESET='\033[0m'
YELLOW='\033[1;33m'
WHITE_R='\033[39m' # Same as GRAY_R for terminals with white background.
GRAY_R='\033[39m'
RED='\033[1;31m' # Light Red.
GREEN='\033[1;32m' # Light Green.

###################################################################################################################################################################################################
#                                                                                                                                                                                                 #
#                                                                                  Constants & Variables                                                                                          #
#                                                                                                                                                                                                 #
###################################################################################################################################################################################################

WHIPTAIL_TITLE="Project N.O.M.A.D Installation"
NOMAD_DIR="${HOME}/project-nomad"
MANAGEMENT_COMPOSE_FILE_URL="https://raw.githubusercontent.com/proximasan/project-nomad/refs/heads/main/install/management_compose.yaml"
SIDECAR_UPDATER_DOCKERFILE_URL="https://raw.githubusercontent.com/proximasan/project-nomad/refs/heads/main/install/sidecar-updater/Dockerfile"
SIDECAR_UPDATER_SCRIPT_URL="https://raw.githubusercontent.com/proximasan/project-nomad/refs/heads/main/install/sidecar-updater/update-watcher.sh"
START_SCRIPT_URL="https://raw.githubusercontent.com/proximasan/project-nomad/refs/heads/main/install/start_nomad.sh"
STOP_SCRIPT_URL="https://raw.githubusercontent.com/proximasan/project-nomad/refs/heads/main/install/stop_nomad.sh"
UPDATE_SCRIPT_URL="https://raw.githubusercontent.com/proximasan/project-nomad/refs/heads/main/install/update_nomad.sh"
script_option_debug='true'
accepted_terms='false'
local_ip_address=''
use_native_ollama='false'
apple_chip_model=''

###################################################################################################################################################################################################
#                                                                                                                                                                                                 #
#                                                                                           Functions                                                                                             #
#                                                                                                                                                                                                 #
###################################################################################################################################################################################################

header() {
  if [[ "${script_option_debug}" != 'true' ]]; then clear; clear; fi
  echo -e "${GREEN}#########################################################################${RESET}\\n"
}

header_red() {
  if [[ "${script_option_debug}" != 'true' ]]; then clear; clear; fi
  echo -e "${RED}#########################################################################${RESET}\\n"
}

check_is_bash() {
  if [[ -z "$BASH_VERSION" ]]; then
    header_red
    echo -e "${RED}#${RESET} This script requires bash to run. Please run the script using bash.\\n"
    echo -e "${RED}#${RESET} For example: bash $(basename "$0")"
    exit 1
  fi
    echo -e "${GREEN}#${RESET} This script is running in bash.\\n"
}

check_is_macos() {
  if [[ "$(uname)" != "Darwin" ]]; then
    header_red
    echo -e "${RED}#${RESET} This script is designed to run on macOS only.\\n"
    echo -e "${RED}#${RESET} Please run this script on a Mac and try again."
    exit 1
  fi
  echo -e "${GREEN}#${RESET} This script is running on macOS.\\n"
}

detect_apple_chip_model() {
  # Detect the Apple chip model for injection into the compose file.
  # Inside Docker on macOS, systeminformation returns empty/generic CPU data,
  # so we capture it here from the host and pass it as an environment variable.
  apple_chip_model=$(sysctl -n machdep.cpu.brand_string 2>/dev/null || echo "")
  if [[ -n "$apple_chip_model" ]]; then
    echo -e "${GREEN}#${RESET} Detected chip: ${WHITE_R}${apple_chip_model}${RESET}\\n"
  else
    echo -e "${YELLOW}#${RESET} Could not detect Apple chip model. CPU info in the admin UI may be limited.\\n"
  fi
}

ensure_dependencies_installed() {
  # Check for Homebrew first
  if ! command -v brew &> /dev/null; then
    echo -e "${RED}#${RESET} Homebrew is not installed. Homebrew is required to install dependencies on macOS.\\n"
    echo -e "${YELLOW}#${RESET} Install Homebrew by running:\\n"
    echo -e "${WHITE_R}  /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\"${RESET}\\n"
    exit 1
  fi
  echo -e "${GREEN}#${RESET} Homebrew is installed.\\n"

  local missing_deps=()

  # Check for curl (should be present on macOS, but just in case)
  if ! command -v curl &> /dev/null; then
    missing_deps+=("curl")
  fi

  if [[ ${#missing_deps[@]} -gt 0 ]]; then
    echo -e "${YELLOW}#${RESET} Installing required dependencies: ${missing_deps[*]}...\\n"
    brew install "${missing_deps[@]}"

    # Verify installation
    for dep in "${missing_deps[@]}"; do
      if ! command -v "$dep" &> /dev/null; then
        echo -e "${RED}#${RESET} Failed to install $dep. Please install it manually and try again."
        exit 1
      fi
    done
    echo -e "${GREEN}#${RESET} Dependencies installed successfully.\\n"
  else
    echo -e "${GREEN}#${RESET} All required dependencies are already installed.\\n"
  fi
}

check_is_debug_mode(){
  # Check if the script is being run in debug mode
  if [[ "${script_option_debug}" == 'true' ]]; then
    echo -e "${YELLOW}#${RESET} Debug mode is enabled, the script will not clear the screen...\\n"
  else
    clear; clear
  fi
}

generateRandomPass() {
  local length="${1:-32}"  # Default to 32
  local password

  # Generate random password using /dev/urandom (works on macOS)
  password=$(tr -dc 'A-Za-z0-9' < /dev/urandom | head -c "$length")

  echo "$password"
}

ensure_docker_installed() {
  if ! command -v docker &> /dev/null; then
    echo -e "${YELLOW}#${RESET} Docker not found.\\n"

    # Check if Docker Desktop app exists but CLI isn't in PATH
    if [[ -d "/Applications/Docker.app" ]]; then
      echo -e "${YELLOW}#${RESET} Docker Desktop is installed but the CLI may not be in your PATH.\\n"
      echo -e "${YELLOW}#${RESET} Attempting to start Docker Desktop...\\n"
      open -a Docker
      echo -e "${YELLOW}#${RESET} Waiting for Docker to start (this may take up to 60 seconds)...\\n"

      local retries=30
      while [[ $retries -gt 0 ]]; do
        if command -v docker &> /dev/null && docker info &> /dev/null; then
          break
        fi
        sleep 2
        retries=$((retries - 1))
      done

      if ! command -v docker &> /dev/null || ! docker info &> /dev/null; then
        echo -e "${RED}#${RESET} Docker Desktop started but the CLI is not available.\\n"
        echo -e "${YELLOW}#${RESET} Please ensure Docker Desktop is fully started and the CLI tools are installed.\\n"
        echo -e "${YELLOW}#${RESET} In Docker Desktop: Settings -> General -> enable 'Install Docker CLI in system PATH'.\\n"
        exit 1
      fi
    else
      echo -e "${RED}#${RESET} Docker Desktop is not installed.\\n"
      echo -e "${YELLOW}#${RESET} Please install Docker Desktop for Mac from: https://www.docker.com/products/docker-desktop/\\n"
      echo -e "${YELLOW}#${RESET} After installing, launch Docker Desktop and run this script again.\\n"
      exit 1
    fi

    echo -e "${GREEN}#${RESET} Docker is now available.\\n"
  else
    echo -e "${GREEN}#${RESET} Docker is already installed.\\n"

    # Check if Docker daemon is running
    if ! docker info &> /dev/null; then
      echo -e "${YELLOW}#${RESET} Docker is installed but not running. Attempting to start Docker Desktop...\\n"
      open -a Docker

      local retries=30
      while [[ $retries -gt 0 ]]; do
        if docker info &> /dev/null; then
          break
        fi
        sleep 2
        retries=$((retries - 1))
      done

      if ! docker info &> /dev/null; then
        echo -e "${RED}#${RESET} Failed to start Docker Desktop. Please start it manually and try again."
        exit 1
      else
        echo -e "${GREEN}#${RESET} Docker Desktop started successfully.\\n"
      fi
    else
      echo -e "${GREEN}#${RESET} Docker is running.\\n"
    fi
  fi
}

check_docker_compose() {
  # Check if 'docker compose' (v2 plugin) is available
  if ! docker compose version &>/dev/null; then
    echo -e "${RED}#${RESET} Docker Compose v2 is not installed or not available as a Docker plugin."
    echo -e "${YELLOW}#${RESET} This script requires 'docker compose' (v2), not 'docker-compose' (v1)."
    echo -e "${YELLOW}#${RESET} Docker Desktop for Mac should include Docker Compose v2 by default."
    echo -e "${YELLOW}#${RESET} Please ensure Docker Desktop is up to date."
    exit 1
  fi
}

prompt_ollama_mode() {
  # Ask the user whether to install Ollama natively (recommended for GPU acceleration)
  # or use the Docker-based Ollama (no Metal GPU access).
  echo ""
  echo -e "${YELLOW}#########################################################################${RESET}"
  echo -e "${YELLOW}#${RESET} Ollama Installation Mode"
  echo -e "${YELLOW}#########################################################################${RESET}"
  echo ""
  echo -e "${WHITE_R}  Docker on macOS cannot pass through Metal GPU acceleration to containers.${RESET}"
  echo -e "${WHITE_R}  Installing Ollama natively allows AI models to use your Apple Silicon GPU${RESET}"
  echo -e "${WHITE_R}  for significantly faster inference.${RESET}"
  echo ""
  echo -e "${GREEN}  Option 1 (Recommended):${RESET} Native Ollama via Homebrew"
  echo -e "${WHITE_R}    - Full Metal GPU acceleration on Apple Silicon${RESET}"
  echo -e "${WHITE_R}    - Runs as a background service on your Mac${RESET}"
  echo -e "${WHITE_R}    - Best performance for AI workloads${RESET}"
  echo ""
  echo -e "${YELLOW}  Option 2:${RESET} Docker-based Ollama"
  echo -e "${WHITE_R}    - Runs inside a Docker container (no GPU acceleration)${RESET}"
  echo -e "${WHITE_R}    - CPU-only inference (significantly slower)${RESET}"
  echo -e "${WHITE_R}    - Fully containerized${RESET}"
  echo ""
  read -p "Install Ollama natively for GPU acceleration? (Y/n): " ollama_choice
  case "$ollama_choice" in
    n|N )
      use_native_ollama='false'
      echo -e "${YELLOW}#${RESET} Docker-based Ollama selected. AI models will run in CPU-only mode.\\n"
      ;;
    * )
      use_native_ollama='true'
      echo -e "${GREEN}#${RESET} Native Ollama selected. AI models will have Metal GPU acceleration.\\n"
      ;;
  esac
}

install_native_ollama() {
  if [[ "${use_native_ollama}" != 'true' ]]; then
    return 0
  fi

  echo -e "${YELLOW}#${RESET} Setting up native Ollama...\\n"

  if command -v ollama &> /dev/null; then
    echo -e "${GREEN}#${RESET} Ollama is already installed.\\n"
  else
    echo -e "${YELLOW}#${RESET} Installing Ollama via Homebrew...\\n"
    if ! brew install ollama; then
      echo -e "${RED}#${RESET} Failed to install Ollama via Homebrew.\\n"
      echo -e "${YELLOW}#${RESET} You can install it manually later from: https://ollama.com/download\\n"
      echo -e "${YELLOW}#${RESET} Falling back to Docker-based Ollama.\\n"
      use_native_ollama='false'
      return 0
    fi
    echo -e "${GREEN}#${RESET} Ollama installed successfully.\\n"
  fi

  # Start Ollama as a background service using brew services
  echo -e "${YELLOW}#${RESET} Starting Ollama service...\\n"
  brew services start ollama 2>/dev/null || true

  # Wait briefly for Ollama to start
  local retries=10
  while [[ $retries -gt 0 ]]; do
    if curl -s http://localhost:11434/api/version &> /dev/null; then
      break
    fi
    sleep 1
    retries=$((retries - 1))
  done

  if curl -s http://localhost:11434/api/version &> /dev/null; then
    echo -e "${GREEN}#${RESET} Ollama is running and accessible at http://localhost:11434\\n"
  else
    echo -e "${YELLOW}#${RESET} Ollama installed but not yet responding. It may need a moment to start.\\n"
    echo -e "${YELLOW}#${RESET} You can start it manually with: ${WHITE_R}brew services start ollama${RESET}\\n"
  fi
}

get_install_confirmation(){
  echo -e "${YELLOW}#${RESET} This script will install Project N.O.M.A.D. and its dependencies on your Mac."
  echo -e "${YELLOW}#${RESET} If you already have Project N.O.M.A.D. installed with customized config or data, please be aware that running this installation script may overwrite existing files and configurations. It is highly recommended to back up any important data/configs before proceeding."
  read -p "Are you sure you want to continue? (y/N): " choice
  case "$choice" in
    y|Y )
      echo -e "${GREEN}#${RESET} User chose to continue with the installation."
      ;;
    * )
      echo "User chose not to continue with the installation."
      exit 0
      ;;
  esac
}

accept_terms() {
  printf "\n\n"
  echo "License Agreement & Terms of Use"
  echo "__________________________"
  printf "\n\n"
  echo "Project N.O.M.A.D. is licensed under the Apache License 2.0. The full license can be found at https://www.apache.org/licenses/LICENSE-2.0 or in the LICENSE file of this repository."
  printf "\n"
  echo "By accepting this agreement, you acknowledge that you have read and understood the terms and conditions of the Apache License 2.0 and agree to be bound by them while using Project N.O.M.A.D."
  echo -e "\n\n"
  read -p "I have read and accept License Agreement & Terms of Use (y/N)? " choice
  case "$choice" in
    y|Y )
      accepted_terms='true'
      ;;
    * )
      echo "License Agreement & Terms of Use not accepted. Installation cannot continue."
      exit 1
      ;;
  esac
}

create_nomad_directory(){
  # Ensure the main installation directory exists (in user home, no sudo needed)
  if [[ ! -d "$NOMAD_DIR" ]]; then
    echo -e "${YELLOW}#${RESET} Creating directory for Project N.O.M.A.D at $NOMAD_DIR...\\n"
    mkdir -p "$NOMAD_DIR"
    echo -e "${GREEN}#${RESET} Directory created successfully.\\n"
  else
    echo -e "${GREEN}#${RESET} Directory $NOMAD_DIR already exists.\\n"
  fi

  # Create subdirectories. Use directory mounts rather than individual file mounts
  # to avoid Docker Desktop's bind-mount bug where missing files become directories.
  mkdir -p "${NOMAD_DIR}/storage/logs"
  mkdir -p "${NOMAD_DIR}/mysql"
  mkdir -p "${NOMAD_DIR}/redis"

  # Create an admin.log file in the logs directory
  touch "${NOMAD_DIR}/storage/logs/admin.log"
}

download_management_compose_file() {
  local compose_file_path="${NOMAD_DIR}/compose.yml"

  echo -e "${YELLOW}#${RESET} Downloading docker-compose file for management...\\n"
  if ! curl -fsSL "$MANAGEMENT_COMPOSE_FILE_URL" -o "$compose_file_path"; then
    echo -e "${RED}#${RESET} Failed to download the docker compose file. Please check the URL and try again."
    exit 1
  fi
  echo -e "${GREEN}#${RESET} Docker compose file downloaded successfully to $compose_file_path.\\n"

  local app_key
  local db_root_password
  local db_user_password
  app_key=$(generateRandomPass)
  db_root_password=$(generateRandomPass)
  db_user_password=$(generateRandomPass)

  # Replace the storage path placeholder with the actual NOMAD_DIR (BSD sed requires -i '')
  echo -e "${YELLOW}#${RESET} Configuring storage paths in docker-compose file...\\n"
  sed -i '' "s|NOMAD_STORAGE_PATH_PLACEHOLDER|${NOMAD_DIR}|g" "$compose_file_path"

  # Inject dynamic env values into the compose file
  echo -e "${YELLOW}#${RESET} Configuring docker-compose file env variables...\\n"
  sed -i '' "s|URL=replaceme|URL=http://${local_ip_address}:8080|g" "$compose_file_path"
  sed -i '' "s|APP_KEY=replaceme|APP_KEY=${app_key}|g" "$compose_file_path"

  sed -i '' "s|DB_PASSWORD=replaceme|DB_PASSWORD=${db_user_password}|g" "$compose_file_path"
  sed -i '' "s|MYSQL_ROOT_PASSWORD=replaceme|MYSQL_ROOT_PASSWORD=${db_root_password}|g" "$compose_file_path"
  sed -i '' "s|MYSQL_PASSWORD=replaceme|MYSQL_PASSWORD=${db_user_password}|g" "$compose_file_path"

  # Inject APPLE_CHIP_MODEL environment variable into the admin service.
  # systeminformation returns empty/generic CPU data inside Docker on macOS,
  # so we pass the detected chip model from the host for display in the admin UI.
  if [[ -n "$apple_chip_model" ]]; then
    echo -e "${YELLOW}#${RESET} Injecting Apple chip model into compose environment...\\n"
    # Add APPLE_CHIP_MODEL after the REDIS_PORT line in the admin service environment block
    sed -i '' "/- REDIS_PORT=6379/a\\
      - APPLE_CHIP_MODEL=${apple_chip_model}" "$compose_file_path"
  fi

  # If native Ollama is chosen, inject OLLAMA_HOST so the admin container
  # reaches the host-native Ollama via Docker Desktop's special DNS name.
  if [[ "${use_native_ollama}" == 'true' ]]; then
    echo -e "${YELLOW}#${RESET} Configuring native Ollama connection (host.docker.internal)...\\n"
    # Add OLLAMA_HOST after the REDIS_PORT line in the admin service environment block
    sed -i '' "/- REDIS_PORT=6379/a\\
      - OLLAMA_HOST=http://host.docker.internal:11434" "$compose_file_path"
  fi

  echo -e "${GREEN}#${RESET} Docker compose file configured successfully.\\n"
}

download_sidecar_files() {
  # Create sidecar-updater directory if it doesn't exist
  if [[ ! -d "${NOMAD_DIR}/sidecar-updater" ]]; then
    mkdir -p "${NOMAD_DIR}/sidecar-updater"
  fi

  local sidecar_dockerfile_path="${NOMAD_DIR}/sidecar-updater/Dockerfile"
  local sidecar_script_path="${NOMAD_DIR}/sidecar-updater/update-watcher.sh"

  echo -e "${YELLOW}#${RESET} Downloading sidecar updater Dockerfile...\\n"
  if ! curl -fsSL "$SIDECAR_UPDATER_DOCKERFILE_URL" -o "$sidecar_dockerfile_path"; then
    echo -e "${RED}#${RESET} Failed to download the sidecar updater Dockerfile. Please check the URL and try again."
    exit 1
  fi
  echo -e "${GREEN}#${RESET} Sidecar updater Dockerfile downloaded successfully to $sidecar_dockerfile_path.\\n"

  echo -e "${YELLOW}#${RESET} Downloading sidecar updater script...\\n"
  if ! curl -fsSL "$SIDECAR_UPDATER_SCRIPT_URL" -o "$sidecar_script_path"; then
    echo -e "${RED}#${RESET} Failed to download the sidecar updater script. Please check the URL and try again."
    exit 1
  fi
  chmod +x "$sidecar_script_path"
  echo -e "${GREEN}#${RESET} Sidecar updater script downloaded successfully to $sidecar_script_path.\\n"
}

download_helper_scripts() {
  local start_script_path="${NOMAD_DIR}/start_nomad.sh"
  local stop_script_path="${NOMAD_DIR}/stop_nomad.sh"
  local update_script_path="${NOMAD_DIR}/update_nomad.sh"

  echo -e "${YELLOW}#${RESET} Downloading helper scripts...\\n"
  if ! curl -fsSL "$START_SCRIPT_URL" -o "$start_script_path"; then
    echo -e "${RED}#${RESET} Failed to download the start script. Please check the URL and try again."
    exit 1
  fi
  chmod +x "$start_script_path"

  if ! curl -fsSL "$STOP_SCRIPT_URL" -o "$stop_script_path"; then
    echo -e "${RED}#${RESET} Failed to download the stop script. Please check the URL and try again."
    exit 1
  fi
  chmod +x "$stop_script_path"

  if ! curl -fsSL "$UPDATE_SCRIPT_URL" -o "$update_script_path"; then
    echo -e "${RED}#${RESET} Failed to download the update script. Please check the URL and try again."
    exit 1
  fi
  chmod +x "$update_script_path"

  echo -e "${GREEN}#${RESET} Helper scripts downloaded successfully to $start_script_path, $stop_script_path, and $update_script_path.\\n"
}

start_management_containers() {
  echo -e "${YELLOW}#${RESET} Starting management containers using docker compose...\\n"
  if ! docker compose -p project-nomad -f "${NOMAD_DIR}/compose.yml" up -d; then
    echo -e "${RED}#${RESET} Failed to start management containers. Please check the logs and try again."
    exit 1
  fi
  echo -e "${GREEN}#${RESET} Management containers started successfully.\\n"
}

get_local_ip() {
  # Try common macOS network interfaces
  local_ip_address=$(ipconfig getifaddr en0 2>/dev/null)

  if [[ -z "$local_ip_address" ]]; then
    # Fallback to en1 (some Macs use en1 for Wi-Fi)
    local_ip_address=$(ipconfig getifaddr en1 2>/dev/null)
  fi

  if [[ -z "$local_ip_address" ]]; then
    # Fallback: iterate over all interfaces
    local iface
    for iface in $(ifconfig -l 2>/dev/null); do
      local_ip_address=$(ipconfig getifaddr "$iface" 2>/dev/null)
      if [[ -n "$local_ip_address" ]]; then
        break
      fi
    done
  fi

  if [[ -z "$local_ip_address" ]]; then
    echo -e "${RED}#${RESET} Unable to determine local IP address. Please check your network configuration."
    exit 1
  fi
}

verify_apple_silicon() {
  # This function displays Apple Silicon / GPU status and is completely non-blocking

  echo -e "\\n${YELLOW}#${RESET} Hardware Verification\\n"
  echo -e "${YELLOW}===========================================${RESET}\\n"

  # Display detected chip model
  if [[ -n "$apple_chip_model" ]]; then
    echo -e "${GREEN}#${RESET} CPU: ${WHITE_R}${apple_chip_model}${RESET}\\n"
  else
    echo -e "${YELLOW}#${RESET} Unable to detect CPU information.\\n"
  fi

  # Check for Apple Silicon (M-series)
  local arch
  arch=$(uname -m)

  if [[ "$arch" == "arm64" ]]; then
    echo -e "${GREEN}#${RESET} Architecture: Apple Silicon (arm64)\\n"
  else
    echo -e "${YELLOW}#${RESET} Architecture: ${arch} (not Apple Silicon - some features may not be available)\\n"
  fi

  # Check for Metal support (Apple's GPU framework)
  if system_profiler SPDisplaysDataType 2>/dev/null | grep -qi "metal"; then
    echo -e "${GREEN}#${RESET} Metal GPU acceleration: Supported\\n"
  else
    echo -e "${YELLOW}#${RESET} Metal GPU acceleration: Not detected\\n"
  fi

  # Display memory info (unified memory on Apple Silicon)
  local total_mem
  total_mem=$(sysctl -n hw.memsize 2>/dev/null)
  if [[ -n "$total_mem" ]]; then
    local mem_gb=$((total_mem / 1073741824))
    echo -e "${GREEN}#${RESET} Unified Memory: ${WHITE_R}${mem_gb} GB${RESET}\\n"
  fi

  # Ollama mode
  if [[ "${use_native_ollama}" == 'true' ]]; then
    echo -e "${GREEN}#${RESET} Ollama: Native (Metal GPU acceleration enabled)\\n"
  else
    echo -e "${YELLOW}#${RESET} Ollama: Docker-based (CPU-only, no GPU acceleration)\\n"
  fi

  echo -e "${YELLOW}===========================================${RESET}\\n"

  # Summary
  if [[ "$arch" == "arm64" && "${use_native_ollama}" == 'true' ]]; then
    echo -e "${GREEN}#${RESET} Apple Silicon detected with native Ollama. AI models will use Metal GPU acceleration.\\n"
  elif [[ "$arch" == "arm64" ]]; then
    echo -e "${YELLOW}#${RESET} Apple Silicon detected but Ollama is running in Docker (CPU-only).\\n"
    echo -e "${YELLOW}#${RESET} For GPU acceleration, reinstall with native Ollama or run:${RESET}\\n"
    echo -e "${WHITE_R}    brew install ollama && brew services start ollama${RESET}\\n"
  else
    echo -e "${YELLOW}#${RESET} Running on Intel Mac. AI workloads will use CPU-only mode.\\n"
  fi
}

success_message() {
  echo -e "${GREEN}#${RESET} Project N.O.M.A.D installation completed successfully!\\n"
  echo -e "${GREEN}#${RESET} Installation files are located at ${NOMAD_DIR}\\n\\n"
  echo -e "${GREEN}#${RESET} To start Project N.O.M.A.D, run: ${WHITE_R}${NOMAD_DIR}/start_nomad.sh${RESET}\\n"
  echo -e "${GREEN}#${RESET} To stop Project N.O.M.A.D, run: ${WHITE_R}${NOMAD_DIR}/stop_nomad.sh${RESET}\\n"
  echo -e "${GREEN}#${RESET} To update Project N.O.M.A.D, run: ${WHITE_R}${NOMAD_DIR}/update_nomad.sh${RESET}\\n"
  if [[ "${use_native_ollama}" == 'true' ]]; then
    echo -e "${GREEN}#${RESET} Ollama (native): Manage with ${WHITE_R}brew services start/stop ollama${RESET}\\n"
  fi
  echo -e "${GREEN}#${RESET} You can now access the management interface at http://localhost:8080 or http://${local_ip_address}:8080\\n"
  echo -e "${GREEN}#${RESET} Thank you for supporting Project N.O.M.A.D!\\n"
}

###################################################################################################################################################################################################
#                                                                                                                                                                                                 #
#                                                                                           Main Script                                                                                           #
#                                                                                                                                                                                                 #
###################################################################################################################################################################################################

# Pre-flight checks
check_is_macos
check_is_bash
ensure_dependencies_installed
check_is_debug_mode
detect_apple_chip_model

# Main install
get_install_confirmation
accept_terms
ensure_docker_installed
check_docker_compose
prompt_ollama_mode
install_native_ollama
get_local_ip
create_nomad_directory
download_sidecar_files
download_helper_scripts
download_management_compose_file
start_management_containers
verify_apple_silicon
success_message
