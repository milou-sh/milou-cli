# 🚨 URGENT SECURITY PATCH

## Critical Security Issue

**IMMEDIATE ACTION REQUIRED**: The current `.env` file contains a hardcoded GitHub Personal Access Token that needs to be immediately revoked and secured.

## Exposed Token

```
GITHUB_TOKEN=ghp_EXAMPLE_TOKEN_REDACTED_FOR_SECURITY
```

## Immediate Actions Required

### 1. Revoke the Exposed Token (URGENT - Do this NOW)

1. Go to GitHub → Settings → Developer settings → Personal access tokens
2. Find the token `ghp_EXAMPLE_TOKEN_REDACTED_FOR_SECURITY`
3. **Delete/Revoke it immediately**

### 2. Remove Token from Configuration

```bash
# Remove the hardcoded token from .env
sed -i '/^GITHUB_TOKEN=/d' .env
```

### 3. Generate New Token

1. Go to GitHub → Settings → Developer settings → Personal access tokens → Tokens (classic)
2. Click "Generate new token (classic)"
3. Set expiration to a reasonable time (e.g., 90 days)
4. Select scopes:
   - `read:packages` (required for pulling container images)
   - `read:org` (if using organization packages)

### 4. Secure Token Storage

Instead of storing in `.env`, use environment variables:

```bash
# Option 1: Environment variable (temporary)
export GITHUB_TOKEN="your_new_token_here"
./milou.sh setup --token "$GITHUB_TOKEN"

# Option 2: Pass directly (recommended)
./milou.sh setup --token "your_new_token_here"
```

## Quick Security Patches

### Patch 1: Remove Token from History

```bash
# Clean git history if the token was committed
git filter-branch --force --index-filter \
'git rm --cached --ignore-unmatch .env' \
--prune-empty --tag-name-filter cat -- --all

# Force push to update remote (WARNING: This rewrites history)
git push origin --force --all
```

### Patch 2: Add .env to .gitignore

```bash
# Ensure .env is never committed again
echo ".env" >> .gitignore
echo "*.env" >> .gitignore
echo "**/.env" >> .gitignore
git add .gitignore
git commit -m "Add .env to gitignore for security"
```

### Patch 3: Create Secure Environment Template

Create `.env.example` without sensitive data:

```bash
cat > .env.example << 'EOF'
# Milou Application Environment Configuration
# Copy this file to .env and fill in your values
# ========================================

# Server Configuration
SERVER_NAME=localhost
CUSTOMER_DOMAIN_NAME=localhost
SSL_PORT=443
SSL_CERT_PATH=./ssl
CORS_ORIGIN=https://localhost

# Database Configuration (will be auto-generated)
DB_HOST=db
DB_PORT=5432
DB_USER=your_db_user_here
DB_PASSWORD=your_db_password_here
DB_NAME=milou

# Redis Configuration (will be auto-generated)
REDIS_HOST=redis
REDIS_PORT=6379
REDIS_PASSWORD=your_redis_password_here

# RabbitMQ Configuration
RABBITMQ_URL=amqp://guest:guest@rabbitmq:5672
RABBITMQ_USER=guest
RABBITMQ_PASSWORD=guest

# Security (will be auto-generated)
SESSION_SECRET=your_session_secret_here
ENCRYPTION_KEY=your_encryption_key_here

# Application
API_PORT=9999
NODE_ENV=production

# NOTE: GitHub token should NOT be stored here
# Pass it as command line argument: --token YOUR_TOKEN
EOF
```

## Updated Usage

### Secure Setup Command

```bash
# Generate new GitHub token first, then use:
./milou.sh setup --token "ghp_your_new_secure_token" --domain "your-domain.com"

# For localhost development:
./milou.sh setup --token "ghp_your_new_secure_token"
```

### Environment Variable Method

```bash
# Set token as environment variable
export MILOU_GITHUB_TOKEN="ghp_your_new_secure_token"

# Modify setup to use environment variable
./milou.sh setup --domain "your-domain.com"
```

## Additional Security Measures

### 1. Scan for Other Exposed Secrets

```bash
# Search for potential secrets in all files
grep -r -i "token\|password\|secret\|key" . --exclude-dir=.git
```

### 2. Set Proper File Permissions

```bash
# Secure configuration files
chmod 600 .env 2>/dev/null || true
chmod 700 ~/.milou 2>/dev/null || true
```

### 3. Add Security Headers

Add this to your nginx configuration or environment:

```bash
# Security headers
SECURITY_HEADERS="
    add_header X-Frame-Options DENY;
    add_header X-Content-Type-Options nosniff;
    add_header X-XSS-Protection '1; mode=block';
    add_header Strict-Transport-Security 'max-age=31536000; includeSubDomains';
"
```

## Prevention Measures

### 1. Pre-commit Hook

Create `.git/hooks/pre-commit`:

```bash
#!/bin/bash
# Check for potential secrets before commit

secrets_patterns=(
    "ghp_[a-zA-Z0-9]{36}"
    "gho_[a-zA-Z0-9]{36}"
    "ghu_[a-zA-Z0-9]{36}"
    "ghs_[a-zA-Z0-9]{36}"
    "ghr_[a-zA-Z0-9]{36}"
    "password\s*=\s*.+"
    "secret\s*=\s*.+"
)

for pattern in "${secrets_patterns[@]}"; do
    if git diff --cached --name-only | xargs grep -l "$pattern" 2>/dev/null; then
        echo "❌ Potential secret detected! Commit rejected."
        echo "Pattern: $pattern"
        exit 1
    fi
done
```

### 2. Add .gitignore Rules

```gitignore
# Environment files
.env
.env.local
.env.production
.env.staging
*.env

# Secrets and credentials
**/secrets/
**/*secret*
**/*token*
**/*key*
.credentials

# Backup files
*.backup
*.bak
```

## Long-term Security Recommendations

1. **Implement proper secrets management** (HashiCorp Vault, AWS Secrets Manager)
2. **Use short-lived tokens** with automatic rotation
3. **Implement least-privilege access** for GitHub tokens
4. **Add security scanning** to CI/CD pipeline
5. **Regular security audits** of configuration files
6. **Implement token encryption** for storage
7. **Add audit logging** for token usage

## Verification Steps

After applying patches, verify security:

```bash
# 1. Verify no tokens in files
grep -r "ghp_" . --exclude-dir=.git || echo "✅ No GitHub tokens found"

# 2. Verify .env is not tracked
git status | grep ".env" && echo "❌ .env is still tracked" || echo "✅ .env not tracked"

# 3. Verify gitignore works
echo "test" > .env && git status | grep ".env" && echo "❌ .env not ignored" || echo "✅ .env properly ignored"
rm .env

# 4. Test secure setup
./milou.sh setup --token "your_new_token" --domain localhost
```

## Emergency Contacts

If you suspect the token has been compromised:

1. **Immediately revoke the token** on GitHub
2. **Check GitHub audit logs** for unauthorized access
3. **Rotate all other credentials** as a precaution
4. **Monitor container registry** for unauthorized access
5. **Review system logs** for suspicious activity

---

**This is a critical security issue that requires immediate attention. Do not delay in revoking the exposed token and implementing these security measures.** 