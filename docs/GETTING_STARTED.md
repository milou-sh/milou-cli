# Getting Started with Milou

## Installation

### Quick Install
```bash
curl -fsSL https://raw.githubusercontent.com/milou-sh/milou-cli/main/install.sh | bash
```

### Manual Install
```bash
git clone https://github.com/milou-sh/milou-cli.git
cd milou-cli
chmod +x milou.sh
./milou.sh setup
```

## First Setup

1. Run setup:
```bash
milou setup
```

2. Answer 3 questions:
   - **Domain**: `localhost` (or your domain)
   - **Email**: Your email address
   - **SSL**: Choose `generate` for self-signed certificates

3. Wait for services to start (~2 minutes)

4. Open your browser to `https://localhost`

## Daily Commands

```bash
milou status    # Check if everything is running
milou start     # Start all services
milou stop      # Stop all services  
milou restart   # Restart services
milou logs      # View service logs
milou backup    # Create backup
```

## Configuration

All settings are in `.env` file:

```bash
# Basic settings
DOMAIN=localhost
ADMIN_EMAIL=admin@localhost
SSL_MODE=generate

# Database (auto-generated)
DB_USER=milou_user
DB_PASSWORD=randomly_generated_password
```

## Backup & Restore

### Create Backup
```bash
milou backup
# Creates: backups/milou_backup_YYYYMMDD_HHMMSS.tar.gz
```

### List Backups
```bash
milou backup --list
```

### Restore Backup
```bash
milou restore backups/milou_backup_20241201_143022.tar.gz
```

## Troubleshooting

### Services won't start
```bash
milou status     # Check service status
milou logs       # Check for errors
```

### Can't access website
1. Check if services are running: `milou status`
2. Check SSL certificates: `ls ssl/`
3. Try restarting: `milou restart`

### Reset everything
```bash
milou stop
rm -rf ssl/ .env
milou setup
```

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