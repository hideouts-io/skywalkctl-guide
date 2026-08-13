# The Unofficial `skywalkctl` Field Guide

`skywalkctl` is Apple’s diagnostic command for inspecting the Skywalk networking subsystem used by macOS. It can show the kernel’s network providers, runtime nexus objects, channels, flows, interface counters, protocol statistics, memory allocators, and port reservations.

This is a hands-on guide built from 175 recorded, elevated, read-only invocations of the Apple-signed `/usr/sbin/skywalkctl` included with macOS 26.4 build 25E246. Results below are real but sanitized: hostnames, usernames, real IP addresses, identifying ports, PIDs, UUIDs, timestamps, and application inventory have been replaced or omitted.

> `skywalkctl` is a debugging interface, not a stable public API. Commands and output can change between macOS releases. Always check the help emitted by the binary installed on your Mac.

## What is included

- A guided tour of every top-level command.
- Representative sanitized output from the test run.
- A plain-English explanation immediately after each result.
- Every documented option and subcommand.
- Clear warnings for commands that change the computer.
- Read-only collection scripts that preserve command lines, output, errors, timestamps, and exit status.
- A full [command reference](REFERENCE.md) and an expanded [`skywalkctl(8)` man page](skywalkctl.8).

## Guide map

| Learning goal | Commands covered |
| --- | --- |
| Understand the object model | `show`, `provider`, `list-providers`, `tree` |
| See process attachments | `channel`, `channel-stats` |
| Investigate flows | `flow`, `flow-adv`, `flow-owner`, `flow-route`, `tcpinfo` |
| Read protocol and namespace state | `netstat`, `flowidns`, `netns`, `protons` |
| Read datapath and allocator counters | `interface`, `flow-switch`, `memory` |
| Understand logging and legacy controls | `log`, `status`, `enable` |
| Understand steering and redirection | `traffic-rule`, `redirect` |
| Check platform-specific paths | `aop`, `print-banner` |

Use the ten-minute survey for a first pass, the command-by-command guide for interpretation, and [REFERENCE.md](REFERENCE.md) when you need the complete option matrix and parser research.

## Safety map

The following commands are safe to use as read-only diagnostics:

```text
channel          flow              flow-adv          flow-owner
flow-route       flow-switch       interface         memory
netns            protons           netstat           provider
show             tree              log show          log list
status           tcpinfo           flowidns          traffic-rule show
aop              print-banner      channel-stats      list-providers
```

These forms change live or persistent state and were **not executed**:

| Command | Effect |
| --- | --- |
| `skywalkctl enable 0|1` | Changes NVRAM boot arguments and may require a reboot. |
| `skywalkctl log SK_VERB_*` | Changes kernel Skywalk logging verbosity. |
| `skywalkctl log 0` | Resets the kernel Skywalk verbosity mask. |
| `skywalkctl traffic-rule add` | Adds a live traffic-steering rule. |
| `skywalkctl traffic-rule remove` | Removes a live traffic-steering rule. |
| `skywalkctl redirect create` | Creates a redirect interface. |
| `skywalkctl redirect set` | Changes redirect-interface delegation. |
| `skywalkctl redirect destroy` | Destroys a redirect interface. |

## A simple mental model

```text
provider definition
└── nexus instance
    ├── channel endpoint → process/file descriptor
    └── flow-switch or pipe resources

network flow
├── local and remote endpoint
├── protocol and interface
├── packet/byte accounting
└── effective process attribution
```

- A **provider** defines a Skywalk service such as a netif, flow switch, user pipe, or kernel pipe.
- A **nexus** is a runtime instance of a provider.
- A **channel** is an endpoint attached to a nexus port.
- A **flow** is a Skywalk flow record. It may remain visible after the application socket has closed.
- A **flow switch** classifies and moves packets for an interface.
- A **netif** is Skywalk’s representation of a network interface.

## Start here: a ten-minute read-only survey

Run these commands in order:

```sh
sudo /usr/sbin/skywalkctl show -v
sudo /usr/sbin/skywalkctl provider -D
sudo /usr/sbin/skywalkctl tree
sudo /usr/sbin/skywalkctl channel
sudo /usr/sbin/skywalkctl flow -n
sudo /usr/sbin/skywalkctl interface
sudo /usr/sbin/skywalkctl flow-switch -G -v
sudo /usr/sbin/skywalkctl memory -a
sudo /usr/sbin/skywalkctl netns -a
sudo /usr/sbin/skywalkctl netstat -a -n
```

