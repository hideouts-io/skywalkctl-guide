# Learning `skywalkctl` on macOS

`skywalkctl` is Apple's command-line diagnostic utility for the macOS Skywalk networking subsystem. The installed manual describes Skywalk as plumbing between networking-related software and hardware, and warns that the tool is intended only for testing and debugging.

This guide is based on the Apple-signed `/usr/sbin/skywalkctl` shipped with macOS 26.4 build 25E246. Treat the output of your own installed binary as authoritative because commands, flags, privileges, and output schemas can change between macOS builds.

## Safety first

Most `skywalkctl` commands inspect kernel networking state. Four command families can change live or persistent state:

| Command | What can change | Why it is risky |
| --- | --- | --- |
| `enable` | NVRAM `boot-args` | The change is persistent and may require a reboot. |
| `log` with a flag or `0` | Kernel Skywalk verbosity | It can produce heavy logging or clear the current verbosity mask. |
| `traffic-rule add/remove` | Traffic-steering rules | A bad rule can redirect or disrupt traffic. |
| `redirect create/set/destroy` | Redirect interfaces and delegation | It changes live interface topology. |

Do not put those operations into an inventory script. The collector in this repository runs only their help or read-only forms.

## What the main objects mean

- A **provider** describes a Skywalk service such as a network interface, flow switch, user pipe, or kernel pipe.
- A **nexus** is an instance created from a provider.
- A **channel** is an endpoint attached to a nexus port; output can associate it with a process and file descriptor.
- A **flow** is Skywalk's record for a network flow. A displayed flow is not necessarily a currently established socket.
- A **flow switch** is the Skywalk component that classifies and moves packets for an interface.
- A **netif** is Skywalk's network-interface representation.

Apple's open-source XNU tree exposes the Skywalk nexus and channel system-call surface in [`bsd/kern/syscalls.master`](https://github.com/apple-oss-distributions/xnu/blob/main/bsd/kern/syscalls.master). The complete [Apple XNU source tree](https://github.com/apple-oss-distributions/xnu) is useful background, but the user-space `skywalkctl` implementation and all current kernel internals are not fully documented as a stable public API.

External research fills in some useful vocabulary. Jonathan Levin's Darwin
networking notes discuss Skywalk's provider, nexus, channel, entitlement, and
sysctl-backed inspection paths. The Apple Internals glossary gives a compact
cross-reference for Skywalk, DriverKit network drivers, nexus/agent terminology,
and `skywalkctl`. A Korean macOS network interface write-up is also useful when
correlating unfamiliar interface names with the lower-level Skywalk objects shown
by this tool.

Source-derived working notes:

- Skywalk is described by independent research as undocumented XNU networking
  plumbing with limited public-source visibility. Treat every structure name and
  behavior here as observed implementation detail unless Apple documents it.
- Known provider classes include user pipes, kernel pipes, network interfaces,
  and flow switches. Flow-switch examples are relevant to `utun` and IPSec-style
  paths.
- A nexus is identified by UUID and can expose channels used for packet flow.
  Channels commonly surface transmit and receive ring concepts in diagnostic
  output.
- Levin's notes identify private sysctl data for provider and channel lists.
  `skywalkctl tree`, `provider`, and `channel` are useful because the signed
  Apple tool can translate those kernel records into readable output.
- Broad Skywalk observation and registration paths are entitlement-gated. This
  explains why reproducing `skywalkctl` behavior in an unsigned third-party tool
  is not equivalent to calling a public API.
- `proc_pidfdinfo` has an undocumented channel-info flavor referenced by Levin's
  notes. That helps explain why channel records can be mapped to descriptors,
  UUIDs, ports, and flags.
- Apple Internals summarizes Skywalk as connecting technologies and virtual
  networking paths such as Bluetooth, Wi-Fi, Thunderbolt, interfaces, and
  tunnels. It also links the terminology to nexus and agent objects.
- The Korean interface guide identifies `llw0` as a low-latency WLAN interface
  used by Skywalk, `awdl0` as Apple Wireless Direct Link for Apple continuity
  features, and `utun#` as a user-tunneling interface commonly associated with
  VPN software.
- Interface names visible through `ifconfig -l` and `ifconfig -v` are good
  starting points for correlating user-visible network devices with Skywalk
  `net-if`, `flow-switch`, and `agent` output.

## Discover the installed command set

Start with the local manual and the binary's own help:

```sh
man 8 skywalkctl
/usr/sbin/skywalkctl
/usr/sbin/skywalkctl flow -h
/usr/sbin/skywalkctl memory -h
```

Some subcommands do not implement `-h` consistently. A usage message paired with exit status `64` or `255` can mean argument validation worked; it does not automatically mean the binary is broken.

## Read-only quick start

These commands give a useful overview without changing Skywalk state:

```sh
sudo /usr/sbin/skywalkctl show -v
sudo /usr/sbin/skywalkctl tree
sudo /usr/sbin/skywalkctl provider -D
sudo /usr/sbin/skywalkctl channel
sudo /usr/sbin/skywalkctl flow -n
sudo /usr/sbin/skywalkctl interface
sudo /usr/sbin/skywalkctl flow-switch -G -v
sudo /usr/sbin/skywalkctl memory -a
sudo /usr/sbin/skywalkctl netns -a
sudo /usr/sbin/skywalkctl traffic-rule show
```

