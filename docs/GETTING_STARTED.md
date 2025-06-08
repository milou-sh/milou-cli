# Getting Started with Milou CLI

This guide provides a quick overview of how to install and use the Milou CLI. For a more detailed guide, please refer to the main documentation.

## Quick Installation

You can install the Milou CLI with a single command:

```bash
curl -fsSL https://raw.githubusercontent.com/milou-sh/milou-cli/main/install.sh | bash
```

For a system-wide installation, it is recommended to run this command with `sudo`.

## First-Time Setup

After installation, run the setup wizard:

```bash
milou setup
```

The interactive wizard will guide you through the following steps:

1.  **System Analysis:** The CLI checks your system for dependencies like Docker.
2.  **Domain Configuration:** You'll be asked to provide a domain name (e.g., `localhost` or `milou.yourcompany.com`).
3.  **Admin Email:** Provide an email for SSL certificates and notifications.
4.  **SSL Mode:** Choose between generating self-signed certificates, using your own, or no SSL.
5.  **Version Selection:** Select the version of Milou to install.
6.  **GitHub Authentication:** Provide a GitHub Personal Access Token with `read:packages` scope to pull the required Docker images.
7.  **Deployment:** The CLI will pull the images and start all the services.
8.  **Completion:** Your admin credentials will be displayed.

## Common Commands

Here are some of the most common commands you'll use:

```bash
milou status          # Check the status of all services
milou start           # Start all services
milou stop            # Stop all services
milou restart         # Restart all services
milou logs [service]  # View service logs
milou update          # Update Milou to the latest version
milou backup          # Create a backup of your data
milou restore <file>  # Restore from a backup
milou help            # Show contextual help
```

## Configuration

Your instance's configuration is stored in the `.env` file in the installation directory. You can manually edit this file to change settings, but it's recommended to use the CLI commands when possible.

## Troubleshooting

If you encounter any issues, here are a few things to try:

-   **Check the logs:** `milou logs` or `milou logs <service_name>`
-   **Check the status:** `milou status` will give you a good overview of the system state.
-   **Restart the services:** `milou restart` can sometimes resolve issues.
-   **Run the setup again:** `milou setup` can be used to re-configure or repair an existing installation.

For more detailed troubleshooting, please refer to the main documentation.

## File Structure

```
milou-cli/
├── .env              # Your configuration
├── ssl/              # SSL certificates  
├── backups/          # Your backups
├── static/           # Docker config
└── milou.sh          # Main script
```

## Production Deployment

### Custom Domain
1. Point your domain to your server
2. Run `milou setup` and enter your domain
3. The system will generate SSL certificates

### Real SSL Certificates
1. Get SSL certificates from your provider
2. Copy to `ssl/certificate.crt` and `ssl/private.key`
3. Run `milou restart`

### Security
- Keep `.env` file secure (contains passwords)
- Regular backups: `milou backup`
- Monitor with: `milou logs`

## Need Help?

1. **Check status**: `milou status`
2. **Check logs**: `milou logs`
3. **Reset setup**: Remove `.env` and run `milou setup`
4. **Open an issue**: [GitHub Issues](https://github.com/milou-sh/milou-cli/issues)

That's it! Milou is designed to be simple and just work. 🚀 