This sequence answers:

1. What Skywalk objects exist?
2. Which providers and instances created them?
3. Which processes have channels?
4. Which flow records are retained?
5. What are the interface and flow-switch counters?
6. How much memory is represented by Skywalk allocators?
7. Which TCP/UDP ports are reserved?

Root is not necessary for every command, but it was required for complete results on the tested Mac. `Operation not permitted` means incomplete coverage, not an empty system.

---

## Command-by-command guide

Each section answers four questions:

1. What does the command do?
2. What should I run?
3. What did the tested Mac return?
4. What does that result mean?

### 1. `show` — quick runtime overview

#### What it does

`show` is the fastest way to see active Skywalk instances. The verbose form also associates applicable pipes with attached processes and nexus ports.

#### Run this

```sh
sudo /usr/sbin/skywalkctl show -v
```

Options:

- `-h`, `--help`: print usage.
- `-v`, `--verbose`: add attached channel/process information.

#### Observed output

```text
flowswitch <NEXUS_UUID> com.apple.flowswitch.en0
flowswitch <NEXUS_UUID> com.apple.flowswitch.awdl0
flowswitch <NEXUS_UUID> com.apple.flowswitch.utun<N>
kernel-pipe <NEXUS_UUID> IOSkywalkBSDClient
user-pipe <NEXUS_UUID> <APPLE_SERVICE_PIPE>
        [ 0] <PROCESS>.<PID>
        [ 1] <PROCESS>.<PID>
```

#### What it means

The system had active flow switches for physical, peer-to-peer, and tunnel interfaces, plus kernel and user pipes. A flow-switch or pipe name is an inventory item—not proof that traffic is currently passing through it and not evidence of compromise.

Use `provider -D` for configuration details and `tree` for hierarchy.

### 2. `provider` — list provider definitions and instances

#### What it does

`provider` lists Skywalk provider definitions and their child nexus instances.

#### Run this

```sh
sudo /usr/sbin/skywalkctl provider -D
```

Options:

- `-h`, `--help`: print usage.
- `-D`, `--detail`: show ring counts, slot counts, buffer size, metadata size, memory hints, and child instances.

#### Observed output

```text
flow-switch com.apple.flowswitch.en0 <PROVIDER_UUID>
        rings: tx 1 rx 1 slots: tx 256 rx 1024
        bufsize 2048 metasize 256 mhints 0
        instance <NEXUS_UUID>

net-if AppleBCMWLANSkywalkInterface.en0 <PROVIDER_UUID>
        rings: tx 1 rx 1 slots: tx 2 rx 2
        bufsize 2048 metasize 256 mhints 0
        instance <NEXUS_UUID>
```

Provider counts from the complete snapshot:

```text
net-if       15
flow-switch   7
user-pipe    10
kernel-pipe   5
total        37
```

#### What it means

The provider line describes a service definition. `rings` and `slots` describe configured queue capacity. `bufsize` and `metasize` describe packet-buffer and metadata sizing. `instance` is the runtime nexus created from that provider.

The four provider types are normal Skywalk building blocks. Their presence alone says nothing about authorization or maliciousness.

### 3. `list-providers` — provider compatibility alias

#### What it does

`list-providers` is a compatibility alias for `provider`.

#### Run this

```sh
sudo /usr/sbin/skywalkctl list-providers -D
```

#### Observed result

The output matched `provider -D` byte-for-byte in the same snapshot.

#### What it means

Use either spelling on the tested build. `provider` is shorter and is the name described by the installed manual page.

### 4. `tree` — show the provider/nexus/channel hierarchy

#### What it does

`tree` emits Skywalk’s object hierarchy as JSON.

#### Run this

```sh
sudo /usr/sbin/skywalkctl tree > tree.json
jq -e . tree.json >/dev/null
```

To select one object:

```sh
sudo /usr/sbin/skywalkctl tree -U <PROVIDER_OR_NEXUS_UUID>
```

Options:

- `-h`, `--help`: print usage.
- `-U`, `--uuid=UUID`: start the tree at one UUID.

#### Observed output

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

Complete tree counts:

```text
root             1
nexus_provider  37
nexus           31
channel         25
```

#### What it means

The provider owns a child nexus instance. Ring/slot fields describe topology and capacity, not traffic volume. The full output parsed successfully as JSON. UUIDs are useful for correlating `tree`, `provider`, `flow-switch -U`, and `netstat -s -U`.

