#!/bin/bash

SCRIPT_DIR=$(dirname "$BASH_SOURCE")
PROJ_DIR="$SCRIPT_DIR/../"

pushd $PROJ_DIR
grep -RPizo ' *# TODO.*\n( *#.*\n)*'
