# ZN - MOTD (Message of the Day)
## Overview
A customizable Message of the Day (MOTD) banner for Linux systems. It provides a quick glance at essential system information, helping administrators and users quickly assess the state of their system. 

![motd](/assets/preview.png)


## Features and Usage
`zn-motd` provides various system monitoring utilities. By default, it displays the following information:
- **System Info**: Shows OS name, version, kernel, uptime, IP addresses.
- **Resources Usage**: Displays CPU usage, memory usage, and disk usage.
- **Services**: Lists the status of key services.
- **Active Logins**: Details on current active user sessions.
- **Reboot Required**: Indicates if a system restart is required.

### Usage:
Run `zn-motd` with the following syntax:
```
motd [OPTION]
```
| Option             | Description                             |
|--------------------|-----------------------------------------|
| `--help, -h`       | Show help message.                      |
| `--version, -V`    | Display the version of `zn-motd`.       |
| `--update, -U`     | Update `zn-motd` to the latest version. |
| `--info, -I`       | Display system information.             |
| `--resources, -R`  | Display resource usage.                 |
| `--service, -S`    | Display services.                       |
| `--who, -W`        | Display active logins.                  |
| `--reboot, -B`     | Display reboot required.                |

If no option is provided, all MOTD sections will be displayed as a single banner.

## Installation
To install zn-motd, use the following command:
```bash
curl -s https://raw.githubusercontent.com/zharfanug/zn-motd/latest/install.sh | sh
```
### What Happens During Installation?
- Creates the MOTD script at `/etc/profile.d/zn-motd.sh`.
- Links the script to `/bin/motd`, allowing you to run it directly using the motd command.
- Installs dependencies if available.

### Dependencies
- **sudo/root privileges**: Required for installation and updates.
- **systemd**: Required for displaying service status. If the system doesn't use `systemd`, service status section will be skipped without breaking other features.

## Customizing Services

You can configure which services are displayed in the MOTD by editing the top of the `/etc/profile.d/zn-motd.sh` file.
For multiple entries, each service must be separated by pipe `|` with no spaces. 

For example:
```sh
#!/bin/sh

# Service config
excluded_services="mysqld" 
included_services="mariadb|vmtoolsd"
```

`excluded_services`: Exclude specific services from being displayed in the MOTD. 

`included_services`: Manually include specific services, if the service is being excluded somehow.


---

This project is inspired by [yboetz/motd](https://github.com/yboetz/motd).