### 5. `channel` — show nexus channel endpoints

#### What it does

`channel` lists channels attached to nexus ports and, when available, the owning process and file descriptor.

#### Run this

```sh
sudo /usr/sbin/skywalkctl channel
sudo /usr/sbin/skywalkctl channel -C kernel_task
```

Options:

- `-h`, `--help`: print usage.
- `-C`, `--command=CMD`: filter by command.
- `-w`, `--wait=SECONDS`: repeat until interrupted.

#### Observed output

```text
Instances: 31
<INDEX> <NEXUS_UUID>
        Port[ 0] kernel_task.0 (fd -1)
<INDEX> <NEXUS_UUID>
        Port[ 1] <PROCESS>.<PID> (fd <FD>) flags=10<DEFUNCT_OK>
```

#### What it means

- `Instances: 31` is the reported instance count.
- The UUID identifies the nexus.
- `Port[0]` is a nexus port, not a TCP/UDP port.
- `fd -1` is expected for a kernel-owned endpoint.
- `DEFUNCT_OK` is a channel flag allowing a defunct state; it is not a claim that the process is malicious.

The `-C kernel_task` filter retained kernel-owned endpoints. `-w 1` repeated indefinitely, so the collector imposed an external two-second boundary.

### 6. `channel-stats` — channel compatibility alias

#### What it does

`channel-stats` exposes the same channel view and options as `channel`.

#### Run this

```sh
sudo /usr/sbin/skywalkctl channel-stats
```

#### Observed result

It produced output identical to `channel` in the same snapshot.

#### What it means

This is another compatibility command. It does not expose a different statistics schema on the tested build.

### 7. `flow` — inspect retained flow records

#### What it does

`flow` displays Skywalk flow records, endpoint information, packet/byte counters, service class, flags, state, interface, and process attribution.

#### Run this

```sh
sudo /usr/sbin/skywalkctl flow -n
sudo /usr/sbin/skywalkctl flow -n -I en0
sudo /usr/sbin/skywalkctl flow -n -p tcp
sudo /usr/sbin/skywalkctl flow -n -J > flows.json
```

Options:

| Option | Purpose |
| --- | --- |
| `-C CMD` | Filter by effective command. |
| `-I IF` | Filter by interface. |
| `-n` | Keep addresses and services numeric. |
| `-J` | Emit JSON. |
| `-p PROTO` | Filter by protocol. |
| `-P PID` | Filter by PID. |
| `-w SECONDS` | Repeat until interrupted. |

#### Observed output

```text
Proto Local Address      Remote Address       InBytes OutBytes InPkts/InSPkts ... NetIf Port Adv Flags             Process.PID
tcp4 192.0.2.10.53000    198.51.100.20.443    58100   0        193/165         ... en0   1    -   -c-q------------_  kernel_task.0(<APP>.<PID>)
```

The filtered JSON snapshot contained:

```text
flow records:                 38
protocol:                     TCP
interface:                    en0
distinct effective processes: 10
retained parsed state:        CLOSED
```

#### What it means

- `tcp4` means TCP over IPv4.
- The address columns contain endpoint and transport port.
- `Port` later in the row is a nexus port, not the TCP port.
- `BE` is the best-effort service class.
- The parenthesized process is Skywalk’s effective-process attribution even when the kernel-side owner appears as `kernel_task.0`.
- A retained `CLOSED` flow is not a live established socket.

The JSON was valid syntax but repeated the `localTrackState` key twice per flow and omitted `remoteTrackState`. Preserve raw JSON because parsers normally retain only the last duplicate value.

Flow flag legend:

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

### 8. `flow-adv` — show flow advisories

#### What it does

`flow-adv` displays flow-advisory records. Advisories are separate from the main flow table.

#### Run this

```sh
sudo /usr/sbin/skywalkctl flow-adv
sudo /usr/sbin/skywalkctl flow-adv -I en0
sudo /usr/sbin/skywalkctl flow-adv -P 0
sudo /usr/sbin/skywalkctl flow-adv -C kernel_task
```

Options: `-C CMD`, `-I IF`, and `-P PID` filter by command, interface, and PID.

#### Observed output

```text
<no output>
exit status: 0
```

#### What it means

The command completed successfully, but no advisory record matched at collection time. It does not prove that advisories have never existed.

### 9. `flow-owner` — map flow owners

#### What it does

