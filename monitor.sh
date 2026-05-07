#!/usr/bin/env bash
#monitor.sh - Real time monitoring dashboard
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/config.cfg"

# ANSI color constants

RST="\033[0m"
BOLD="\033[1m"
RED="\033[1;31m"
YELLOW="\033[1;33m"
GREEN="\033[1;32m"
BLUE="\033[1;34m"
CYAN="\033[1;36m"
WHITE="\033[1;37m"

BG_RED="\033[41m"
BG_YELLOW="\033[43"
BG_GREEN="\033[42m"

#Helper function to pick a color

color_by_threshold() {
	local value=$1
	local warn=$2
	local crit=$3

	if (($(echo "$value >= $crit" | bc -l)));then
		echo "$RED"
	elif (($(echo "$value >= $warn" | bc -l)));then
		echo "YELLOW"
	else
		echo "GREEN"
	fi
}

status_label() {
	local value=$1
	local warn=$2
	local crit=$3

	if (($(echo "$value >= $crit" | bc -l)));then
		echo -e "${BG_RED}${WHITE} CRITICAL ${RST}"
	elif (($(echo "$value >= $warn" | bc -l)));then
		echo "${BG_YELLOW}${WHITE} WARNING ${RST}"
	else
		echo "${BG_GREEN}${WHITE} NORMAL ${RST}"
	fi
}

draw_bar() {
	local percent=$1
	local width=30
	local filled

	filled=$(echo "$percent * $width/100" | bc)
	local empty=$((width - filled))
	local bar=""

	for (i=0;i<filled;i++); do bar+="█"; done
	for (i=0;i<empty;i++); do bar+="░"; done

	echo -e "$bar"
}


