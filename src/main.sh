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
PATH_DATA="${SCRIPT_PARENT}/data"

if [[ -r ${PATH_CONFIG} ]]; then
	source "${PATH_CONFIG}"
else
	echo "<4>WARN: No config file found at ${PATH_CONFIG}. Using defaults ..."
	source "${PATH_DEFAULTS}"
fi

function set_tags {
	# requires: 
	# - ANSIBLE_LIST_TAGS_REFERENCE_PLAYBOOK
	# - PATH_DATA
	# sets:
	# - ANSIBLE_TAGS
	# - ANSIBLE_TAGS_ARRAY

	local tags_query
	local available_tags=()
	local out_name=$(basename ${ANSIBLE_LIST_TAGS_REFERENCE_PLAYBOOK})
	out_name="${out_name//.yml}" # remove .yml
	local out_path="${PATH_DATA}/tags.${out_name}"
	local run_tag_extraction=true

	# Check if the output file already exists
    if [[ -f "${out_path}" ]]; then
		echo
		echo "Tag list found: ${out_path}"
		echo -e "${CYAN}Use this tag list?${CLEAR} (Enter)"
		echo -e "${CYAN}Refresh tag list?${CLEAR} (r)"
        read -p ">> " choice
        case "${choice}" in
            r)
				run_tag_extraction=true;;
            *) 
				run_tag_extraction=false;;
        esac
    fi

	# run_tag_extraction
	if [[ "${run_tag_extraction}" == true ]]; then
		# get available tags
		echo
		echo -e "${BLINKINK}Searching for tags associated with playbook ...${CLEAR}"
		# Extracting TASK TAGS line
		local output_list_tags=$(ansible-playbook --list-tags "${ANSIBLE_LIST_TAGS_REFERENCE_PLAYBOOK}")
		# Removing the prefix and brackets
		task_tags_line="${output_list_tags#*TASK TAGS: }" # Remove from the beginning until TASK TAGS: 
		task_tags_line="${task_tags_line//[\[\]]/}" # Remove brackets
		# Converting the string into an array using IFS
		IFS=', ' read -r -a available_tags <<< "${task_tags_line}"

		if [[ ${#available_tags[@]} -eq 0 ]]; then
			echo "ERROR: Could not find any tags with playbook: ${ANSIBLE_LIST_TAGS_REFERENCE_PLAYBOOK}."
			exit 1
		else
			printf "%s\n" "${available_tags[@]}" > ${out_path} && echo "Tag list saved to: ${out_path}"
		fi
	else
		readarray -t available_tags < "${out_path}" && echo "Loaded ${#available_tags[@]} unique tags from file"
	fi

	# ask user
	echo
	echo -e "${CYAN}Enter tags${CLEAR}"
	echo -e "${GREY}Separator: comma${CLEAR}"
	echo -e "${GREY}Partial match is supported${CLEAR}"
	echo -e "${GREY}Leave empty to list available hosts${CLEAR}"
	read -p ">> " tags_query

	# user inputs nothing
	if [[ -z "${tags_query}" ]]; then
		# show full list
		select tag in "${available_tags[@]}"; do
			if [ -n "${tag}" ]; then
				ANSIBLE_TAGS="${tag}"
				echo "-> ${tag}"
				break
			else
				echo -e "${MAGENTA}Invalid choice – try again.${CLEAR}"
				continue
			fi
		done
	else
		# query
		tags_query=${tags_query,,} # make lowercase
		# Convert the comma-separated string into an array
		local tags_query_array=()
		local matches=()
		local no_matches=()
		IFS=',' read -ra tags_query_array <<< "${tags_query}"

		# Iterate through each tag in the query
		# find matches
		for query_tag in "${tags_query_array[@]}"; do
			local this_query_matches=()
			for tag in "${available_tags[@]}"; do
				tag=${tag,,} # lowercase
				if [[ ${tag} == *"${query_tag}"* ]]; then
					this_query_matches+=("${tag}")
				fi
			done
			if [[ ${#this_query_matches[@]} -eq 1 ]]; then
				matches+=("${this_query_matches[0]}")
				echo "-> ${this_query_matches[0]}"
			else
				echo -e "${CYAN}Multiple matches found for ${query_tag}. Select:${CLEAR}"
				select choice in "${this_query_matches[@]}"; do
					if [[ -z ${choice} ]]; then
						echo -e "${MAGENTA}Invalid choice – try again.${CLEAR}"
						continue
					else
						matches+=("${choice}")
						echo "-> ${choice}"
						break
					fi
				done
			fi
		done

		if [[ ${#matches[@]} -eq 0 ]]; then
			# no match
			echo -e "${MAGENTA}Could not find any matches. Please try again.${CLEAR}"
			# repeat
			set_tags
		else
			echo -e "${CYAN}Confirm the following tags:${CLEAR} ${GREY}${matches[@]}${CLEAR} (Enter)"
			read -p ">> " confirm
			if [[ -z ${confirm} ]]; then
				joined=$(printf '%s,' "${matches[@]}")
				joined=${joined%,}   # strip the trailing comma
				ANSIBLE_TAGS="${joined}"
				ANSIBLE_TAGS_ARRAY=("${matches[@]}")
			else
				echo -e "Restart."
				# repeat
				set_tags
			fi
		fi
	fi

	if [[ -n ${ANSIBLE_TAGS} ]]; then
		return 0
	else
		echo "ERROR: ANSIBLE_TAGS not set!"
		return 1
	fi
}

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
	
	# Tags
	set_tags
	echo "ANSIBLE_TAGS: ${ANSIBLE_TAGS}"
	echo "ANSIBLE_TAGS_ARRAY: ${ANSIBLE_TAGS_ARRAY[@]}"

	# Convert the input into a JSON array format
	tags_array=$(echo "${ANSIBLE_TAGS}" | tr ',' '\n' | jq -R . | jq -s .)

	if [[ ${#tags_array[@]} -eq 0 ]]; then
		echo "No Tags given. Exit."
		exit 1
	fi

	# Create a new JSON entry
	local new_entry=$(jq -n --arg id "${new_updateID}" --argjson tags "${tags_array}" '{"updateID": $id | tonumber, "tags": $tags}')
	if [[ -z ${new_entry} ]]; then
		echo "ERROR: new_entry is empty. Probably a jq compile error! Exit."
		exit 1
	fi

	# Append the new entry to the existing JSON
	local updated_content=$(echo "${current_content}" | jq ". += [${new_entry}]")
	if [[ -z ${updated_content} ]]; then
		echo "ERROR: updated_content is empty. Probably a jq compile error! Exit."
		exit 1
	fi

	# Write the updated JSON back to the file
	echo "${updated_content}" > "${ANSIBLE_PULL_CONFIG_PATH}"

	# Feedback
	echo "New entry with updateID ${new_updateID} added to ${ANSIBLE_PULL_CONFIG_PATH}"

}

main ${@}