`flow-owner` maps owner properties to interface, nexus port, bucket, and process.

#### Run this

```sh
sudo /usr/sbin/skywalkctl flow-owner
sudo /usr/sbin/skywalkctl flow-owner -I en0
```

Options: `-C CMD`, `-I IF`, and `-P PID` filter by command, interface, and PID.

#### Observed output

```text
NetIf  Port  Property  Bkt  Process
en0    1               0    kernel_task(0)
utun<N> 1              0    kernel_task(0)
```

#### What it means

The active Wi-Fi and a tunnel datapath had kernel-side ownership entries on nexus port 1. This is ownership metadata, not proof that `kernel_task` independently initiated every associated application connection.

### 10. `flow-route` — inspect flow-route entries

#### What it does

`flow-route` displays Skywalk-specific flow-route entries.

#### Run this

```sh
sudo /usr/sbin/skywalkctl flow-route -n
```

- `-n`: do not resolve service names.

#### Observed output

```text
<no output>
exit status: 0
```

#### What it means

No flow-route entry was returned at that instant. The empty result is not the same thing as the system having no BSD routing table; this command queries a specific Skywalk structure.

### 11. `netstat` — flow and protocol-statistics views

#### What it does

This is the `skywalkctl netstat` subcommand, not `/usr/sbin/netstat`. It has two primary modes:

- `-a`: flow view.
- `-s`: protocol-statistics view.

#### Run this

```sh
sudo /usr/sbin/skywalkctl netstat -a -n
sudo /usr/sbin/skywalkctl netstat -s
sudo /usr/sbin/skywalkctl netstat -s -G
sudo /usr/sbin/skywalkctl netstat -s -U <NEXUS_UUID> -v
```

Full grammar:

```text
skywalkctl netstat -a [-C command | -I interface | -P pid | -U uuid]
                    [-p protocol] [-n] [-v]
skywalkctl netstat -s [-C command | -I interface | -P pid | -U uuid]
                    [-p protocol] [-G] [-o] [-n] [-v] [-z]
skywalkctl netstat -a -s [compatible modifiers]
```

#### Observed flow output

```text
Proto Local Address      Remote Address       InBytes OutBytes ... UUID        Process.PID
tcp4 192.0.2.10.53000    198.51.100.20.443    58100   0        ... <FLOW_UUID> kernel_task.0(<APP>.<PID>)
```

The later numeric parser-matrix snapshot returned 68 data rows. Counts differ from the earlier 38-flow snapshot because network state changed between commands.

#### Observed statistics output

```text
<Closed Port Stats>
Nexus UUID: <NEXUS_UUID>
Netif     : en0
ip:
ip6:
tcp:
udp:
quic:
```

With `-z` or `-v`, those protocol headings expanded into many counters, including received/sent packets, checksum outcomes, fragments, retransmission events, connection events, and allocation failures.

#### What it means

`-a` is the flow table; `-s` is per-protocol statistics. Filters by interface, protocol, PID, command, and UUID worked when paired with a primary mode. Filters or modifiers alone exited `64` because no primary mode was selected.

Verified parser rules:

| Form | Result |
| --- | --- |
| no options or only `-n`, `-G`, `-o`, `-z` | Exit `64`, usage. |
| `-a -n` | Numeric flow view. |
| `-s` | Statistics view. |
| `-a -s` | Both views. |
| `-s -G` | Folded global statistics. |
| `-s -G -I en0` | Invalid: global conflicts with object filters. |
| `-s -o` | AOP lookup attempted; unsupported on tested hardware. |

Always use `-n` for evidence. The nonnumeric `-a` form spent substantial time resolving names and services.

### 12. `tcpinfo` — query one exact TCP tuple

#### What it does

`tcpinfo` queries Skywalk’s information for an exact local/remote TCP four-tuple.

#### Run this

```sh
sudo /usr/sbin/skywalkctl tcpinfo \
  <LOCAL_IP> <LOCAL_PORT> <REMOTE_IP> <REMOTE_PORT>
```

#### Observed output from a fresh tuple

```text
ifindex <INTERFACE_INDEX>
seq     0
ack     0
wnd     0
wscale  0
```

An earlier tuple selected too far in advance returned:

```text
flow not found
exit status: 64
```

#### What it means

The successful query matched a tuple and reported the interface index plus sequence, acknowledgement, window, and window-scale values exposed by this diagnostic. Zero values do not mean that the socket carried no data. The failed query demonstrates that tuples can disappear before `tcpinfo` reaches them.

