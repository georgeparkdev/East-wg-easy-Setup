# Easy wg-easy Setup

Welcome to the Easy wg-easy setup guide! This repository provides a straightforward way to install and configure [wg-easy](https://github.com/wg-easy/wg-easy) on your server.

## Overview

This repository includes a setup script and configuration file to simplify the installation of `wg-easy`, a web-based management interface for WireGuard VPN. The setup script automates the installation of Docker, Docker Compose, and `wg-easy`, including the creation of necessary configuration files and SSL certificates.

## Requirements

Before you start, ensure you have the following:

- **Domain Name**: You need to set up a domain name and point its A-record to your server's IP address.
- **Ubuntu System**: This script is designed for Ubuntu-based systems.
- **File Transfer**: Transfer the configuration file and setup script to your server. You can use `scp` for this purpose:
```bash
scp wg-easy-config.env setup-wg-easy.sh root@<your-server-ip>:~/
```

## Configuration

1. **Edit the Configuration File**

Open `wg-easy-config.env` and set the following variables:
- `HOST`: Your domain or server IP where `wg-easy` will be accessible.
- `WG_ADMIN_PASSWORD`: The admin password for `wg-easy`.
- `ENABLE_PROMETHEUS_METRICS`: Set to `true` to enable Prometheus metrics.
- **Cron Job Configuration**:
    - `ENABLE_REBOOT_CRON`: Enable automatic server reboot (true/false).
    - `REBOOT_TIME`: Time in UTC for reboot (HH:MM format).
    - `ENABLE_UPDATE_CRON`: Enable automatic `wg-easy` update (true/false).
    - `UPDATE_DAY_OF_MONTH`: Day of the month for updates (1-31).
    - `UPDATE_TIME`: Time in UTC for updates (HH:MM format).

2. **Make the Script Executable**
```bash
chmod +x setup-wg-easy.sh
```

## Installation

1. **Run the Setup Script**
Execute the setup script as root:
```bash
sudo ./setup-wg-easy.sh
```

This will:
- Install Docker and Docker Compose.
- Generate a password hash.
- Create the `docker-compose.yml` and NGINX configuration.
- Start Docker containers and set up SSL certificates.
- Configure the firewall and cron jobs.
- Clean up sensitive information.

## Usage

Once the setup is complete, you can access `wg-easy` via your domain. Log in using the admin password you specified in the configuration file.

## Troubleshooting

- **Docker Installation Issues**: Ensure your server has internet access and the correct Ubuntu version.
- **Configuration Errors**: Check `setup.log` for details on any errors during setup.
- **SSL Issues**: Verify your domain’s DNS settings and ensure ports 80 and 443 are open.

## Contribution

Contributions are welcome! Please fork the repository and submit a pull request with your changes. For more information, check the [contribution guidelines](CONTRIBUTING.md).

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
