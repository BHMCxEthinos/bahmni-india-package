#!/bin/bash

function generatePassword {
    tr -dc 'A-Za-z0-9$%&=?@_' </dev/urandom | head -c $1  ; echo
}

cp .env.template .env.init
for ENV_VAR in $(env | grep -v "^CI_" | grep -v "^LESS" | grep -v "^LS_" | grep -v "^PATH" | grep -v "^_")
do
    VAR_NAME=$(echo $ENV_VAR | cut -d"=" -f1)
    if grep -q $VAR_NAME .env.init
    then
        sed -i "s@^$VAR_NAME=\(.*\)@$ENV_VAR@g" .env.init
    fi
done

mv .env.init .env