### 13. `flowidns` — inspect flow-ID namespaces

#### What it does

`flowidns` shows allocation statistics and mappings for internal flow IDs.

#### Run this

```sh
sudo /usr/sbin/skywalkctl flowidns -v
sudo /usr/sbin/skywalkctl flowidns -v -d inpcb
sudo /usr/sbin/skywalkctl flowidns -f <HEX_FLOW_ID>
```

Options:

- `-v`: include records.
- `-d DOMAIN`: select `PF`, `IPSec`, `flowswitch`, or `inpcb`.
- `-f HEX_ID`: select one flow ID.

#### Observed output

```text
Flow ID statistics for inpcb domain
num allocs:     9779
num releases:   9703
num collisions: 0
num flowids:    76

flowID: <HEX_FLOW_ID>
        IP addresses: 192.0.2.10 <-> 198.51.100.20
        IP Protocol: 17
        Ports: <LOCAL_PORT> <-> <REMOTE_PORT>
        Domain: inpcb
```

Other tested domains:

```text
PF:         0 current flow IDs
IPSec:      0 current flow IDs
flowswitch: 0 current flow IDs
```

#### What it means

The inpcb domain was actively allocating and releasing identifiers and had no recorded collisions. Protocol 17 is UDP. `inpcb` refers to the Internet protocol control-block domain. A flow ID is an internal correlation value, not a user identity or authentication secret.

### 14. `interface` — inspect netif counters and queues

#### What it does

`interface` displays Skywalk network-interface counters, logical links, queue sets, and queue statistics.

#### Run this

```sh
sudo /usr/sbin/skywalkctl interface -I en0
sudo /usr/sbin/skywalkctl interface -I en0 -L
sudo /usr/sbin/skywalkctl interface -I en0 -Q
```

Options:

- `-G`: fold counters globally.
- `-I IF`: select an interface.
- `-L`: show logical links.
- `-Q`: show queue statistics.
- `-W SECONDS`: repeat until interrupted.

#### Observed counter output

```text
netif:
en0
<NEXUS_UUID>
        TxCopyMbuf   : 357836
        GSOSegments  : 50150
        GSOPackets   : 5893
        IfAdvUpdRecv : 1515
        LLinkAdd     : 1
```

#### Observed logical-link and queue output

```text
states: initialized(0x1)
flags: default(0x1)
qset_cnt: 1
        flags: default,AQM,ext_inited
        num_rx_queues: 1
        num_tx_queues: 4

Queue   bits/s  Pkts/s  Min Avg Max  SVC
RX[0]     0.00    0.00    0   0   0   BE
TX[0]     0.00    0.00    0   0   0   BE
TX[1]     0.00    0.00    0   0   0   BK
TX[2]     0.00    0.00    0   0   0   VI
TX[3]     0.00    0.00    0   0   0   VO
```

#### What it means

The interface had one initialized logical link and one queue set using active queue management (`AQM`). Service classes were best effort (`BE`), background (`BK`), video (`VI`), and voice (`VO`). Zero rates describe only that sampling instant; cumulative counters show the interface had processed traffic earlier.

### 15. `flow-switch` — inspect datapath counters

#### What it does

`flow-switch` displays counters from Skywalk flow-switch datapaths.

#### Run this

```sh
sudo /usr/sbin/skywalkctl flow-switch -I en0 -v
sudo /usr/sbin/skywalkctl flow-switch -G -v
sudo /usr/sbin/skywalkctl flow-switch -U <NEXUS_UUID> -v
```

Options:

- `-G`: fold globally.
- `-I IF`: select an interface.
- `-U UUID`: select a nexus.
- `-v`: expand counters.

#### Observed output highlights

```text
738234 total Rx packet
178506 dropped, flow lookup failure
     0 Rx rings stalled
     0 Incorrect TCP/IP checksum
     0 total Tx packets
     0 total dropped
     0 errors injected
```

#### What it means

These are cumulative internal datapath events, not a packet-capture summary. `flow lookup failure` is a reason-specific classification result; it should not be translated directly into 178,506 user-visible lost packets. Neighboring counters showed no ring stalls, checksum failures, injected errors, or summary drops in that section.

To assess a rate, capture two snapshots over a known interval and subtract the same counters.

### 16. `memory` — inspect Skywalk allocator state

#### What it does

`memory` shows Skywalk arenas, regions, caches, and per-process memory grouping.

