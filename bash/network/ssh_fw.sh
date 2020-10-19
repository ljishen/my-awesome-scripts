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

# Run this script on the host that you want to forward the SSH connection
# (port 22) to from the remote address.

set -eu -o pipefail

script_name="$(basename "$0")"
args=("$@")

function usage() {
  printf "usage: %s [REMOTE_HOST] [SSH_OPTIONS] [stop]

REMOTE_HOST: [user@]bind_address[:port]

Examples:
  # start forwarding with a specified identity file
  ./%s user@piha.soe.ucsc.edu:8111 -i \"$HOME/.ssh/id_rsa\"

  # stop forwarding by killing the forwarding ssh process
  ./%s stop

" "$script_name" "$script_name" "$script_name"
  exit 1
}

args_len="${#args[@]}"
if [[ "$args_len" -lt 1 ]]; then
  # case with one parameter: ssh_fw.sh stop
  usage
fi

pid_file="$HOME/.${script_name%.*}_pid"
action="${args[-1]}"

if [[ "$action" == "stop" ]]; then
  if [[ -f "$pid_file" ]]; then
    exit_status=0
    pkill --signal SIGTERM --pidfile "$pid_file" || exit_status=$?
    if [[ "$exit_status" -eq 0 ]]; then
      echo "Terminated PID $(cat "$pid_file")"
      rm -f "$pid_file"
    else
      echo "Fail to terminate PID $(cat "$pid_file")"
      exit "$exit_status"
    fi
  else
    echo "pidfile $pid_file does not exist!"
    exit 2
  fi
else
  # action start

  if [[ "$args_len" -lt 1 ]]; then
    usage
  fi

  bind_address="${args[0]}"
  port=8111
  if [[ $bind_address == *:* ]]; then
    port="$(grep -oP ':\K\d+' <<< "$bind_address")"
    bind_address="${bind_address%:*}"
  fi

  # port number less than 1024 requires root privilege.
  # https://www.w3.org/Daemon/User/Installation/PrivilegedPorts.html
  # https://linux.die.net/man/1/ssh
  if [[ "$port" -lt 1024 ]]; then
    if [[ "$EUID" -ne 0 ]]; then
      printf "Forwarding to privileged port (1-1023) requires sudo.\\n\\n"
      exit 3
    fi

    echo "WARNING: forwarding to privileged port is not guaranteed to work."
  fi

  log_file="/tmp/${script_name%.*}.log"
  stdbuf -oL nohup ssh \
    -o PasswordAuthentication=no \
    -o ExitOnForwardFailure=yes \
    -o ServerAliveInterval=60 \
    -N "$bind_address" \
    -R "$port":localhost:22 \
    "${args[@]:1}" \
    < /dev/null \
    >"$log_file" 2>&1 &
  echo $! >"$pid_file"
  sleep 3
  if ! pgrep --pidfile "$pid_file" >/dev/null; then
    cat "$log_file"
    echo
    wait "$(cat "$pid_file")"
    exit $!
  fi

  printf "Remote SSH port forwarding (remote %d -> local 22) is running (PID %d).\\n" \
    "$port" "$(cat "$pid_file")"
fi
