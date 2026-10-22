# github.com/crimsonvspurple/docker-osticket

Fork of [tiredofit/docker-osticket](https://github.com/tiredofit/docker-osticket), which was archived on 7 October 2025.

* * *
## About

This builds a Docker image for [osTicket](https://www.osticket.com), an open source helpdesk.

* osTicket v1.18.4
* PHP 8.4.27 (the newest PHP release osTicket v1.18.4 supports; PHP 8.5 is not supported upstream)
* Debian Bookworm, Nginx, and PHP-FPM
* Installs and configures itself on first start

## Maintainer

- [CvP](https://github.com/crimsonvspurple)
- Original image by [Dave Conroy](https://github.com/tiredofit)

## Table of Contents


- [About](#about)
- [Maintainer](#maintainer)
- [Table of Contents](#table-of-contents)
- [Prerequisites and Assumptions](#prerequisites-and-assumptions)
- [Installation](#installation)
  - [Build from Source](#build-from-source)
  - [Prebuilt Images](#prebuilt-images)
- [Configuration](#configuration)
  - [Quick Start](#quick-start)
  - [Persistent Storage](#persistent-storage)
  - [Environment Variables](#environment-variables)
    - [Base Images used](#base-images-used)
  - [Networking](#networking)
- [Maintenance](#maintenance)
  - [Shell Access](#shell-access)
- [Support](#support)
  - [Usage](#usage)
  - [Bugfixes](#bugfixes)
  - [Feature Requests](#feature-requests)
  - [Updates](#updates)
- [License](#license)
- [References](#references)

## Prerequisites and Assumptions
*  Assumes you are using some sort of SSL terminating reverse proxy such as:
   *  [Traefik](https://github.com/tiredofit/docker-traefik)
   *  [Nginx](https://github.com/jc21/nginx-proxy-manager)
   *  [Caddy](https://github.com/caddyserver/caddy)
*  Requires access to a MySQL/MariaDB Server

## Installation

### Build from Source
Clone this repository and build the image with `docker build -t (imagename) .`

### Prebuilt Images

This fork does not publish a prebuilt image. Build it from this repository. The image tag in [examples/docker-compose.yml](examples/docker-compose.yml) is `docker-osticket:1.18.4`.

## Configuration

### Quick Start

- The quickest way to get started is using [docker-compose](https://docs.docker.com/compose/). See the examples folder for a working [docker-compose.yml](examples/docker-compose.yml) that can be modified for development or production use.

- Set various [environment variables](#environment-variables) to understand the capabilities of this image.
- Map [persistent storage](#data-volumes) for access to configuration and data files for backup.
- Make [networking ports](#networking) available for public access if necessary

**The first boot can take from 2 minutes - 5 minutes depending on your CPU to setup the proper schemas.**

- Login to the web server and enter in your admin email address, admin password and start configuring the system!

### Persistent Storage
The following directories are used for configuration and can be mapped for persistent storage.

| Directory       | Description                                                                                 |
| --------------- | ------------------------------------------------------------------------------------------- |
| `/www/osticket` | (Not needed as we want to keep base clean, move to a custom/assets approach) Root Directory |
| `/www/logs`     | Nginx and php-fpm logfiles                                                                  |

### Environment Variables

#### Base Images used

The image is `php:8.4.27-fpm-bookworm` plus Nginx from Debian Bookworm. Outgoing mail uses `msmtp`. osTicket v1.18.4 supports PHP 8.2 through 8.4 and recommends 8.4, so this image stays on the latest 8.4 patch rather than PHP 8.5.

PHP's IMAP extension was removed in PHP 8.4. Mail fetching uses osTicket's laminas-mail stack, which needs the ctype extension shipped with PHP.


| Parameter         | Description                                                                 | default                 |
| ----------------- | --------------------------------------------------------------------------- | ----------------------- |
| `INSTALL_SECRET`  | A Large and Random Installation String (Auto Generates on Install if empty) |                         |
| `INSTALL_EMAIL`   | Installer Email (Use different email then ADMIN_EMAIL)                      | `helpdesk@example.com`  |
| `INSTALL_NAME`    | Site Name                                                                   | `My Helpdesk`           |
| `ADMIN_FIRSTNAME` | First name of Admin User                                                    |                         |
| `ADMIN_LASTNAME`  | Last name of Admin User                                                     |                         |
| `ADMIN_EMAIL`     | Admin Email address (Make sure it is different than INSTALL_EMAIL)          |                         |
| `ADMIN_USER`      | Admin Username. At least 5 characters                                       |                         |
| `ADMIN_PASS`      | Admin Password                                                              |                         |
| `CRON_INTERVAL`   | Amount of time in Minutes to Check Incoming Mail                            | `10`                    |
| `DB_HOST`         | Host or container name of MariaDB Server e.g. `osticket-db`                 |                         |
| `DB_PORT`         | MariaDB Port                                                                | `3306`                  |
| `DB_NAME`         | MariaDB Database name e.g. `osticket`                                       |                         |
| `DB_USER`         | MariaDB Username for above Database e.g. `osticket`                         |                         |
| `DB_PASS`         | MariaDB Password for above Database e.g. `password`                         |                         |
| `DB_PREFIX`       | Prefix for Tables                                                           | `ost_`                  |
| `SMTP_HOST`       | SMTP Host                                                                   | `postfix`               |
| `SMTP_PORT`       | SMTP Host Port                                                              | `25`                    |
| `SMTP_FROM`       | SMTP From Address                                                           | `osticket@hostname.com` |
| `SMTP_TLS`        | Should TLS be used (`0`=no `1`=yes)                                         | `1`                     |
| `SMTP_USER`       | SMTP Authentication user                                                    |                         |
| `SMTP_PASS`       | SMTP Authentication password                                                |                         |

### Networking

The following ports are exposed.

| Port | Description |
| ---- | ----------- |
| `80` | HTTP        |

* * *
## Maintenance

### Shell Access

For debugging and maintenance purposes you may want access the containers shell.

``bash
docker exec -it (whatever your container name is) bash
``
## Support

This fork tracks current osTicket and PHP releases. Issues for this image belong on this repository. The original project is archived.

## License
MIT. See [LICENSE](LICENSE) for more details.

## References

* https://osticket.com