Root is not required for every command, but it is commonly required for complete kernel statistics. Without it, an empty table plus `Operation not permitted` is a coverage gap, not proof that no objects exist.

## Every top-level command

| Command | Purpose | Useful read-only invocation | Notes |
| --- | --- | --- | --- |
| `channel` | List channels, owning processes, ports, descriptors, and channel flags. | `skywalkctl channel` | `-C name` filters by command; `-w seconds` repeats. |
| `flow` | Display Skywalk flows and byte/packet accounting. | `skywalkctl flow -n` | Supports command, interface, PID, and protocol filters; `-J` emits JSON. |
| `flow-adv` | Show flow-advisory records. | `skywalkctl flow-adv` | Empty output means none were returned at that instant. |
| `flow-owner` | Map flow ownership properties to interface/port/process. | `skywalkctl flow-owner` | Supports command, interface, and PID filters. |
| `flow-route` | Show Skywalk flow-route entries. | `skywalkctl flow-route -n` | `-n` avoids name/service resolution. |
| `flow-switch` | Show per-interface or folded flow-switch counters. | `skywalkctl flow-switch -G -v` | Large counters are cumulative; a name containing `dropped` needs its specific reason and denominator. |
| `interface` | Show netif statistics. | `skywalkctl interface` | `-L` shows logical links; `-Q` shows queues; `-G` folds counters globally. |
| `memory` | Show Skywalk arenas, regions, caches, and memory totals. | `skywalkctl memory -a` | `-J` emits JSON; filters include interface and PID. |
| `netns` | Show protocol namespace and port reservations. | `skywalkctl netns -a` | Supports IP and protocol filters. A reservation is not, by itself, proof of a listening user process. |
| `protons` | Undocumented/unstable protocol-namespace view. | `skywalkctl protons` | On the tested build, advertised option handling was inconsistent. Treat its usage text and results as version-specific. |
| `netstat` | Show flows and Skywalk protocol statistics. | `skywalkctl netstat -a -n -v` | `-s` selects statistics; `-G` folds globally; this is distinct from `/usr/sbin/netstat`. |
| `provider` | List nexus providers and child instances. | `skywalkctl provider -D` | Provider type, ring count, slots, buffer size, and instance UUIDs are shown. |
| `show` | Print a concise Skywalk runtime overview. | `skywalkctl show -v` | Good first command for active instances and attached channels. |
| `tree` | Emit the provider → nexus → channel hierarchy as JSON. | `skywalkctl tree` | `-U uuid` starts at one UUID. Validate saved output with `jq -e .`. |
| `log` | Show, list, or change the kernel verbosity mask. | `skywalkctl log show`; `skywalkctl log list` | Only `show` and `list` are read-only. Setting `SK_VERB_*` or `0` changes state. |
| `status` | Check a legacy Skywalk enable/boot setting. | `skywalkctl status` | Do not use this result alone to decide whether Skywalk objects are active; see build quirks below. |
| `enable` | Enable or disable Skywalk through boot arguments. | Help only: `skywalkctl enable` | State-changing, root-only, persistent, and potentially reboot-dependent. |
| `tcpinfo` | Query Skywalk TCP details for one exact 4-tuple. | `skywalkctl tcpinfo LOCAL_IP LOCAL_PORT REMOTE_IP REMOTE_PORT` | Capture a live tuple immediately before running it; short-lived sockets often disappear first. |
| `flowidns` | Show flow-ID namespace statistics and mappings. | `skywalkctl flowidns -v` | Domains include PF, IPSec, flowswitch, and inpcb; flow IDs are hexadecimal. |
| `traffic-rule` | Add, remove, or show traffic-steering rules. | `skywalkctl traffic-rule show` | `add` and `remove` change live state. |
| `redirect` | Create, change, or destroy redirect interfaces. | Help only: `skywalkctl redirect` | Every functional subcommand is state-changing. |
| `aop` | Show AOP networking counters or activity bitmaps. | `skywalkctl aop`; `skywalkctl aop -b` | Hardware/build support varies; `Operation not supported` is a coverage result. |
| `print-banner` | Internal/undocumented banner path. | `skywalkctl print-banner` | It returned no text on the tested build. |
| `channel-stats` | Compatibility alias for channel statistics. | `skywalkctl channel-stats` | Output matched `channel` on the tested build. |
| `list-providers` | Compatibility alias for provider listing. | `skywalkctl list-providers -D` | Output matched `provider -D` on the tested build. |

Run the examples with `/usr/sbin/skywalkctl` or ensure `/usr/sbin` is in `PATH`.

The repository also contains an installable, render-checked manual page: [`skywalkctl.8`](skywalkctl.8). Preview it without installing anything:

```sh
mandoc -Tascii ./skywalkctl.8 | less
```

## Complete command and option reference

The following is the option surface exposed by the tested binary. “Observed result” refers to the elevated read-only test host, with identifying values redacted from this public document.

### `channel` and `channel-stats`

```text
skywalkctl channel [-h] [-C command] [-w seconds]
skywalkctl channel-stats [-h] [-C command] [-w seconds]
```

- `-h`, `--help`: print usage.
- `-C`, `--command=CMD`: keep channel endpoints attributed to that command.
- `-w`, `--wait=INT`: repeat every `INT` seconds until interrupted.