#### Run this

```sh
sudo /usr/sbin/skywalkctl memory -a
sudo /usr/sbin/skywalkctl memory -a -J > memory.json
sudo /usr/sbin/skywalkctl memory -g
```

Options:

| Option | Result section |
| --- | --- |
| `-a` | All available allocator information. |
| `-A` | Arenas. |
| `-R` | Regions. |
| `-C` | Caches. |
| `-g` | Group by process. |
| `-J` | JSON output. |
| `-I IF` | Interface filter. |
| `-P PID` | PID filter. |

#### Observed JSON summary

```json
{
  "arenaCount": 40,
  "regionCount": 196,
  "cacheCount": 155,
  "totalRegionMemory": 66051760,
  "wiredRegionMemory": 16580608
}
```

Observed grouped total in a later snapshot:

```text
TOTAL: 15.78 MB memory, 15.78 MB wired
```

#### What it means

- Arenas associate clients with region types.
- Regions describe segments, object geometry, and memory totals.
- Caches describe slabs, magazines, allocations, frees, failures, and utilization.

Five caches had nonzero cumulative slab-allocation-failure counters in the full snapshot. Without a time baseline, repeated growth, or an associated symptom, that is not proof of a memory leak or exhaustion event.

### 17. `netns` — inspect port reservations

#### What it does

`netns` displays TCP and UDP port reservations for network namespaces.

#### Correct syntax

```sh
sudo /usr/sbin/skywalkctl netns -a
sudo /usr/sbin/skywalkctl netns -i 127.0.0.1 -p tcp
sudo /usr/sbin/skywalkctl netns -i ::1 -p tcp
```

Verified grammar:

```text
skywalkctl netns -a
skywalkctl netns -i IP -p {tcp|udp}
```

Without `-a`, **both** IP and protocol are required.

#### Observed output

```text
tcp port reservations for 127.0.0.1
    PORT(S)    SKYWALK        BSD   LISTENER
       <PORT>          0          1          0
```

#### What it means

This sample says that BSD had one reservation for the port, while Skywalk and listener counts were zero. A reservation is not automatically an accepting listener and does not identify the process.

Parser results:

| Input | Result |
| --- | --- |
| no options | Exit `22`: asks for `-a` or an IP. |
| only `-p tcp` | Exit `22`: missing IP. |
| only `-i 127.0.0.1` | Exit `22`: missing protocol. |
| valid IP and protocol | Table or silent exit `2` when no namespace matched. |
| `-a` plus other filters | Other filters ignored with a warning. |

### 18. `protons` — show protocol reference counts

#### What it does

`protons` lists numeric IP protocol/IPv6 next-header values and reference counts.

#### Run this

```sh
sudo /usr/sbin/skywalkctl protons
```

#### Observed output

```text
Proto RefCnt Pid ePid
0     3      0   0
1     2      0   0
6     2      0   0
17    2      0   0
41    3      0   0
58    2      0   0
```

#### What it means

`Proto` uses the IANA protocol-number registry: for example, 1 is ICMP, 6 is TCP, 17 is UDP, 41 is IPv6 encapsulation, and 58 is IPv6 ICMP. `RefCnt` is the reported reference count. PID 0 indicates kernel attribution in this view.

The binary advertised `-a`, `-i`, and `-p`, but all three were rejected with exit `64`. Only the no-option form worked on the tested build.

### 19. `log` — inspect or change Skywalk logging

#### Read-only subcommands

```sh
sudo /usr/sbin/skywalkctl log show
sudo /usr/sbin/skywalkctl log list
```

Observed results:

```text
log show: exit 0, no named active flag printed
log list: exit 0, 64 bit positions enumerated
```

`log list` printed names such as `SK_VERB_FLOW`, `SK_VERB_NETIF`, `SK_VERB_DROP`, and reserved entries with their hexadecimal masks.

#### State-changing subcommands — do not run casually

```text
skywalkctl log SK_VERB_NAME   # sets kernel verbosity
skywalkctl log 0              # resets the verbosity mask
```

#### What it means

`show` and `list` are safe inventory operations. The other forms change kernel logging and can generate a large volume of logs. They were not executed.

### 20. `status` — check a legacy enable setting

#### What it does

`status` checks a Skywalk-related boot/sysctl setting.

#### Run this

```sh
sudo /usr/sbin/skywalkctl status
```

#### Observed output

