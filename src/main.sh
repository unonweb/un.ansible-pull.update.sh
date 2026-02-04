#!/bin/bash

SCRIPT_PATH="$(readlink -f "${BASH_SOURCE}")"
SCRIPT_DIR=$(dirname -- "$(readlink -f "${BASH_SOURCE}")")
SCRIPT_NAME=$(basename -- "$(readlink -f "${BASH_SOURCE}")")
SCRIPT_PARENT=$(dirname "${SCRIPT_DIR}")

CLEAR="\e[0m"
BOLD="\e[1m"
UNDERLINE="\e[4m"
RED="\e[31m"
GREEN="\e[32m"
YELLOW="\e[33m"
BLUE="\e[34m"
MAGENTA="\e[35m"
CYAN="\e[36m"

# CONFIG & DEFAULTS
PATH_CONFIG="${SCRIPT_PARENT}/config.cfg"
PATH_DEFAULTS="${SCRIPT_DIR}/defaults.cfg"

if [[ -r ${PATH_CONFIG} ]]; then
	source "${PATH_CONFIG}"
else
	echo "<4>WARN: No config file found at ${PATH_CONFIG}. Using defaults ..."
	source "${PATH_DEFAULTS}"
fi

function main {
	
	if [[ -z ${ANSIBLE_PULL_CONFIG_PATH} ]]; then
		echo "ERROR: Required variable empty: ANSIBLE_PULL_CONFIG_PATH"
		exit 1
	fi

	# Read the current content of the JSON file
	local current_content=$(<"${ANSIBLE_PULL_CONFIG_PATH}")

	# Extract the highest updateID
	local max_updateID=$(echo "${current_content}" | jq 'map(.updateID) | max')

	# Increment to get the new updateID
	local new_updateID=$((max_updateID + 1))

	# Prompt the user for tags
	echo -e "${CYAN}Enter tags to update${CLEAR}"
	echo -e "${GREY}Separator: comma${CLEAR}"
	echo -e "${GREY}Leave empty for suggestions${CLEAR}"
	read -p ">> " -r tags
	
	local tags_array=()

	if [[ -z "${tags}" ]]; then
		
		if [[ -z ${ANSIBLE_LIST_TAGS_REFERENCE_PLAYBOOK} ]]; then
			echo "ERROR: Required variable empty: ANSIBLE_LIST_TAGS_REFERENCE_PLAYBOOK"
			exit 1
		fi
		
		# Extract the TASK TAGS line
		local output_list_tags=$(ansible-playbook --list-tags "${ANSIBLE_LIST_TAGS_REFERENCE_PLAYBOOK}")
		# Removing the prefix and brackets
		task_tags_line="${output_list_tags#*TASK TAGS: }" # Remove from the beginning until TASK TAGS: 
		task_tags_line="${task_tags_line//[\[\]]/}" # Remove brackets
		# Converting the string into an array using IFS
		IFS=', ' read -r -a tags_array <<< "${task_tags_line}"

		select tag in "${tags_array[@]}"; do
			if [ -n "${tag}" ]; then
				echo "-> ${tag}"
				tags="${tag}"
				break
			else
				echo "Invalid selection. Try again."
			fi
		done			
	fi

	# Convert the input into a JSON array format
	tags_array=$(echo "${tags}" | tr ',' '\n' | jq -R . | jq -s .)

	if [[ ${#tags_array[@]} -eq 0 ]]; then
		echo "No Tags given. Exit."
		exit 1
	fi

	# Create a new JSON entry
	local new_entry=$(jq -n --arg id "${new_updateID}" --argjson tags "${tags_array}" '{"updateID": ${id} | tonumber, "tags": ${tags}}')

	# Append the new entry to the existing JSON
	local updated_content=$(echo "${current_content}" | jq ". += [${new_entry}]")

	# Write the updated JSON back to the file
	echo "${updated_content}" > "${ANSIBLE_PULL_CONFIG_PATH}"

	# Feedback
	echo "New entry with updateID ${new_updateID} added to ${ANSIBLE_PULL_CONFIG_PATH}"

}

main ${@}