Output begins with an instance count, followed by an internal index, nexus UUID, port number, `process.pid`, file descriptor, and flags. A file descriptor of `-1` is expected for kernel-owned endpoints. `DEFUNCT_OK` is a channel flag, not a claim that the process is malicious or broken.

Observed result: both aliases reported 31 instances and byte-for-byte identical snapshots. The command filter successfully reduced output to kernel-owned endpoints. The `-w 1` form produced repeated snapshots and did not terminate on its own; the collector bounded it externally and therefore recorded exit `137` after intentional `SIGKILL`.

### `flow`

```text
skywalkctl flow [-h] [-C command] [-I interface] [-n] [-J]
                [-p protocol] [-P pid] [-w seconds]
```

- `-C`, `--command=CMD`: filter by effective command.
- `-I`, `--interface=IF`: filter by interface.
- `-n`, `--numeric`: suppress address and service-name resolution.
- `-J`, `--json`: emit JSON.
- `-p`, `--protocol=PROTO`: filter by protocol, such as `tcp`.
- `-P`, `--pid=PID`: filter by PID.
- `-w`, `--wait=INT`: repeat until interrupted.

Important table fields:

| Field | Meaning |
| --- | --- |
| `Proto` | Address family/protocol representation, such as `tcp4`. |
| `Local Address`, `Remote Address` | Endpoint address and port. |
| `InBytes`, `OutBytes` | Skywalk direction-specific byte accounting. A zero is not proof that the application sent no data. |
| `InPkts/InSPkts`, `OutPkts/OutSPkts` | Packet and secondary/subpacket counters. The exact `SPkts` implementation meaning is not documented by the installed manual. |
| `SvC` | Service class, such as best effort (`BE`). |
| `NetIf` | Interface name. |
| `Port` | Nexus port, not the TCP/UDP port. |
| `Adv` | Flow-advisory index, or `-` when absent. |
| `Flags` | Fixed-position flag string explained below. |
| `Local State`, `Remote State` | Flow tracking states when populated. |
| `Local RTT`, `Remote RTT` | Round-trip estimates when available. |
| `Process.PID` | Kernel-side attribution, with an effective process in parentheses when present. |

Flow flag legend from the installed binary:

| Flag | Meaning | Flag | Meaning |
| --- | --- | --- | --- |
| `t` | tracked | `c` | connected |
| `l` | listener | `q` | QoS marking |
| `w` | wait-close | `e` | close notification |
| `A` | aborted | `N` | nonviable |
| `W` | withdrawn | `T` | torn down |
| `D` | destroyed | `R` | lingering |
| `L` | low latency | `P` | parent |
| `C` | child | `S` | do not wake from sleep |

Observed result: a filtered snapshot contained 38 TCP records on the primary Wi-Fi interface across ten effective-process names. All retained state values parsed as `CLOSED`, so these rows are not 38 established connections. Interface, protocol, PID 0, and `kernel_task` filters returned the same 38 rows on this build because the visible records were kernel-side flow entries with effective-process attribution.

The JSON was syntactically valid but contained two `localTrackState` keys per flow and no `remoteTrackState` key. Most JSON parsers silently keep the last duplicate. Preserve the raw file if schema fidelity matters.

### `flow-adv`, `flow-owner`, and `flow-route`

```text
skywalkctl flow-adv [-h] [-C command] [-I interface] [-P pid]
skywalkctl flow-owner [-h] [-C command] [-I interface] [-P pid]
skywalkctl flow-route [-h] [-n]
```

- `flow-adv` exposes flow-advisory records, with command/interface/PID filters.
- `flow-owner` maps `NetIf`, nexus `Port`, owner `Property`, bucket (`Bkt`), and process.
- `flow-route` exposes Skywalk flow-route entries; `-n` prevents name/service resolution.

Observed results:

- All `flow-adv` variants exited `0` with no records.
- `flow-owner` returned kernel ownership rows. Interface filtering selected the primary Wi-Fi row; PID/command filters retained the applicable kernel rows.
- Resolved and numeric `flow-route` forms exited `0` with no entries.

These are instantaneous empty results, not proof that those tables have always been empty.

### `flow-switch`

```text
skywalkctl flow-switch [-h] [-G] [-I interface] [-U nexus-uuid] [-v]
```

- `-G`, `--global`: fold counters across instances.
- `-I`, `--interface=IF`: select one interface.
- `-U`, `--uuid=UUID`: select one nexus instance.
- `-v`, `--verbose`: print detailed counters.

Output covers receive/transmit processing, demultiplexing, classification, copies, aggregation, fragments, rings, allocation failures, queue conditions, and reason-specific drops. These are cumulative implementation events. Interpret them over a measured interval, not as standalone verdicts.

Observed result: interface and UUID selection worked. One active interface showed hundreds of thousands of received packets and a substantial cumulative `flow lookup failure` count, while ring stalls, checksum failures, injected errors, and the summary `total dropped` counter shown in that section were zero. Another selected inactive instance had zero counters. The lookup counter alone does not prove user-visible packet loss or compromise.

### `interface`

```text
skywalkctl interface [-h] [-G] [-I interface] [-L] [-Q] [-W seconds]
```

- `-G`: fold globally.
- `-I IF`: select an interface.
- `-L`: show logical links and queue sets.
- `-Q`: show queue rates and totals.
- `-W INT`: repeat until interrupted.

