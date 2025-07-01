# Reverse Proxy Setup for Milou

Milou now supports running behind reverse proxies like Traefik, Nginx Proxy Manager, Caddy, and custom nginx setups. The CLI automatically detects port conflicts and gracefully handles reverse proxy scenarios.

## What Changed

### Automatic Port Conflict Detection
- **Port Conflict Handling**: When ports 80/443 are already in use (common with reverse proxies), Milou automatically disables the nginx service and continues setup
- **Override File Support**: The CLI now automatically detects and uses `docker-compose.override.yml` files
- **Graceful Fallback**: Instead of failing on nginx startup, the system continues without nginx when port conflicts are detected

### Enhanced Service Startup
- **Smart Detection**: Automatically detects reverse proxy setups when port conflicts occur
- **Override Integration**: Respects docker-compose override files during setup
- **Service Scaling**: Can automatically scale nginx to 0 replicas when conflicts are detected

## Quick Setup Guide

### 1. Create Override File
Create a `docker-compose.override.yml` file in your milou-cli directory:

```yaml
version: '3.8'

services:
  # Disable nginx for reverse proxy
  nginx:
    deploy:
      replicas: 0

  # Configure frontend for your reverse proxy
  frontend:
    labels:
      # Your reverse proxy labels here
      - "traefik.enable=true"
      - "traefik.http.routers.milou.rule=Host(`your-domain.com`)"
      # ... more labels
```

### 2. Run Setup
```bash
./milou.sh setup --token your_github_token
```

The CLI will automatically:
- Detect your override file
- Handle port conflicts gracefully
- Skip nginx when conflicts are detected
- Continue with setup successfully

## Example Configurations

See `docs/reverse-proxy-example.yml` for complete examples for:
- Traefik (with automatic HTTPS)
- Nginx Proxy Manager
- Caddy
- Custom nginx reverse proxy

## Traefik Example

```yaml
version: '3.8'

services:
  nginx:
    deploy:
      replicas: 0

  frontend:
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.milou-frontend.rule=Host(`your-domain.com`)"
      - "traefik.http.routers.milou-frontend.entrypoints=websecure"
      - "traefik.http.routers.milou-frontend.tls=true"
      - "traefik.http.routers.milou-frontend.tls.certresolver=letsencrypt"
      - "traefik.http.services.milou-frontend.loadbalancer.server.port=3000"
    networks:
      - default
      - traefik

networks:
  traefik:
    external: true
```

## Troubleshooting

### Common Issues

1. **Port Still Conflicts**: Make sure your override file properly disables nginx
   ```yaml
   nginx:
     deploy:
       replicas: 0
   ```

2. **Services Not Accessible**: Ensure your reverse proxy routes to the correct ports:
   - Frontend: port 3000
   - Backend API: port 8000

3. **Override File Not Detected**: Ensure the file is named exactly `docker-compose.override.yml` and is in the milou-cli root directory

### Manual Override
If automatic detection doesn't work, you can manually start services:

```bash
# Start with override file
docker compose -f docker-compose.yml -f docker-compose.override.yml up -d

# Or scale nginx to 0 manually
docker compose up -d --scale nginx=0
```

## Benefits

- **Zero Configuration**: Works out of the box with most reverse proxy setups
- **Automatic Detection**: No need to modify the main CLI code
- **Flexible**: Supports any reverse proxy through override files
- **Safe Fallback**: Gracefully handles port conflicts without failing setup
- **Standard Docker**: Uses standard docker-compose override functionality

## Technical Details

The changes were made to:
1. `src/_setup.sh` - Enhanced service startup with override file detection
2. `src/_docker.sh` - Added port conflict detection and nginx fallback logic

These minimal changes ensure backward compatibility while adding robust reverse proxy support. 