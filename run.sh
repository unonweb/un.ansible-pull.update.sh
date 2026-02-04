#!/bin/bash

ESC=$(printf "\e")
BOLD="${ESC}[1m"
RESET="${ESC}[0m"
SCRIPT_DIR=$(dirname -- "$(readlink -f "${BASH_SOURCE}")")
EXEC_PATH="${SCRIPT_DIR}/src/main.sh"

echo -e "Use ${BOLD}ctrl + c${RESET} to exit."
while true; do
	echo "---"
	${EXEC_PATH}
done