`-L` adds logical-link IDs, state/flags, queue-set IDs, and RX/TX queue counts. `-Q` reports bits/s, packets/s, totals, queue depth statistics, and service class (`BE`, `BK`, `VI`, `VO`).

Observed result: the primary interface reported transmit-copy, GSO, advisory-update, and logical-link counters. Its logical-link view showed one initialized default link and one queue set with one RX and four TX queues. The instantaneous queue-rate sample was zero. The bounded `-W 1` run emitted no data before external termination; this is a sampling/timing result.

### `memory`

```text
skywalkctl memory [-h] [-I interface] [-J] [-P pid]
                  [-a] [-A] [-R] [-C] [-g]
```

- `-I IF`: interface filter.
- `-J`: JSON output.
- `-P PID`: PID filter.
- `-a`: all allocator sections.
- `-A`: arenas only.
- `-R`: regions only.
- `-C`: caches only.
- `-g`: group by process.

Arena rows associate clients and region types. Region rows describe segments, object geometry, memory in use/wired/total, modes, and owning arenas. Cache rows describe slab and magazine behavior, allocations, frees, failures, utilization, and backing regions.

Observed result from the full JSON snapshot: 40 arenas, 196 regions, 155 caches, 66,051,760 bytes of total region memory, and 16,580,608 wired bytes. Grouped output attributed 15.78 MiB to the listed client processes in that later snapshot. Five caches had nonzero cumulative slab-allocation-failure counters in the earlier full snapshot. Without a time baseline or symptom, those are counter observations—not proof of a memory leak or exhaustion event.

### `netns`: verified grammar

```text
skywalkctl netns -a
skywalkctl netns -i IP -p {tcp|udp}
```

- `-a`, `--all`: complete all-namespaces mode.
- `-i`, `--ip=IP`: select an IPv4 or IPv6 namespace address.
- `-p`, `--protocol=PROTO`: select `tcp` or `udp`.

The parser matrix established:

| Invocation shape | Result |
| --- | --- |
| no options | Exit `22`: asks for `-a` or a valid IP. |
| `-p tcp` only | Exit `22`: asks for `-a` or a valid IP. |
| `-i 127.0.0.1` only | Exit `22`: asks for a valid L4 protocol. |
| `-i IP -p tcp` | Valid query; matching namespaces print a table. |
| `-i IP -p udp` | Valid query; absent namespace can exit `2` silently. |
| `-a` | Exit `0`; print all namespaces. |
| `-a` plus `-i` and/or `-p` | Exit `0` with a warning that extra specifiers are ignored. |
| malformed IP or unsupported protocol | Exit `22` with an input message. |

Output columns are port, Skywalk reservation count, BSD reservation count, and listener count. A reserved port is not automatically a listening application and does not identify the owning process.

### `protons`

```text
skywalkctl protons
```

