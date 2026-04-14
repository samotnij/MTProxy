<!--
 * @Author: Vincent Young
 * @Date: 2022-07-01 15:29:23
 * @LastEditors: Vincent Young
 * @LastEditTime: 2022-07-30 19:28:49
 * @FilePath: /MTProxy/README.md
 * @Telegram: https://t.me/missuo
 * 
 * Copyright © 2022 by Vincent, All Rights Reserved. 
-->
# MTProxy
Highly-opinionated (ex-bullshit-free) MTPROTO proxy for [Telegram](https://telegram.org).

## Intro
**If you have used MTProxy before, you must be using Version 1. At present, the scripts on the Internet are basically Version 1. And my script uses the new Version 2.**

### Differences between v1 and v2
- Configuration file incompatibility
- v2 completely removes TAG
- FakeTLS encryption is used in v2

## Target architecture
- OS family: modern RHEL-family distributions (Rocky Linux 9+, AlmaLinux 9+, CentOS Stream 9+, Oracle Linux 9+)
- Init system: `systemd`
- Package manager: `dnf`
- Firewall integration: `firewalld` (used if active, otherwise skipped)
- SELinux: supported, with context restore for installed `mtg` binary

## Installation
**This script uses the latest release of [9seconds/mtg](https://github.com/9seconds/mtg) by default**
~~~shell
bash <(curl -Ls https://raw.githubusercontent.com/samotnij/MTProxy/main/mtproxy.sh)
~~~
**Due to the CDN cache, jsdelivr link may not be the latest.**
~~~shell
bash <(curl -Ls https://cdn.jsdelivr.net/gh/samotnij/MTProxy/mtproxy.sh)
~~~

## Manual tuning profiles (RHEL-family)
Choose a profile based on expected concurrent connections.

### Profile A: ~1k connections
If you expect up to about 1,000 concurrent connections, use this lighter profile.

#### 1) Kernel and network parameters
~~~shell
sudo tee /etc/sysctl.d/99-mtproxy-tuning.conf > /dev/null <<'EOF'
# Accept queue / bursts
net.core.somaxconn = 4096
net.ipv4.tcp_max_syn_backlog = 8192

# Ephemeral ports range
net.ipv4.ip_local_port_range = 10240 65535

# FD ceiling for the whole system
fs.file-max = 500000
EOF

sudo sysctl --system
~~~

#### 2) Service open files limit
~~~shell
sudo mkdir -p /etc/systemd/system/mtg.service.d

sudo tee /etc/systemd/system/mtg.service.d/override.conf > /dev/null <<'EOF'
[Service]
LimitNOFILE=65535
EOF

sudo systemctl daemon-reload
sudo systemctl restart mtg
~~~

#### 3) Optional user limits
~~~shell
sudo tee /etc/security/limits.d/99-mtproxy.conf > /dev/null <<'EOF'
* soft nofile 65535
* hard nofile 65535
root soft nofile 65535
root hard nofile 65535
EOF
~~~

#### 4) Quick verification
~~~shell
sysctl net.core.somaxconn net.ipv4.tcp_max_syn_backlog net.ipv4.ip_local_port_range fs.file-max
systemctl show mtg -p LimitNOFILE
~~~

### Profile B: ~10k connections
If you expect up to about 10,000 concurrent connections, apply the baseline tuning below manually.

#### 1) Kernel and network parameters
~~~shell
sudo tee /etc/sysctl.d/99-mtproxy-tuning.conf > /dev/null <<'EOF'
# Accept queue / bursts
net.core.somaxconn = 8192
net.ipv4.tcp_max_syn_backlog = 16384

# Ephemeral ports range
net.ipv4.ip_local_port_range = 10240 65535

# FD ceiling for the whole system
fs.file-max = 1000000

# Conntrack (if nf_conntrack is enabled)
net.netfilter.nf_conntrack_max = 262144
EOF

sudo sysctl --system
~~~

#### 2) Service open files limit (important)
~~~shell
sudo mkdir -p /etc/systemd/system/mtg.service.d

sudo tee /etc/systemd/system/mtg.service.d/override.conf > /dev/null <<'EOF'
[Service]
LimitNOFILE=262144
EOF

sudo systemctl daemon-reload
sudo systemctl restart mtg
~~~

#### 3) Optional user limits
~~~shell
sudo tee /etc/security/limits.d/99-mtproxy.conf > /dev/null <<'EOF'
* soft nofile 262144
* hard nofile 262144
root soft nofile 262144
root hard nofile 262144
EOF
~~~

#### 4) Quick verification
~~~shell
sysctl net.core.somaxconn net.ipv4.tcp_max_syn_backlog net.ipv4.ip_local_port_range fs.file-max net.netfilter.nf_conntrack_max
systemctl show mtg -p LimitNOFILE
~~~

## Open Source Used
[9seconds/mtg](https://github.com/9seconds/mtg)

## Author

**MTProxy** © [Vincent Young](https://github.com/missuo), Released under the [MIT](./LICENSE) License.<br>

Optimized by `samotnij` for modern RHEL-family target architecture.
