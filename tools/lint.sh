#!/bin/bash

SCRIPT_DIR=$(dirname "$BASH_SOURCE")
PROJ_DIR=$(realpath "$SCRIPT_DIR/../")

FAILED=0

function run_check() {
    local pattern="$1"
    local err_msg="$2"

    local occurrences
    occurrences=$(grep -nRIP "$pattern" \
                  --exclude-dir='.*' $PROJ_DIR)
    if [[ ! -z $occurrences ]]; then
        FAILED=1
        echo -e "$err_msg\n"
        echo -e "$occurrences\n"
    fi
}

function check_local_command_substitution() {
    echo "Checking for misuse of local variables and command substitution."

    pattern='local [a-zA-Z0-9_]+=(\$\(|`)'
    err_msg="
Local variables are used in conjunction with command substitution. This will
prevent non-zero return codes from being intercepted. Please declare the
local variables separately."

    run_check "$pattern" "$err_msg"
}

function check_empty_line_whitespaces() {
    echo "Checking for empty lines containing whitespaces."

    pattern='^[ ]+$'
    err_msg="Empty line contains whitespaces."

    run_check "$pattern" "$err_msg"
}

function check_trailing_whitespaces() {
    echo "Checking for trailing whitespaces."

    pattern='[^ ]* +$'
    err_msg="Trailing whitespaces."

    run_check "$pattern" "$err_msg"
}


check_local_command_substitution
check_empty_line_whitespaces
check_trailing_whitespaces

exit $FAILED
