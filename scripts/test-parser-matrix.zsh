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
run_capture "001-tree" "$skywalkctl_binary" tree

typeset nexus_uuid
nexus_uuid=$(/usr/bin/awk -F'"' '
  /"uuid":/ { previous_uuid = $4 }
  /"type":"nexus"/ { print previous_uuid; exit }
' "$output_directory/001-tree.stdout")

if [[ -z "$nexus_uuid" ]]; then
  print -u2 -- "Could not extract a nexus UUID from tree output: $output_directory/001-tree.stdout"
  exit 65
fi
print -r -- "$nexus_uuid" > "$output_directory/SELECTED_NEXUS_UUID.txt"

run_capture "010-netns-no-options" "$skywalkctl_binary" netns
run_capture "011-netns-all" "$skywalkctl_binary" netns -a
run_capture "012-netns-protocol-only" "$skywalkctl_binary" netns -p tcp
run_capture "013-netns-ip-only" "$skywalkctl_binary" netns -i 127.0.0.1
run_capture "014-netns-ipv4-tcp" "$skywalkctl_binary" netns -i 127.0.0.1 -p tcp
run_capture "015-netns-ipv4-udp" "$skywalkctl_binary" netns -i 127.0.0.1 -p udp
run_capture "016-netns-ipv6-tcp" "$skywalkctl_binary" netns -i ::1 -p tcp
run_capture "017-netns-ipv6-udp" "$skywalkctl_binary" netns -i ::1 -p udp
run_capture "018-netns-any-ipv4-tcp" "$skywalkctl_binary" netns -i 0.0.0.0 -p tcp
run_capture "019-netns-any-ipv4-udp" "$skywalkctl_binary" netns -i 0.0.0.0 -p udp
run_capture "020-netns-any-ipv6-tcp" "$skywalkctl_binary" netns -i :: -p tcp
run_capture "021-netns-any-ipv6-udp" "$skywalkctl_binary" netns -i :: -p udp
run_capture "022-netns-unassigned-ip" "$skywalkctl_binary" netns -i 192.0.2.1 -p tcp
run_capture "023-netns-invalid-ip" "$skywalkctl_binary" netns -i not-an-ip -p tcp
run_capture "024-netns-invalid-protocol" "$skywalkctl_binary" netns -i 127.0.0.1 -p icmp
run_capture "025-netns-all-with-protocol" "$skywalkctl_binary" netns -a -p tcp
run_capture "026-netns-all-with-ip" "$skywalkctl_binary" netns -a -i 127.0.0.1
run_capture "027-netns-all-with-ip-protocol" "$skywalkctl_binary" netns -a -i 127.0.0.1 -p tcp

run_capture "100-netstat-no-options" "$skywalkctl_binary" netstat
run_capture "101-netstat-numeric-only" "$skywalkctl_binary" netstat -n
run_capture_bounded "102-netstat-all" 2 "$skywalkctl_binary" netstat -a
run_capture "103-netstat-statistics" "$skywalkctl_binary" netstat -s
run_capture "104-netstat-global-only" "$skywalkctl_binary" netstat -G
run_capture "105-netstat-aop-only" "$skywalkctl_binary" netstat -o
run_capture "106-netstat-zero-only" "$skywalkctl_binary" netstat -z

run_capture "110-netstat-all-numeric" "$skywalkctl_binary" netstat -a -n
run_capture "111-netstat-all-interface" "$skywalkctl_binary" netstat -a -I en0 -n
run_capture "112-netstat-all-protocol" "$skywalkctl_binary" netstat -a -p tcp -n
run_capture "113-netstat-all-pid" "$skywalkctl_binary" netstat -a -P 0 -n
run_capture "114-netstat-all-command" "$skywalkctl_binary" netstat -a -C kernel_task -n
run_capture "115-netstat-all-uuid" "$skywalkctl_binary" netstat -a -U "$nexus_uuid" -n
run_capture "116-netstat-all-verbose" "$skywalkctl_binary" netstat -a -v -n

run_capture "120-netstat-statistics-global" "$skywalkctl_binary" netstat -s -G
run_capture "121-netstat-statistics-interface" "$skywalkctl_binary" netstat -s -I en0
run_capture "122-netstat-statistics-protocol" "$skywalkctl_binary" netstat -s -p tcp
run_capture "123-netstat-statistics-pid" "$skywalkctl_binary" netstat -s -P 0
run_capture "124-netstat-statistics-command" "$skywalkctl_binary" netstat -s -C kernel_task
run_capture "125-netstat-statistics-uuid" "$skywalkctl_binary" netstat -s -U "$nexus_uuid"
run_capture "126-netstat-statistics-aop" "$skywalkctl_binary" netstat -s -o
run_capture "127-netstat-statistics-zero" "$skywalkctl_binary" netstat -s -z
run_capture "128-netstat-statistics-verbose" "$skywalkctl_binary" netstat -s -v
run_capture "129-netstat-statistics-numeric" "$skywalkctl_binary" netstat -s -n

run_capture "130-netstat-all-and-statistics" "$skywalkctl_binary" netstat -a -s
run_capture "131-netstat-global-with-interface" "$skywalkctl_binary" netstat -s -G -I en0
run_capture "132-netstat-all-global" "$skywalkctl_binary" netstat -a -G
run_capture "133-netstat-all-aop" "$skywalkctl_binary" netstat -a -o
run_capture "134-netstat-help" "$skywalkctl_binary" netstat -h

print -r -- "$command_count" > "$output_directory/ACTUAL_INVOCATION_COUNT.txt"
chmod -R go-rwx "$output_directory"
/usr/sbin/chown -R "$owner_uid:$owner_gid" "$output_directory"
print -r -- "Collected $command_count parser-matrix invocations in $output_directory"