The no-option form printed `Proto`, `RefCnt`, `Pid`, and `ePid`. `Proto` is an IP protocol/IPv6 next-header number; use the [IANA Protocol Numbers registry](https://www.iana.org/assignments/protocol-numbers/protocol-numbers.xhtml) to map values such as 6 to TCP and 17 to UDP.

Observed result: the default form returned multiple numeric protocols with kernel PID attribution. Although its usage text advertised `-a`, `-i`, and `-p`, every one of those options was rejected with exit `64`. This is a tested binary/parser defect or stale usage string; do not publish those flags as functional on this build.

### `netstat`: verified primary modes

This is the `skywalkctl` subcommand, not `/usr/sbin/netstat`.

```text
skywalkctl netstat -a [flow filters] [-n] [-v]
skywalkctl netstat -s [statistics filters] [-G] [-o] [-v] [-z] [-n]
skywalkctl netstat -a -s [compatible modifiers]
```

Primary modes:

- `-a`, `--all`: flow table.
- `-s`, `--statistics`: protocol statistics.
- `-a -s`: both flow table and statistics.

Filters and modifiers:

- `-C CMD`: command filter.
- `-I IF`: interface filter.
- `-P PID`: PID filter.
- `-p PROTO`: protocol filter.
- `-U UUID`: nexus filter.
- `-G`: folded global statistics.
- `-n`: numeric addresses/services.
- `-o`: AOP statistics; meaningful with `-s`.
- `-v`: verbose output.
- `-z`: include zero-valued statistics.

Parser-matrix results:

| Form | Result |
| --- | --- |
| no options, `-n`, `-G`, `-o`, or `-z` alone | Exit `64` with usage. A primary mode is missing. |
| `-a -n` | Successful numeric flow view. |
| `-a` without `-n` | Valid, but may block for a long time in name/service resolution. |
| `-a` plus `-I`, `-p`, `-P`, `-C`, `-U`, or `-v` | Successful flow view. |
| `-s` | Successful per-instance protocol statistics. |
| `-s -G` | Successful folded statistics. |
| `-s` plus individual interface/protocol/PID/command/UUID filters | Successful filtered statistics. |
| `-s -o` | Exit `0`; AOP lookup reported `Operation not supported` on this hardware. |
| `-s -z` | Successful and much larger because zero fields are retained. |
| `-s -v` | Successful expanded statistics. |
| `-a -s` | Successful; emitted flow and statistics sections. |
| `-s -G -I IF` | Exit `64`: global cannot be combined with interface/PID/command/UUID filters. |

In the test snapshot, `-a -I primary-interface` reduced the rows, while PID 0 and `kernel_task` retained the kernel-side flow records. UUID selection was useful in statistics mode. Use `-n` for reproducible capture.

### `provider`, `list-providers`, `show`, and `tree`

```text
skywalkctl provider [-h] [-D]
skywalkctl list-providers [-h] [-D]
skywalkctl show [-h] [-v]
skywalkctl tree [-h] [-U UUID]
```

- `provider -D` adds ring/slot/buffer/metadata sizes and instance UUIDs.
- `list-providers` is an alias; its detailed output matched `provider -D` byte-for-byte.
- `show -v` adds attached process and port information where applicable.
- `tree` emits JSON; `-U UUID` starts at one provider/nexus object.

Observed result: 37 providers—15 net-if, seven flow-switch, ten user-pipe, and five kernel-pipe—mapped to 31 nexus instances and 25 channels. The full tree contained one root and parsed successfully with `jq`. The selected subtree preserved provider configuration and its child nexus. UUIDs correlate views but do not grant access; they are nevertheless redacted here because they fingerprint one runtime.

### `log` subcommands

```text
skywalkctl log show
skywalkctl log list
skywalkctl log SK_VERB_NAME   # changes kernel logging
skywalkctl log 0              # changes kernel logging
```

| Subcommand | Effect | Test result |
| --- | --- | --- |
| `show` | Read-only current verbosity view. | Exit `0`; no named active bit was printed. |
| `list` | Read-only list of all known bit names and masks. | Exit `0`; enumerated 64 bit positions, including named and reserved entries. |
| `SK_VERB_NAME` | Set verbosity. | Documented from help only; not executed. |
| `0` | Reset verbosity. | Documented from help only; not executed. |

Changing verbosity can generate heavy kernel logging, so it is outside a read-only inventory.

### `status` and `enable`

```text
skywalkctl status
skywalkctl enable 1   # changes NVRAM boot arguments
skywalkctl enable 0   # changes NVRAM boot arguments
```

`status` is read-only. On the tested build it queried the absent `net.link.generic.system.if_attach_nx` sysctl, printed “Skywalk is NOT enabled currently,” and exited `71`. At the same time, `tree`, `provider`, `flow`, and `interface` returned populated runtime state. Therefore this `status` result describes a stale/absent boot-setting probe, not the absence of Skywalk runtime objects.

`enable 1` and `enable 0` are root-only, persistent NVRAM operations that may require reboot. Both were documented from installed help and binary usage strings but not executed.

### `tcpinfo`

```text
skywalkctl tcpinfo LOCAL_IP LOCAL_PORT REMOTE_IP REMOTE_PORT
```

The exact live TCP four-tuple is required. Fields are:

- `ifindex`: interface index;
- `seq`: TCP sequence value exposed by this diagnostic;
- `ack`: acknowledgement value;
- `wnd`: advertised/receive window value;
- `wscale`: window-scale value.

Observed results: a tuple selected too early disappeared and returned `flow not found` with exit `64`. A tuple captured immediately before the command succeeded and returned an interface index with zero values for the four TCP fields. This proves tuple timing matters; it does not imply the connection carried no traffic.

### `flowidns`

```text
skywalkctl flowidns [-v] [-d {PF|IPSec|flowswitch|inpcb}]
skywalkctl flowidns -f HEX_FLOW_ID
```

- `-v`: include individual records.
- `-d`: select a namespace domain.
- `-f`: select a hexadecimal flow ID.

Aggregate fields are allocations, releases, collisions, and current IDs. Record fields include flow ID, endpoint pair, IP protocol number, ports, and domain.

Observed result: the inpcb domain was populated and a selected ID resolved successfully; PF, IPSec, and flowswitch domains reported zero current IDs. A flow ID is an internal correlation value, not a user or remote-machine identity.

### `traffic-rule` subcommands

```text
skywalkctl traffic-rule show
skywalkctl traffic-rule add -t inet -p {tcp|udp} \
    [-l local-address] [-r remote-address] \
    [-L local-port] [-R remote-port] -q queue-set [-i interface]
skywalkctl traffic-rule add -t eth [-e {eap|wai}] \
    [-m remote-mac] -q queue-set [-i interface]
skywalkctl traffic-rule remove -u RULE_UUID
```

| Subcommand | Effect | Test result |
| --- | --- | --- |
| `show` | Read-only list of traffic-steering rules. | Exit `0`, no rules. |
| `add` | Add an inet or Ethernet queue-steering rule. | Usage validation only; no rule added. |
| `remove` | Remove the rule identified by UUID. | Usage validation only; no rule removed. |

`-t` chooses `inet` or `eth`; inet rules accept protocol, endpoint addresses, and ports; Ethernet rules accept an EAP/WAI ether type and remote MAC; `-q` supplies the queue-set ID; `-i` limits the interface. The mutating forms can disrupt traffic and were not executed.

### `redirect` subcommands

```text
skywalkctl redirect create -t {ethernet|cellular} [-d delegate] INTERFACE
skywalkctl redirect set -d {delegate|none} INTERFACE
skywalkctl redirect destroy INTERFACE
```

| Subcommand | Effect | Test result |
| --- | --- | --- |
| `create` | Create a redirect interface, optionally delegated. | Usage validation only; no interface created. |
| `set` | Change or clear an existing redirect's delegate. | Usage validation only; no delegate changed. |
| `destroy` | Destroy a redirect interface. | Syntax documented without execution. |

Critical parser finding: `redirect destroy -h` is **not** help. The tested binary treated `-h` as an interface name and attempted `SIOCIFDESTROY`; it failed with `Invalid argument`, so no interface changed. Never use that form for discovery.

### `aop`, `print-banner`, and compatibility commands

```text
skywalkctl aop [-h] [-b]
skywalkctl print-banner [-h]
skywalkctl channel-stats [channel options]
skywalkctl list-providers [provider options]
```

- `aop`: default form printed an `AOP:` heading and `Operation not supported`; `-b` returned no bitmap data. This is a hardware/build coverage result.
- `print-banner`: exited `0` with no output.
- `channel-stats`: matched `channel` byte-for-byte in the snapshot.
- `list-providers`: matched `provider -D` byte-for-byte in the snapshot.

## Overall findings from every command family

The primary publication evidence consists of 175 recorded invocations: 65 in the base sweep, 61 in the corrected option-variation sweep, and 49 in the focused `netns`/`netstat` parser matrix. Each invocation has the command, stdout, stderr, UTC boundaries, and exit status. Earlier exploratory/aborted runs remain private and are not used as authoritative results.

| Command family | Finding and interpretation |
| --- | --- |
| `channel`, `channel-stats` | Populated channel inventory; aliases matched. Kernel and ordinary Apple-service endpoints are expected runtime plumbing, not compromise evidence. |
| `flow` | Populated retained TCP-flow table. Rows were closed-state records and cannot be equated with live sockets. JSON has duplicate-key schema defects. |
| `flow-adv` | Successful empty snapshots under every tested filter. |
| `flow-owner` | Kernel ownership rows for the active Wi-Fi/tunnel datapaths. |
| `flow-route` | Successful empty resolved and numeric views. |
| `flow-switch` | Populated cumulative datapath counters; interface/UUID filters worked. Reason-specific counts need rates and traffic context. |
| `interface` | Populated netif, logical-link, queue-set, and queue views. Zero sampled queue rates were instantaneous. |
| `memory` | Populated allocator model with structured totals. Counters alone do not prove leaks. |
| `netns` | Populated BSD/Skywalk reservation tables. Verified dual-filter grammar and silent exit `2` for some valid-but-unmatched selections. |
| `protons` | Default protocol-reference table worked; every advertised filter was rejected. |
| `netstat` | `-a` and `-s` are verified primary modes; all filter/modifier behavior is documented above. Numeric mode is strongly preferred. |
| `provider`, `list-providers` | 37 providers across four types; aliases matched. Provider presence alone is not suspicious. |
| `show` | Concise populated runtime; verbose mode correlated applicable channels with processes. |
| `tree` | Valid JSON hierarchy with 37 providers, 31 nexuses, and 25 channels; UUID subtree selection worked. |
| `log` | `show`/`list` worked read-only; setters were not executed. |
| `status` | Stale sysctl path made the printed disabled conclusion unreliable on this build. |
| `enable` | Persistent mutating syntax documented only; not executed. |
| `tcpinfo` | Fresh tuple succeeded; stale tuple failed, demonstrating race sensitivity. |
| `flowidns` | Populated inpcb domain; other tested domains empty; exact-ID lookup worked. |
| `traffic-rule` | `show` returned no rules; add/remove documented only. |
| `redirect` | All functional forms documented only. The dangerous `destroy -h` parser behavior is explicitly recorded. |
| `aop` | Unsupported on the tested platform; bitmap empty. |
| `print-banner` | Successful empty output. |

Nothing in the collected results independently demonstrated compromise. The collection is a runtime snapshot, not a packet capture or historical log, and unsupported/empty surfaces remain coverage limits.

## Sanitized output examples

These examples preserve structure and meaning while replacing host-specific IPs, ports, PIDs, UUIDs, process inventory, and precise runtime identifiers.

### Channel endpoint

```text
Instances: 31
<index> <NEXUS_UUID>
        Port[ 0] <PROCESS>.<PID> (fd <FD>) flags=10<DEFUNCT_OK>
```

`Instances` is the reported snapshot total. The following identifier is a nexus instance. `Port` is a nexus port; it is not a TCP/UDP port. The process/PID and file descriptor identify the attached endpoint when available.

### Flow row

```text
Proto Local Address       Remote Address        InBytes OutBytes ... NetIf Port Adv Flags             Process.PID
tcp4 192.0.2.10.53000     198.51.100.20.443     58100   0        ... en0   1    -   -c-q------------_  kernel_task.0(<APP>.<PID>)
```

The RFC 5737 addresses are placeholders. `en0` is retained because it is a generic interface role used throughout the command examples. The kernel-side owner can be `kernel_task.0` while the parenthesized effective process identifies the client attributed by Skywalk. The compact flags indicate connected and QoS-marked positions in this example. The row must still be correlated with a live socket tool before being called an active connection.

### Provider and nexus

```text
flow-switch com.apple.flowswitch.en0 <PROVIDER_UUID>
        rings: tx 1 rx 1 slots: tx 256 rx 1024 bufsize 2048 metasize 256 mhints 0
        instance <NEXUS_UUID>
```

The provider defines a flow-switch service. Ring and slot counts describe its configured queues; `bufsize` and `metasize` describe buffer and metadata sizing. The child `instance` is the runtime nexus UUID used to correlate `tree`, `flow-switch -U`, and `netstat -s -U`.

### Tree subtree

```json
{
  "uuid": "<PROVIDER_UUID>",
  "type": "nexus_provider",
  "name": "com.apple.flowswitch.en0",
  "provider_type": "flow-switch",
  "tx_rings": 1,
  "rx_rings": 1,
  "tx_slots": 256,
  "rx_slots": 1024,
  "children": [
    {
      "uuid": "<NEXUS_UUID>",
      "type": "nexus",
      "children": []
    }
  ]
}
```

This is configuration/topology, not evidence that traffic is currently traversing the instance.

### Namespace reservation

```text
tcp port reservations for 127.0.0.1
    PORT(S)    SKYWALK        BSD   LISTENER
       <PORT>          0          1          0
```

The example says one BSD reservation exists for the port and Skywalk/listener counts are zero. It does not name the owning process and does not prove that the port is accepting connections.

### TCP tuple details

```text
ifindex <INTERFACE_INDEX>
seq     0
ack     0
wnd     0
wscale  0
```

The query successfully matched the tuple even though these diagnostic values were zero. They are not general socket byte counters.

### Flow-ID record

```text
flowID: <HEX_FLOW_ID>
        IP addresses: 192.0.2.10 <-> 198.51.100.20
        IP Protocol: 17
        Ports: <LOCAL_PORT> <-> <REMOTE_PORT>
        Domain: inpcb
```

Protocol 17 is UDP in the IANA registry. `inpcb` refers to the Internet protocol control-block domain. The flow ID is useful for internal correlation but is not a secret credential or remote identity.

### Queue set

```text
llink states: initialized(0x1)  llink flags: default(0x1)
qset flags: default,AQM,ext_inited
Queue   bits/s  Pkts/s  Min Avg Max  SVC
RX[0]     0.00    0.00    0   0   0   BE
TX[0]     0.00    0.00    0   0   0   BE
TX[1]     0.00    0.00    0   0   0   BK
TX[2]     0.00    0.00    0   0   0   VI
TX[3]     0.00    0.00    0   0   0   VO
```

The queue set supports active queue management (`AQM`) and maps queues to best-effort, background, video, and voice service classes. Zero rates describe only the sampling moment.

## Filtering large outputs

Use the command's native filters before post-processing:

```sh
sudo /usr/sbin/skywalkctl flow -n -I en0
sudo /usr/sbin/skywalkctl flow -n -p tcp
sudo /usr/sbin/skywalkctl flow -n -P 1234
sudo /usr/sbin/skywalkctl channel -C process_name
sudo /usr/sbin/skywalkctl memory -P 1234
sudo /usr/sbin/skywalkctl tree -U NEXUS_UUID
sudo /usr/sbin/skywalkctl flowidns -d inpcb
sudo /usr/sbin/skywalkctl flowidns -f HEX_FLOW_ID
```

Prefer numeric output (`-n`) during evidence collection. It avoids DNS and service-name lookups that can delay collection and introduce unrelated network activity.

## Save commands and results reproducibly

The bundled collector records:

- exact shell-escaped command line;
- separate stdout and stderr;
- UTC start and end timestamps;
- exit status;
- macOS build, kernel version, execution identity, binary SHA-256, and code-signing metadata;
- every top-level command's help/validation path;
- every available read-only command family plus useful detailed views.

Run it from the repository root:

```sh
output_directory="$PWD/evidence/$(date -u +%Y%m%dT%H%M%SZ)"
sudo ./scripts/collect-read-only.zsh "$output_directory" "$(id -u)" "$(id -g)"
```

Run the option-variation and parser collections into separate private directories:

```sh
variation_directory="$PWD/evidence/variations-$(date -u +%Y%m%dT%H%M%SZ)"
matrix_directory="$PWD/evidence/parser-matrix-$(date -u +%Y%m%dT%H%M%SZ)"

sudo ./scripts/collect-variations.zsh \
  "$variation_directory" "$(id -u)" "$(id -g)"
sudo ./scripts/test-parser-matrix.zsh \
  "$matrix_directory" "$(id -u)" "$(id -g)"
```

The variation collector covers every documented read-only option at least once. It never invokes a mutating subcommand, even in a presumed help mode; mutating syntax is documented from the already-inspected installed usage text. The parser matrix verifies `netns` and `netstat` grammar. Wait modes and nonnumeric resolution are externally bounded where necessary.

The owner UID and GID are explicit so files created under `sudo` are returned to the invoking user. The script deliberately does not run an arbitrary command string and does not execute any mutating Skywalk operation.

`tcpinfo` needs a live tuple and is therefore collected separately:

```sh
sudo /usr/sbin/skywalkctl tcpinfo 192.0.2.10 53000 198.51.100.20 443
```

The addresses above are documentation-only examples and will normally return `flow not found`. Obtain a real tuple from a socket you own, run the query immediately, and save it using the same stdout/stderr/exit-status pattern as the collector.

## How to interpret the output

### `flow` and `netstat`

- Treat the process in parentheses as the effective process attribution reported by Skywalk; the kernel side can still appear as `kernel_task.0`.
- A flow row can remain visible after the corresponding application socket changes state. Correlate with `lsof -nP -i` or `/usr/sbin/netstat -anv` before calling it live.
- Byte and packet fields are direction- and implementation-specific accounting. A zero in one direction is not proof that no application data was sent.
- Flow flags are printed in a fixed-position compact string. Use the legend from `skywalkctl flow -h` for the installed build.

### `provider`, `show`, and `tree`

These are three views of related state:

```text
provider definition
└── nexus instance
    └── channel endpoint (process, port, file descriptor)
```

UUIDs let you correlate the views. Ordinary Apple services can create net-if, flow-switch, user-pipe, and kernel-pipe providers. Their presence alone is not evidence of compromise.

### `flow-switch` and `interface`

Counters usually accumulate for the lifetime of the object or boot. Interpret a counter as:

1. a named implementation event;
2. measured over an unknown interval unless you captured a baseline;
3. meaningful only with neighboring counters and traffic volume.

For a rate, capture two snapshots and subtract counters over a known interval. Avoid `-w` in forensic scripts unless you also bound execution time.

### `memory`

`memory -a -J` is useful for structured analysis. Arena, region, and cache utilization describe kernel allocator state, not application heap use. A high utilization percentage for one cache is not automatically a leak; compare repeated snapshots and allocation-failure counters.

### Empty output and errors

Classify results instead of flattening them:

- exit `0`, empty stdout, empty stderr: the command completed but returned no records;
- `Operation not permitted`: insufficient privilege or protected kernel data;
- `Operation not supported`: the hardware or OS build does not expose that surface;
- `No such file or directory` for a sysctl: the installed tool queried a kernel key absent from this build;
- `flow not found`: the exact TCP tuple was absent by query time;
- usage text with exit `64` or `255`: argument/help parser result, not a network finding.

## Tested-build observations

The three authoritative elevated read-only collections on macOS 26.4 build 25E246 recorded 175 invocations. The base sweep covered every top-level family, the corrected variation sweep exercised every documented read-only option or subcommand at least once, and the focused matrix established the `netns` and `netstat` parser rules. Nonzero statuses were retained as parser, timeout, unsupported-surface, or stale-query evidence rather than silently discarded.

Important quirks observed on that build:

- `status` queried `net.link.generic.system.if_attach_nx`, which did not exist, then printed “NOT enabled” and exited `71`. At the same time, `provider`, `tree`, `flow`, and `interface` returned live Skywalk objects. Therefore, `status` was not a reliable runtime-presence test on that build.
- `protons` advertised `-a` but rejected it. This appears to be a command/parser mismatch.
- `aop` reported `Operation not supported`; this is not evidence of tampering.
- `tcpinfo` returned `flow not found` after the selected connection changed before collection reached it.
- `flow -J` emitted valid JSON but repeated the `localTrackState` key twice per flow and did not emit a `remoteTrackState` key. Many JSON parsers keep only the last duplicate value.
- `channel-stats` matched `channel`, and `list-providers -D` matched `provider -D`.
- `redirect destroy -h` is not help; it attempted to address an interface named `-h` and failed with `Invalid argument`. No interface changed. The reusable collector no longer invokes that form.
- Unbounded `channel -w`, `flow -w`, and `interface -W` modes required external termination. Exit `137` in those evidence records came from the collector's deliberate timeout, not from a Skywalk failure.

These observations are evidence for one binary/OS combination, not promises about earlier or later releases.

## Privacy and publication checklist

Raw output can expose:

- local and remote IP addresses and ports;
- process names and PIDs;
- interface names;
- provider, nexus, channel, and flow UUIDs;
- traffic volumes and timing;
- VPN/tunnel presence;
- host name and OS build.

Before publishing:

1. Keep raw `evidence/` outside Git; this repository ignores it by default.
2. Replace examples with RFC 5737 documentation addresses (`192.0.2.0/24`, `198.51.100.0/24`, or `203.0.113.0/24`).
3. Redact host names, user names, real endpoint addresses, identifying ports, PIDs, runtime UUIDs, precise timestamps, and application inventory. These values are not credentials, but combined values can fingerprint and correlate one host.
4. Preserve the macOS product/build version when describing command behavior.
5. State whether collection was elevated and whether any command failed.
6. Never describe an unfamiliar provider, pipe, tunnel, or counter as malicious without independent corroboration.

Always remove material that can directly grant access: passwords, password hashes, API/session tokens, cookies, private keys, Wi-Fi/VPN secrets, recovery codes, signed authenticated URLs, and reusable authorization headers. None were present in the collected `skywalkctl` output, but adjacent collection scripts or shell history can contain them.

## Sources and scope

- Local primary documentation: `man 8 skywalkctl` on the tested Mac.
- Installed binary help: `/usr/sbin/skywalkctl COMMAND -h` and command-specific usage paths.
- Apple open source: [XNU](https://github.com/apple-oss-distributions/xnu) and its [Skywalk-gated nexus/channel syscalls](https://github.com/apple-oss-distributions/xnu/blob/main/bsd/kern/syscalls.master).
- Jonathan Levin's Darwin networking notes: [Net-Work: Darwin Networking](https://newosxbook.com/bonus/vol1ch16.html).
- Apple Internals glossary: [Skywalk entry](https://mroi.github.io/apple-internals/).
- Korean macOS networking notes: [contrabass.tistory.com/127](https://contrabass.tistory.com/127).

This is an observational diagnostic guide, not an Apple API contract. `skywalkctl` is a debugging tool, its output is ephemeral, and several surfaces are undocumented or build-dependent.
