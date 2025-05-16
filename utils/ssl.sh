#!/bin/bash

# SSL certificate management utility functions

# Set up SSL certificates
setup_ssl() {
    local ssl_path="$1"
    local domain="$2"
    
    echo "Setting up SSL certificates..."
    
    # Set default SSL path if not provided
    if [ -z "$ssl_path" ]; then
        ssl_path="./ssl"
    fi
    
    # Check if the SSL path exists
    if [ ! -d "$ssl_path" ]; then
        echo "Creating SSL certificate directory: $ssl_path"
        mkdir -p "$ssl_path" || {
            echo "Error: Failed to create SSL certificate directory."
            return 1
        }
    fi
    
    # Check if the domain was provided
    if [ -z "$domain" ]; then
        domain=$(get_config_value "SERVER_NAME")
        if [ -z "$domain" ]; then
            domain="localhost"
        fi
    fi
    
    # Check if certificates already exist
    if [ -f "${ssl_path}/milou.crt" ] && [ -f "${ssl_path}/milou.key" ]; then
        echo "SSL certificates already exist in ${ssl_path}."
        return 0
    fi
    
    # Check if we should generate dummy certificates for development/testing
    if [ "$domain" = "localhost" ] || [ "$ssl_path" = "./dummy-certs" ]; then
        echo "Generating dummy SSL certificates for development/testing..."
        
        # Generate self-signed certificates
        openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
            -keyout "${ssl_path}/milou.key" \
            -out "${ssl_path}/milou.crt" \
            -subj "/CN=${domain}/O=Milou/C=US" || {
            echo "Error: Failed to generate self-signed certificates."
            return 1
        }
        
        echo "Dummy SSL certificates generated successfully."
        
        # Update configuration
        update_config_value "SSL_CERT_PATH" "${ssl_path}"
        
        return 0
    fi
    
    # For production, instruct the user to place their certificates in the right location
    echo "Please place your SSL certificates in the following locations:"
    echo "  - Certificate file: ${ssl_path}/milou.crt"
    echo "  - Private key file: ${ssl_path}/milou.key"
    echo ""
    echo "Once your certificates are in place, Nginx will automatically use them."
    
    # Update configuration
    update_config_value "SSL_CERT_PATH" "${ssl_path}"
    
    return 0
}

# Check SSL certificate expiration
check_ssl_expiration() {
    local ssl_path=$(get_config_value "SSL_CERT_PATH")
    
    if [ -z "$ssl_path" ]; then
        echo "Error: SSL path not configured."
        return 1
    fi
    
    local cert_file="${ssl_path}/milou.crt"
    
    # Check if the certificate file exists
    if [ ! -f "$cert_file" ]; then
        echo "Error: Certificate file not found: $cert_file"
        return 1
    fi
    
    # Get certificate expiration date
    local expiration_date=$(openssl x509 -enddate -noout -in "$cert_file" | cut -d= -f2)
    local expiration_seconds=$(date -d "$expiration_date" +%s)
    local current_seconds=$(date +%s)
    local seconds_remaining=$((expiration_seconds - current_seconds))
    local days_remaining=$((seconds_remaining / 86400))
    
    # Get domain from certificate
    local domain=$(openssl x509 -noout -subject -in "$cert_file" | grep -o "CN=\S*" | cut -d= -f2 | cut -d, -f1)
    
    echo "SSL Certificate Information:"
    echo "  - Domain: $domain"
    echo "  - Expiration Date: $expiration_date"
    echo "  - Days Remaining: $days_remaining"
    
    # Warn if expiration is near
    if [ $days_remaining -lt 30 ]; then
        echo "Warning: Certificate will expire in less than 30 days!"
    fi
    
    return 0
}

# Renew SSL certificate (placeholder for Let's Encrypt integration)
renew_ssl_certificate() {
    local ssl_path=$(get_config_value "SSL_CERT_PATH")
    local domain=$(get_config_value "SERVER_NAME")
    
    if [ -z "$ssl_path" ]; then
        echo "Error: SSL path not configured."
        return 1
    fi
    
    echo "Automatic SSL certificate renewal is not supported in this version."
    echo "To renew your certificates manually:"
    echo "1. Obtain new certificates for your domain"
    echo "2. Place them at:"
    echo "   - ${ssl_path}/milou.crt"
    echo "   - ${ssl_path}/milou.key"
    echo "3. Restart the Nginx service with: ./milou.sh restart"
    
    return 0
} 