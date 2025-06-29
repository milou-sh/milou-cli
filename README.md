# Milou - Simple Docker App Launcher

**Simple, reliable Docker application management**

## 🚀 Quick Start (5 minutes)

```bash
# 1. Install
curl -fsSL https://raw.githubusercontent.com/milou-sh/milou-cli/main/install.sh | bash

```

That's it! 🎉

## 📋 What You Get

- **Web application** running on HTTPS
- **Database** with automatic backups
- **SSL certificates** 
- **Simple management** 

## 🔧 Commands

```bash
milou setup          # Initial setup
milou start          # Start all services  
milou stop           # Stop all services
milou restart        # Restart all services
milou status         # Show status
milou logs [service] # Show logs
milou backup         # Create backup
milou restore <file> # Restore from backup
```

## 📦 Requirements

- **Linux** (Ubuntu, CentOS, Debian, etc.)
- **Docker** 20.10+
- **4GB RAM** minimum
- **10GB disk space**

Missing Docker? Run `milou setup` and it will help you install it.

## 🔒 Security

- HTTPS by default with self-signed certificates
- Auto-generated secure passwords
- All credentials saved to `.env` file (keep it safe!)

## 🆘 Need Help?

```bash
milou --help          # Show all commands
milou status          # Check if everything is running
milou logs            # Check for errors
```

**Having issues?** 
- Check `milou status` for service health
- Run `milou logs` to see what's happening
- All data is in the current directory - easy to backup/move

## 🔧 Advanced Setup

### Custom Domain
```bash
milou setup
# When prompted for domain, enter: yourdomain.com
```

### Production SSL
1. Place your SSL certificates in `ssl/` directory:
   - `ssl/certificate.crt` 
   - `ssl/private.key`
2. Run `milou restart`

### Custom Docker Configuration

You can customize service configurations without modifying the core files by creating a `docker-compose.override.yml` file in the `static/` directory:

```yaml
# static/docker-compose.override.yml
services:
  nginx:
    volumes:
      # Custom SSL certificate path
      - ${CUSTOM_SSL_PATH:-/path/to/your/ssl}:/etc/ssl:ro
      - nginx_logs:/var/log/nginx:rw
      - nginx_cache:/var/cache/nginx:rw
```

This file is automatically included and:
- Preserved during updates
- Allows custom volumes, environment variables, and resource limits
- Won't be overwritten by CLI updates

### Backup & Restore
```bash
# Create backup
milou backup

# List backups  
milou backup --list

# Restore from backup
milou restore backups/milou_backup_20241201_143022.tar.gz
```

## 📁 What's Inside

```
milou-cli/
├── .env              # Your configuration (keep safe!)
├── ssl/              # SSL certificates
├── backups/          # Automatic backups
├── static/           # Docker compose files
└── milou.sh          # Main script
```

## 🛠️ Development

```bash
# Clone the repository
git clone https://github.com/milou-sh/milou-cli.git
cd milou-cli

# Run setup
./milou.sh setup

# Start developing
./milou.sh logs    # Watch logs
./milou.sh restart # Restart after changes

# Test commit for user attribution
```

## 📄 License

MIT License - see [LICENSE](LICENSE) file.

## 🤝 Contributing

1. Fork this repository
2. Create a feature branch
3. Make your changes  
4. Submit a pull request

Keep it simple and focused on user experience!

---

**Questions?** Open an issue on GitHub.  
**Ready to get started?** Just run the install command above! 🚀 