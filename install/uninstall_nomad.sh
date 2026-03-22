#!/usr/bin/env bash

# Project N.O.M.A.D. Uninstall Script (macOS)

###################################################################################################################################################################################################

# Script                | Project N.O.M.A.D. Uninstall Script (macOS)
# Version               | 2.1.0
# Original Author       | Crosstalk Solutions, LLC
# macOS Adaptation       | proximasan
# Website               | https://crosstalksolutions.com

###################################################################################################################################################################################################
#                                                                                                                                                                                                 #
#                                                                                  Constants & Variables                                                                                          #
#                                                                                                                                                                                                 #
###################################################################################################################################################################################################

RESET='\033[0m'
YELLOW='\033[1;33m'
RED='\033[1;31m'
GREEN='\033[1;32m'

NOMAD_DIR="${HOME}/project-nomad"
MANAGEMENT_COMPOSE_FILE="${NOMAD_DIR}/compose.yml"

###################################################################################################################################################################################################
#                                                                                                                                                                                                 #
#                                                                                     Functions                                                                                                   #
#                                                                                                                                                                                                 #
###################################################################################################################################################################################################

check_current_directory(){
  if [ "$(pwd)" == "${NOMAD_DIR}" ]; then
    echo "Please run this script from a directory other than ${NOMAD_DIR}."
    exit 1
  fi
}

ensure_management_compose_file_exists(){
  if [ ! -f "${MANAGEMENT_COMPOSE_FILE}" ]; then
    echo "Unable to find the management Docker Compose file at ${MANAGEMENT_COMPOSE_FILE}. There may be a problem with your Project N.O.M.A.D. installation."
    exit 1
  fi
}

get_uninstall_confirmation(){
  read -p "This script will remove ALL Project N.O.M.A.D. files and containers. THIS CANNOT BE UNDONE. Are you sure you want to continue? (y/n): " choice
  case "$choice" in
    y|Y )
      echo -e "User chose to continue with the uninstallation."
      ;;
    n|N )
      echo -e "User chose not to continue with the uninstallation."
      exit 0
      ;;
    * )
      echo "Invalid Response"
      echo "User chose not to continue with the uninstallation."
      exit 0
      ;;
  esac
}

ensure_docker_installed() {
    if ! command -v docker &> /dev/null; then
        echo "Unable to find Docker. There may be a problem with your Docker installation."
        exit 1
    fi
}

check_docker_compose() {
  # Check if 'docker compose' (v2 plugin) is available
  if ! docker compose version &>/dev/null; then
    echo -e "${RED}#${RESET} Docker Compose v2 is not installed or not available as a Docker plugin."
    echo -e "${YELLOW}#${RESET} This script requires 'docker compose' (v2), not 'docker-compose' (v1)."
    echo -e "${YELLOW}#${RESET} Docker Desktop for Mac should include Docker Compose v2 by default."
    exit 1
  fi
}

storage_cleanup() {
  read -p "Do you want to delete the Project N.O.M.A.D. storage directory (${NOMAD_DIR})? This is best if you want to start a completely fresh install. This will PERMANENTLY DELETE all stored Nomad data and can't be undone! (y/N): " delete_dir_choice
  case "$delete_dir_choice" in
      y|Y )
          echo "Removing Project N.O.M.A.D. files..."
          if rm -rf "${NOMAD_DIR}"; then
              echo "Project N.O.M.A.D. files removed."
          else
              echo "Warning: Failed to fully remove ${NOMAD_DIR}. You may need to remove it manually."
          fi
          ;;
      * )
          echo "Skipping removal of ${NOMAD_DIR}."
          ;;
  esac
}

native_ollama_cleanup() {
  # Check if Ollama is installed natively via Homebrew and offer to remove it
  if ! command -v ollama &> /dev/null; then
    return 0
  fi

  echo ""
  echo -e "${YELLOW}#${RESET} Native Ollama installation detected."
  read -p "Do you want to stop and uninstall the native Ollama service? This will remove Ollama and any downloaded models. (y/N): " ollama_choice
  case "$ollama_choice" in
    y|Y )
      echo "Stopping Ollama service..."
      brew services stop ollama 2>/dev/null || true

      echo "Uninstalling Ollama..."
      brew uninstall ollama 2>/dev/null || true

      # Remove Ollama model data (stored in ~/.ollama by default)
      if [[ -d "${HOME}/.ollama" ]]; then
        read -p "Do you also want to remove downloaded Ollama models (~/.ollama)? (y/N): " models_choice
        case "$models_choice" in
          y|Y )
            rm -rf "${HOME}/.ollama"
            echo "Ollama models removed."
            ;;
          * )
            echo "Keeping Ollama models at ~/.ollama."
            ;;
        esac
      fi

      echo "Ollama has been uninstalled."
      ;;
    * )
      echo "Keeping native Ollama installation."
      ;;
  esac
}

uninstall_nomad() {
    echo "Stopping and removing Project N.O.M.A.D. management containers..."
    docker compose -p project-nomad -f "${MANAGEMENT_COMPOSE_FILE}" down
    echo "Allowing some time for management containers to stop..."
    sleep 5

    # Stop and remove all containers where name starts with "nomad_"
    # BSD xargs does not have -r flag; use a while-read loop instead
    echo "Stopping and removing all Project N.O.M.A.D. app containers..."
    docker ps -a --filter "name=^nomad_" --format "{{.Names}}" | while IFS= read -r container; do
      if [[ -n "$container" ]]; then
        docker rm -f "$container"
      fi
    done
    echo "Allowing some time for app containers to stop..."
    sleep 5

    echo "Containers should be stopped now."

    # Remove the shared Docker network (may still exist if app containers were using it during compose down)
    echo "Removing project-nomad_default network if it exists..."
    docker network rm project-nomad_default 2>/dev/null && echo "Network removed." || echo "Network already removed or not found."

    # Remove the shared update volume
    echo "Removing project-nomad_nomad-update-shared volume if it exists..."
    docker volume rm project-nomad_nomad-update-shared 2>/dev/null && echo "Volume removed." || echo "Volume already removed or not found."

    # Handle native Ollama cleanup
    native_ollama_cleanup

    # Prompt user for storage cleanup and handle it if so
    storage_cleanup

    echo "Project N.O.M.A.D. has been uninstalled. We hope to see you again soon!"
}

###################################################################################################################################################################################################
#                                                                                                                                                                                                 #
#                                                                                       Main                                                                                                      #
#                                                                                                                                                                                                 #
###################################################################################################################################################################################################
check_current_directory
ensure_management_compose_file_exists
ensure_docker_installed
check_docker_compose
get_uninstall_confirmation
uninstall_nomad
