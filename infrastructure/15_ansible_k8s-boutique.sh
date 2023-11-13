#!/bin/bash

source common.sh

echo "Введите godaddy token:"
read -s godaddy_token

run_command "ansible-playbook main.yml -i 'localhost' -e godaddy_authtoken=$godaddy_token -v" "ansible-k8s-boutique"