```text
sysctlbyname failed: No such file or directory
skywalkctl: sysctl net.link.generic.system.if_attach_nx failed: No such file or directory
Skywalk is NOT enabled currently
exit status: 71
```

#### What it means

The utility queried a sysctl that does not exist on the tested kernel. The printed “NOT enabled” conclusion is unreliable on this build because `provider`, `tree`, `channel`, `flow`, and `interface` simultaneously returned populated Skywalk state.

Treat `status` as a legacy boot-setting probe, not a definitive runtime-presence test.

### 21. `enable` — change Skywalk boot arguments

#### What it does

```text
skywalkctl enable 1   # enable through boot arguments
skywalkctl enable 0   # disable through boot arguments
```

#### Result

**Not executed.** The syntax was documented from installed usage text only.

#### Why it was not executed

This root-only command edits NVRAM `boot-args`, persists across boots, and may require a reboot. It is not an information-gathering command.

### 22. `traffic-rule` — inspect or change traffic steering

#### Read-only subcommand

```sh
sudo /usr/sbin/skywalkctl traffic-rule show
```

Observed result:

```text
<no output>
exit status: 0
```

No traffic-steering rule was returned at collection time.

#### State-changing subcommands

```text
skywalkctl traffic-rule add -t inet -p {tcp|udp} \
  [-l local-address] [-r remote-address] \
  [-L local-port] [-R remote-port] \
  -q queue-set [-i interface]

skywalkctl traffic-rule add -t eth \
  [-e {eap|wai}] [-m remote-mac] \
  -q queue-set [-i interface]

skywalkctl traffic-rule remove -u RULE_UUID
```

#### What the arguments mean

- `-t`: rule type, `inet` or `eth`.
- `-p`: TCP or UDP for inet rules.
- `-l`, `-r`: local and remote addresses.
- `-L`, `-R`: local and remote ports.
- `-e`: Ethernet type (`eap` or `wai`).
- `-m`: remote MAC address.
- `-q`: destination queue-set ID.
- `-i`: interface.
- `-u`: UUID of a rule to remove.

`add` and `remove` were not executed because they change live traffic steering.

### 23. `redirect` — manage redirect interfaces

#### Syntax

```text
skywalkctl redirect create -t {ethernet|cellular} [-d delegate] INTERFACE
skywalkctl redirect set -d {delegate|none} INTERFACE
skywalkctl redirect destroy INTERFACE
```

#### Result

No functional redirect subcommand was intentionally executed.

#### What each subcommand does

- `create`: creates a redirect interface.
- `set`: changes or clears its delegate interface.
- `destroy`: destroys the named redirect interface.

#### Important parser hazard

```text
skywalkctl redirect destroy -h
```

is **not** a help command on the tested build. The binary treated `-h` as an interface name and attempted `SIOCIFDESTROY`. It failed with `Invalid argument`, so nothing changed. Do not use this form to discover syntax.

### 24. `aop` — inspect AOP network statistics

#### What it does

```sh
sudo /usr/sbin/skywalkctl aop
sudo /usr/sbin/skywalkctl aop -b
```

- `-b`, `--bitmap`: request AOP activity bitmaps.

#### Observed output

```text
AOP:
skywalkctl: sysctlbyname with buffer for data failed: Operation not supported
exit status: 0
```

The bitmap form returned no output and exited `0`.

#### What it means

The tested hardware/build did not expose the requested AOP statistics. `Operation not supported` is a platform coverage result, not evidence of corruption or tampering.

### 25. `print-banner` — undocumented banner path

#### Run this

```sh
/usr/sbin/skywalkctl print-banner
```

#### Observed output

```text
<no output>
exit status: 0
```

#### What it means

This appears to be an internal or compatibility path. It performed no visible action on the tested build.

---

## What the complete run found

The authoritative evidence set contains:

```text
base command sweep:          65 invocations
corrected option variations: 61 invocations
parser matrix:               49 invocations
total:                      175 invocations
```

Main findings:

- The Skywalk runtime was populated with 37 providers, 31 nexus instances, and 25 channels.
- The provider inventory contained 15 net-if, seven flow-switch, ten user-pipe, and five kernel-pipe providers.
- Flow snapshots changed over time, as expected for live network state.
- Retained flow rows were not equivalent to established sockets.
- The JSON flow output had duplicate-key schema defects.
- `netns` requires either `-a` or both IP and protocol.
- `skywalkctl netstat` requires `-a` or `-s` as a primary mode.
- `protons` advertised filters that its parser rejected.
- `status` used a missing legacy sysctl and produced an unreliable disabled conclusion.
- AOP statistics were unsupported on the tested platform.
- The mutating commands were not executed.
- Nothing in the results independently demonstrated compromise.

