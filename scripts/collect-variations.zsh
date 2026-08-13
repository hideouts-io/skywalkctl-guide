#!/bin/zsh

set -u

if (( $# != 3 )); then
  print -u2 -- "Usage: $0 OUTPUT_DIRECTORY OWNER_UID OWNER_GID"
  exit 64
fi

typeset -r output_directory="$1"
typeset -r owner_uid="$2"
typeset -r owner_gid="$3"
typeset -r skywalkctl_binary="/usr/sbin/skywalkctl"
typeset -i command_count=0

mkdir -p "$output_directory"
chmod 700 "$output_directory"

run_capture() {
  typeset -r label="$1"
  shift

  typeset -r prefix="$output_directory/$label"
  typeset -i exit_status=0
  typeset argument

  : > "$prefix.command"
  for argument in "$@"; do
    printf '%q ' "$argument" >> "$prefix.command"
  done
  printf '\n' >> "$prefix.command"

  /bin/date -u '+%Y-%m-%dT%H:%M:%SZ' > "$prefix.started-utc"
  "$@" > "$prefix.stdout" 2> "$prefix.stderr"
  exit_status=$?
  print -r -- "$exit_status" > "$prefix.exit-status"
  /bin/date -u '+%Y-%m-%dT%H:%M:%SZ' > "$prefix.ended-utc"
  (( command_count += 1 ))
}

run_capture_bounded() {
  typeset -r label="$1"
  typeset -r duration_seconds="$2"
  shift 2

  typeset -r prefix="$output_directory/$label"
  typeset -i process_id=0
  typeset -i exit_status=0
  typeset argument

  : > "$prefix.command"
  printf 'bounded-to-%q-seconds ' "$duration_seconds" >> "$prefix.command"
  for argument in "$@"; do
    printf '%q ' "$argument" >> "$prefix.command"
  done
  printf '\n' >> "$prefix.command"

  /bin/date -u '+%Y-%m-%dT%H:%M:%SZ' > "$prefix.started-utc"
  "$@" > "$prefix.stdout" 2> "$prefix.stderr" &
  process_id=$!
  /bin/sleep "$duration_seconds"

  if /bin/kill -0 "$process_id" 2>/dev/null; then
    /bin/kill -TERM "$process_id"
    /bin/sleep 0.25
  fi
  if /bin/kill -0 "$process_id" 2>/dev/null; then
    /bin/kill -KILL "$process_id"
  fi
  wait "$process_id"
  exit_status=$?

  print -r -- "$exit_status" > "$prefix.exit-status"
  print -r -- "$duration_seconds" > "$prefix.bounded-seconds"
  /bin/date -u '+%Y-%m-%dT%H:%M:%SZ' > "$prefix.ended-utc"
  (( command_count += 1 ))
}

run_capture "000-collector-sha256" /usr/bin/shasum -a 256 "$0"
run_capture "001-established-tcp-snapshot" /usr/sbin/netstat -anv -p tcp

typeset selected_tuple
typeset local_endpoint
typeset remote_endpoint
typeset local_ip
typeset local_port
typeset remote_ip
typeset remote_port

selected_tuple=$(/usr/bin/awk '$1 == "tcp4" && $6 == "ESTABLISHED" { print $4 "\t" $5; exit }' \
  "$output_directory/001-established-tcp-snapshot.stdout")

if [[ -n "$selected_tuple" ]]; then
  local_endpoint="${selected_tuple%%$'\t'*}"
  remote_endpoint="${selected_tuple#*$'\t'}"
  local_ip="${local_endpoint%.*}"
  local_port="${local_endpoint##*.}"
  remote_ip="${remote_endpoint%.*}"
  remote_port="${remote_endpoint##*.}"
  print -r -- "$local_ip $local_port $remote_ip $remote_port" \
    > "$output_directory/SELECTED_TCP_TUPLE.txt"
  run_capture "002-tcpinfo-live-tuple" "$skywalkctl_binary" tcpinfo \
    "$local_ip" "$local_port" "$remote_ip" "$remote_port"
else
  print -r -- "No established IPv4 TCP tuple was available" \
    > "$output_directory/SELECTED_TCP_TUPLE.txt"
fi

run_capture "010-channel-kernel-task" "$skywalkctl_binary" channel -C kernel_task
run_capture "011-channel-stats-kernel-task" "$skywalkctl_binary" channel-stats -C kernel_task
run_capture_bounded "012-channel-wait" 2 "$skywalkctl_binary" channel -w 1

run_capture "020-flow-interface-en0" "$skywalkctl_binary" flow -n -I en0
run_capture "021-flow-protocol-tcp" "$skywalkctl_binary" flow -n -p tcp
run_capture "022-flow-pid-zero" "$skywalkctl_binary" flow -n -P 0
run_capture "023-flow-command-kernel-task" "$skywalkctl_binary" flow -n -C kernel_task
run_capture "024-flow-interface-json" "$skywalkctl_binary" flow -n -J -I en0
run_capture_bounded "025-flow-wait" 2 "$skywalkctl_binary" flow -n -w 1

run_capture "030-flow-adv-interface-en0" "$skywalkctl_binary" flow-adv -I en0
run_capture "031-flow-adv-pid-zero" "$skywalkctl_binary" flow-adv -P 0
run_capture "032-flow-adv-command-kernel-task" "$skywalkctl_binary" flow-adv -C kernel_task
run_capture "033-flow-owner-interface-en0" "$skywalkctl_binary" flow-owner -I en0
run_capture "034-flow-owner-pid-zero" "$skywalkctl_binary" flow-owner -P 0
run_capture "035-flow-owner-command-kernel-task" "$skywalkctl_binary" flow-owner -C kernel_task
run_capture "036-flow-route-resolved" "$skywalkctl_binary" flow-route
run_capture "037-flow-route-numeric" "$skywalkctl_binary" flow-route -n

run_capture "040-flow-switch-interface-en0" "$skywalkctl_binary" flow-switch -I en0 -v
run_capture "041-interface-en0" "$skywalkctl_binary" interface -I en0
run_capture "042-interface-en0-llink" "$skywalkctl_binary" interface -I en0 -L
run_capture "043-interface-en0-queue" "$skywalkctl_binary" interface -I en0 -Q
run_capture_bounded "044-interface-wait" 2 "$skywalkctl_binary" interface -I en0 -W 1

run_capture "050-memory-arena" "$skywalkctl_binary" memory -A
run_capture "051-memory-region" "$skywalkctl_binary" memory -R
run_capture "052-memory-cache" "$skywalkctl_binary" memory -C
run_capture "053-memory-grouped" "$skywalkctl_binary" memory -g
run_capture "054-memory-interface-en0" "$skywalkctl_binary" memory -I en0
run_capture "055-memory-pid-zero" "$skywalkctl_binary" memory -P 0

run_capture "060-netns-loopback-tcp" "$skywalkctl_binary" netns -i 127.0.0.1 -p tcp
run_capture "061-netns-loopback-udp" "$skywalkctl_binary" netns -i 127.0.0.1 -p udp
run_capture "062-netns-all-tcp" "$skywalkctl_binary" netns -a -p tcp
run_capture "063-protons-default" "$skywalkctl_binary" protons
run_capture "064-protons-all" "$skywalkctl_binary" protons -a
run_capture "065-protons-tcp" "$skywalkctl_binary" protons -p tcp
run_capture "066-protons-loopback" "$skywalkctl_binary" protons -i 127.0.0.1

run_capture "070-netstat-interface-en0" "$skywalkctl_binary" netstat -a -I en0 -n -v
run_capture "071-netstat-protocol-tcp" "$skywalkctl_binary" netstat -a -p tcp -n
run_capture "072-netstat-pid-zero" "$skywalkctl_binary" netstat -a -P 0 -n
run_capture "073-netstat-global-statistics" "$skywalkctl_binary" netstat -G -s
run_capture "074-netstat-aop" "$skywalkctl_binary" netstat -s -o
run_capture "075-netstat-command-kernel-task" "$skywalkctl_binary" netstat -a -C kernel_task -n

run_capture "080-provider-summary" "$skywalkctl_binary" provider
run_capture "081-show-summary" "$skywalkctl_binary" show
run_capture "082-tree-full" "$skywalkctl_binary" tree

typeset provider_uuid
provider_uuid=$(/usr/bin/awk -F'"' '/"uuid":/ { uuid_count += 1; if (uuid_count == 2) { print $4; exit } }' \
  "$output_directory/082-tree-full.stdout")

if [[ -z "$provider_uuid" ]]; then
  print -u2 -- "Could not extract a provider UUID from tree output: $output_directory/082-tree-full.stdout"
  exit 65
fi

print -r -- "$provider_uuid" > "$output_directory/SELECTED_PROVIDER_UUID.txt"
run_capture "083-tree-provider-uuid" "$skywalkctl_binary" tree -U "$provider_uuid"

typeset nexus_uuid
nexus_uuid=$(/usr/bin/awk -F'"' '
  /"uuid":/ { previous_uuid = $4 }
  /"type":"nexus"/ { print previous_uuid; exit }
' "$output_directory/082-tree-full.stdout")

if [[ -z "$nexus_uuid" ]]; then
  print -u2 -- "Could not extract a nexus UUID from tree output: $output_directory/082-tree-full.stdout"
  exit 65
fi

print -r -- "$nexus_uuid" > "$output_directory/SELECTED_NEXUS_UUID.txt"
run_capture "084-flow-switch-nexus-uuid" "$skywalkctl_binary" flow-switch -U "$nexus_uuid" -v
run_capture "085-netstat-nexus-uuid" "$skywalkctl_binary" netstat -s -U "$nexus_uuid" -v

run_capture "090-flowidns-inpcb" "$skywalkctl_binary" flowidns -v -d inpcb
run_capture "091-flowidns-flowswitch" "$skywalkctl_binary" flowidns -v -d flowswitch
run_capture "092-flowidns-pf" "$skywalkctl_binary" flowidns -v -d PF
run_capture "093-flowidns-ipsec" "$skywalkctl_binary" flowidns -v -d IPSec

typeset flow_id
flow_id=$(/usr/bin/awk '/flowID:/ { print $2; exit }' "$output_directory/090-flowidns-inpcb.stdout")
if [[ -n "$flow_id" ]]; then
  print -r -- "$flow_id" > "$output_directory/SELECTED_FLOW_ID.txt"
  run_capture "094-flowidns-specific-id" "$skywalkctl_binary" flowidns -f "$flow_id"
else
  print -r -- "No inpcb flow ID was available" > "$output_directory/SELECTED_FLOW_ID.txt"
fi

run_capture "100-log-help" "$skywalkctl_binary" log help

print -r -- "$command_count" > "$output_directory/ACTUAL_INVOCATION_COUNT.txt"
chmod -R go-rwx "$output_directory"
/usr/sbin/chown -R "$owner_uid:$owner_gid" "$output_directory"
print -r -- "Collected $command_count read-only command variations in $output_directory"
