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

run_capture "000-sw-vers" /usr/bin/sw_vers
run_capture "001-uname" /usr/bin/uname -a
run_capture "002-id" /usr/bin/id
run_capture "003-binary-sha256" /usr/bin/shasum -a 256 "$skywalkctl_binary"
run_capture "004-binary-codesign" /usr/bin/codesign -dvvv --verbose=4 "$skywalkctl_binary"
run_capture "005-man-page" /usr/bin/env MANPAGER=cat PAGER=cat /usr/bin/man 8 skywalkctl
run_capture "006-top-level-usage" "$skywalkctl_binary"

typeset -a skywalk_subcommands=(
  channel
  flow
  flow-adv
  flow-owner
  flow-route
  flow-switch
  interface
  memory
  netns
  protons
  netstat
  provider
  show
  tree
  log
  status
  enable
  tcpinfo
  flowidns
  traffic-rule
  redirect
  aop
  print-banner
  channel-stats
  list-providers
)

typeset -i help_index=10
typeset skywalk_subcommand
for skywalk_subcommand in "${skywalk_subcommands[@]}"; do
  run_capture "$(printf '%03d' "$help_index")-help-$skywalk_subcommand" \
    "$skywalkctl_binary" "$skywalk_subcommand" -h
  (( help_index += 1 ))
done

run_capture "100-channel" "$skywalkctl_binary" channel
run_capture "101-flow-numeric" "$skywalkctl_binary" flow -n
run_capture "102-flow-json" "$skywalkctl_binary" flow -n -J
run_capture "103-flow-adv" "$skywalkctl_binary" flow-adv
run_capture "104-flow-owner" "$skywalkctl_binary" flow-owner
run_capture "105-flow-route" "$skywalkctl_binary" flow-route -n
run_capture "106-flow-switch" "$skywalkctl_binary" flow-switch -v
run_capture "107-flow-switch-global" "$skywalkctl_binary" flow-switch -G -v
run_capture "108-interface" "$skywalkctl_binary" interface
run_capture "109-interface-global" "$skywalkctl_binary" interface -G
run_capture "110-interface-llink" "$skywalkctl_binary" interface -L
run_capture "111-interface-queue" "$skywalkctl_binary" interface -Q
run_capture "112-memory-all" "$skywalkctl_binary" memory -a
run_capture "113-memory-json" "$skywalkctl_binary" memory -a -J
run_capture "114-netns-all" "$skywalkctl_binary" netns -a
run_capture "115-protons" "$skywalkctl_binary" protons
run_capture "116-netstat-all" "$skywalkctl_binary" netstat -a -n -v
run_capture "117-netstat-statistics" "$skywalkctl_binary" netstat -s
run_capture "118-netstat-global-statistics" "$skywalkctl_binary" netstat -G -s -z
run_capture "119-provider-detail" "$skywalkctl_binary" provider -D
run_capture "120-show-verbose" "$skywalkctl_binary" show -v
run_capture "121-tree" "$skywalkctl_binary" tree
run_capture "122-log-show" "$skywalkctl_binary" log show
run_capture "123-log-list" "$skywalkctl_binary" log list
run_capture "124-status" "$skywalkctl_binary" status
run_capture "125-flowidns-verbose" "$skywalkctl_binary" flowidns -v
run_capture "126-traffic-rule-show" "$skywalkctl_binary" traffic-rule show
run_capture "127-aop" "$skywalkctl_binary" aop
run_capture "128-aop-bitmap" "$skywalkctl_binary" aop -b
run_capture "129-print-banner" "$skywalkctl_binary" print-banner
run_capture "130-channel-stats" "$skywalkctl_binary" channel-stats
run_capture "131-list-providers" "$skywalkctl_binary" list-providers -D

print -r -- "64" > "$output_directory/EXPECTED_INVOCATION_COUNT.txt"
print -r -- "$command_count" > "$output_directory/ACTUAL_INVOCATION_COUNT.txt"
chmod -R go-rwx "$output_directory"
/usr/sbin/chown -R "$owner_uid:$owner_gid" "$output_directory"
print -r -- "Collected $command_count read-only invocations in $output_directory"
