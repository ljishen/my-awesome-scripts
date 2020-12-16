#!/usr/bin/env bash
#
# MIT License
#
# Copyright (c) 2018 Jianshen Liu
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

# Run this script on the host where you want to forward the SSH connection
# (port 22) to from the remote address.

set -euo pipefail

info() { printf "\\033[1;32m[INFO] %s\\033[0m\\n" "$*"; }
err() {
  local -r exit_status="$1"
  shift
  printf "\\033[1;31m[ERROR] %s\\033[0m\\n" "$*" >&2
  exit "$exit_status"
}

# https://stackoverflow.com/a/51548669
shopt -s expand_aliases
alias trace_on="{ echo; set -x; } 2>/dev/null"
alias trace_off="{ set +x; } 2>/dev/null"
export PS4='# ${BASH_SOURCE:-"$0"}:${LINENO} - ${FUNCNAME[0]:+${FUNCNAME[0]}()} > '


readonly SCRIPT_NAME="$(basename "$0")"

usage() {
  cat <<EOF
Usage: $SCRIPT_NAME [REMOTE_HOST [SSH_OPTIONS]] [stop]
       REMOTE_HOST := [user@]bind_address[:port]

Default port number is 8111.

Examples:
  # start ssh forwarding from example.com:8111 to localhost:22
  # using the given identity file
  ./$SCRIPT_NAME user@example.com:8111 -i $HOME/.ssh/id_rsa

  # stop ssh forwarding by killing the process
  ./$SCRIPT_NAME stop

EOF
  exit
}

if (( $# < 1 )); then
  # case with only one parameter: ./$SCRIPT_NAME stop
  usage
fi

readonly PID_FILE="$HOME/.${SCRIPT_NAME%.*}.pid"

pid() { cat "$PID_FILE"; }

do_stop() {
  if [[ -f "$PID_FILE" ]]; then
    local exit_status=0
    trace_on
    pkill --signal SIGTERM --pidfile "$PID_FILE" || exit_status=$?
    trace_off
    if (( exit_status == 0 )); then
      info "Terminated PID $(pid)"
      rm -f "$PID_FILE"
    else
      err "$exit_status" "Fail to terminate PID $(pid)"
    fi
  else
    err 2 "pidfile $PID_FILE does not exist!"
  fi
}

do_forward() {
  local bind_address="$1"
  local port=8111
  if [[ $bind_address == *:* ]]; then
    port="${bind_address##*:}"
    if ! [[ "$port" =~ ^[0-9]+$ ]]; then
      err 1 "Invalid port number $port"
    fi
    bind_address="${bind_address%:*}"
  fi

  # port number < 1024 requires root privileges.
  # https://www.w3.org/Daemon/User/Installation/PrivilegedPorts.html
  # https://linux.die.net/man/1/ssh
  if (( port < 1024 )); then
    if [[ "$EUID" -ne 0 ]]; then
      err 2 "Forwarding to privileged port (1-1023) requires sudo privileges."
    else
      info "WARNING: forwarding to privileged port does not guarantee to work."
    fi
  fi

  local -r log_file="/tmp/${SCRIPT_NAME%.*}.log"
  trace_on
  stdbuf -oL nohup ssh \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    -o GlobalKnownHostsFile=/dev/null \
    -o PasswordAuthentication=no \
    -o ExitOnForwardFailure=yes \
    -o ServerAliveInterval=60 \
    -N "$bind_address" \
    -R "$port":localhost:22 \
    "${@:2}" \
    < /dev/null \
    >"$log_file" 2>&1 &
  echo $! >"$PID_FILE"
  trace_off

  sleep 3
  if ! pgrep --pidfile "$PID_FILE" >/dev/null; then
    cat "$log_file"
    echo
    wait "$(pid)"
    exit $!
  fi

  info "Remote SSH port forwarding (remote $port -> local 22) is running (PID $(pid))."
}


readonly ACTION="${*: -1}"
if [[ "$ACTION" == "stop" ]]; then
  do_stop
else
  do_forward "$@"
fi