## How to interpret empty output and errors

| Result | Interpretation |
| --- | --- |
| Exit `0`, no stdout/stderr | Valid instantaneous empty result. |
| `Operation not permitted` | Privilege/coverage gap. |
| `Operation not supported` | Hardware or build lacks that surface. |
| Missing sysctl | Installed utility queried a kernel key absent from this build. |
| `flow not found` | Exact tuple disappeared or was not represented. |
| Exit `2` from valid `netns` pair | No matching namespace record on tested build. |
| Exit `22` | Invalid or incomplete `netns` arguments. |
| Exit `64` or `255` | Usage/parser result, not a network finding. |
| Exit `137` in saved wait captures | Collector intentionally terminated an unbounded wait mode. |

## Filtering large output

```sh
# Flows on one interface
sudo /usr/sbin/skywalkctl flow -n -I en0

# TCP flows only
sudo /usr/sbin/skywalkctl flow -n -p tcp

# Channels for one command
sudo /usr/sbin/skywalkctl channel -C process_name

# One flow-switch instance
sudo /usr/sbin/skywalkctl flow-switch -U <NEXUS_UUID> -v

# One tree subtree
sudo /usr/sbin/skywalkctl tree -U <UUID>

# One flow-ID domain
sudo /usr/sbin/skywalkctl flowidns -v -d inpcb

# One nexus's protocol statistics
sudo /usr/sbin/skywalkctl netstat -s -U <NEXUS_UUID> -v
```

Prefer numeric output (`-n`) during evidence collection. It prevents slow name/service resolution and avoids introducing unrelated DNS activity.

## Saving commands and results

Three collectors are included:

| Script | Purpose |
| --- | --- |
| [`collect-read-only.zsh`](scripts/collect-read-only.zsh) | Every top-level command family and primary read-only view. |
| [`collect-variations.zsh`](scripts/collect-variations.zsh) | Documented read-only options, filters, JSON views, and bounded waits. |
| [`test-parser-matrix.zsh`](scripts/test-parser-matrix.zsh) | Verified `netns` and `netstat` grammar. |

Run the base collector:

```sh
output_directory="$PWD/evidence/$(date -u +%Y%m%dT%H%M%SZ)"

sudo ./scripts/collect-read-only.zsh \
  "$output_directory" "$(id -u)" "$(id -g)"
```

Each invocation produces:

```text
<label>.command       exact shell-escaped command
<label>.stdout        standard output
<label>.stderr        standard error
<label>.exit-status   numeric exit status
<label>.started-utc   start time
<label>.ended-utc     end time
```

The output directory is mode `700`. The collectors never invoke a settings-changing Skywalk command.

## Privacy before publishing results

Raw `skywalkctl` output can fingerprint a Mac even when it contains no password or token. Before putting results on GitHub, redact:

- host and user names;
- real local and remote IP addresses;
- identifying port combinations;
- live PIDs;
- runtime UUIDs;
- precise timestamps;
- application inventory.

Always remove material that could directly grant access:

- passwords or password hashes;
- API/session tokens;
- cookies or authorization headers;
- private keys;
- Wi-Fi or VPN secrets;
- recovery codes;
- reusable signed URLs.

No access-bearing credential was found in the collected `skywalkctl` output.

## License

This project is available under the permissive [MIT License](LICENSE). Anyone
may use, copy, modify, publish, distribute, sublicense, or sell copies, provided
the copyright and license notice are retained.

## Additional documentation

- [Complete option reference and research notes](REFERENCE.md)
- [Expanded `skywalkctl(8)` man page](skywalkctl.8)
- [Apple XNU source](https://github.com/apple-oss-distributions/xnu)
- [Skywalk nexus/channel syscall definitions](https://github.com/apple-oss-distributions/xnu/blob/main/bsd/kern/syscalls.master)
- [IANA protocol-number registry](https://www.iana.org/assignments/protocol-numbers/protocol-numbers.xhtml)

Preview the included man page without installing it:

```sh
mandoc -Tascii ./skywalkctl.8 | less
```

This guide documents observed diagnostic behavior. It is not an Apple API contract and should not be used to label unfamiliar networking objects as malicious without independent evidence.
