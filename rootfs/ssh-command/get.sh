#!/bin/bash

# This script outputs the ssh command to connect to the container

set -euo pipefail

function log_color() {
    color_code="$1"
    shift

    printf "\033[${color_code}m%s\033[0m\n" "$*" >&2
}

function log_red() {
    log_color "0;31" "$@"
}

function log_blue() {
    log_color "0;34" "$@"
}

function log_yellow() {
    log_color "1;33" "$@"
}

function log_task() {
    log_blue "🔃" "$@"
}

function log_manual_action() {
    log_red "⚠️" "$@"
}

function log_c() {
    log_yellow "👉" "$@"
}

function log_info() {
    log_blue "ℹ️" "$@"
}

function log_tip() {
    log_blue "💡" "$@"
}

function log_error() {
    log_red "❌" "$@"
}

function error() {
    log_error "$@"
    exit 1
}

readonly podinfo_dir="/ssh-command/podinfo"

if [[ -d "${podinfo_dir}" ]]; then
    readonly as_pod="true"
else
    log_info "Assuming not running as a pod, because the '${podinfo_dir}' was not found."
    readonly as_pod="false"
fi

if [[ "${as_pod}" == "false" ]]; then
    readonly node_host="${NODE_NAME:-}"
    if [[ -z "${node_host}" ]]; then
        error "Cannot infer hostname because the NODE_NAME env var is not set. Ensure this script is being called from Jenkins."
    fi

    readonly sshd_port="${SSHD_PORT:-}"
    if [[ -z "${sshd_port}" ]]; then
        error "Cannot infer the SSHD port because the SSHD_PORT env var is not set. Check that you have set the SSHD_PORT in the Jenkinsfile."
    fi
else
    readonly sshd_port_file="${podinfo_dir}/sshd-port"
    readonly node_fqdn_file="${podinfo_dir}/node-fqdn"

    for file in "${sshd_port_file}" "${node_fqdn_file}"; do
        if [[ ! -f "${file}" ]]; then
            error "File not found: '${file}'. Check the pod configuration."
        fi
    done

    # Wait for 30s until the sshd_port_file and node_fqdn_file are populated
    for attempt in {1..30}; do
        if [[ -s "${sshd_port_file}" && -s "${node_fqdn_file}" ]]; then
            break
        elif [[ "${attempt}" -eq 5 ]]; then
            log_task "Waiting more 25s for the '${sshd_port_file}' and '${node_fqdn_file}' to be populated"
        elif [[ "${attempt}" -eq 30 ]]; then
            error "The '${sshd_port_file}' and '${node_fqdn_file}' files were not populated. Check the dynamic-hostports installation." >&2
        fi
        sleep 1
    done

    sshd_port="$(cat "${sshd_port_file}")"
    readonly sshd_port

    node_host="$(cat "${node_fqdn_file}")"
    readonly node_host
fi

# Check if node_host is a fully qualified domain name (have a dot)
if [[ "${node_host}" == *.* ]]; then
    readonly node_fqdn="${node_host}"
    if [[ -n "${DOMAIN:-}" ]]; then
        log_info "Ignoring the DOMAIN env var because the inferred node hostname seems to be a fully qualified domain name."
    fi
elif [[ -n "${DOMAIN:-}" ]]; then
    readonly node_fqdn="${node_host}.${DOMAIN}"
    log_info "Using the DOMAIN env var to build the node's fully qualified domain name."
else
    readonly node_fqdn="${node_host}"
    log_manual_action "Inferred node hostname does not seem to be a fully qualified domain name and the DOMAIN env var is not set. The SSH command may not work."
fi

# User is hardcoded because this script may get called from within another container which will not have access to the NON_ROOT_USER environment variable.
readonly user="jenkins"

readonly ssh_host="${user}@${node_fqdn}:${sshd_port}"

log_info "The SSH host is: ${ssh_host}"
echo

log_tip "Copy the following command and paste in your terminal to access the build container:"
log_c "ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR ssh://${ssh_host} -t 'cd ${PWD}; exec bash -l'"
echo

log_tip "You can also open the build container in VS Code (via the Remote - SSH extension) by opening the following link in your browser:"
log_c "vscode://vscode-remote/ssh-remote+${ssh_host}${PWD}"
echo

log_manual_action "Don't forget that the container will be automatically deleted once the build is finished." >&2
