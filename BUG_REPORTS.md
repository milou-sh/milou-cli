# Milou Bug Reports and Fixes

## Fixed Issues

### 1. Docker Image Tag Mismatch (FIXED)

**Issue**: The setup script was generating `.env` files with Docker image tags prefixed with "v" (e.g., `v1.0.0`) but the actual Docker images in GitHub Container Registry use tags without the "v" prefix (e.g., `1.0.0`).

**Symptom**: 
```
Error response from daemon: manifest unknown
```

**Root Cause**: 
- `src/_config.sh` line 225 and 278: `echo "v1.0.0"`
- `src/_setup.sh` line 1109: `version_tag="v1.0.0"`

**Fix Applied**:
- Updated all fallback version defaults from `"v1.0.0"` to `"1.0.0"`
- Updated help text examples to use correct format
- Files modified:
  - `src/_config.sh`
  - `src/_setup.sh` 
  - `src/_update.sh`

**Status**: ✅ FIXED

---

### 2. Engine RabbitMQ Authentication Bug (WORKAROUND APPLIED)

**Issue**: The engine service fails to connect to RabbitMQ despite correct environment variables being set, always attempting to use 'guest:guest' credentials.

**Symptom**:
```
ConnectionClosedByBroker: (403) 'ACCESS_REFUSED - Login was refused using authentication mechanism PLAIN. For details see the broker logfile.'
```

**Root Cause**: 
The engine code in `engine/src/main.py` only extracts hostname and port from `RABBITMQ_URL` but ignores the username/password:

```python
# Get RabbitMQ URL from environment
RABBITMQ_URL = os.getenv('RABBITMQ_URL', 'amqp://guest:guest@localhost:5672')

# Parse the URL to get host - BUG: credentials are ignored!
rabbitmq_url = urlparse(RABBITMQ_URL)
rabbitmq_host = rabbitmq_url.hostname
rabbitmq_port = rabbitmq_url.port
```

The `BaseHandler` class and all `pika.ConnectionParameters` calls are missing the `credentials` parameter:

```python
# In base_handler.py - BUG: No credentials passed!
connection = pika.BlockingConnection(
    pika.ConnectionParameters(
        host=self.host,
        port=self.port,
        # Missing: credentials=pika.PlainCredentials(username, password)
        heartbeat=heartbeat_interval,
        # ...
    )
)
```

**Temporary Workaround Applied**:
- Added guest user to RabbitMQ container: `rabbitmqctl add_user guest guest`
- Set administrator permissions: `rabbitmqctl set_user_tags guest administrator`
- Granted full permissions: `rabbitmqctl set_permissions -p / guest ".*" ".*" ".*"`

**Proper Fix Needed**:
1. Modify `engine/src/main.py` to extract credentials from `RABBITMQ_URL`:
```python
rabbitmq_url = urlparse(RABBITMQ_URL)
rabbitmq_host = rabbitmq_url.hostname
rabbitmq_port = rabbitmq_url.port
rabbitmq_username = rabbitmq_url.username or 'guest'
rabbitmq_password = rabbitmq_url.password or 'guest'
```

2. Update `BaseHandler` constructor to accept credentials:
```python
def __init__(self, host='localhost', port='15672', username='guest', password='guest', ...):
    self.credentials = pika.PlainCredentials(username, password)
```

3. Add credentials to all `pika.ConnectionParameters` calls:
```python
pika.ConnectionParameters(
    host=self.host,
    port=self.port,
    credentials=self.credentials,
    # ...
)
```

**Status**: ⚠️ WORKAROUND APPLIED - PROPER FIX NEEDED

---

## Security Note

The current workaround enables the default 'guest' user in RabbitMQ, which is a security risk in production environments. This should be replaced with a proper fix in the engine code as soon as possible.

---

## Testing

After applying fixes:
1. ✅ All Docker images pull correctly with `1.0.0` tags
2. ✅ All services start successfully
3. ✅ RabbitMQ authentication works (via workaround)
4. ✅ Milou application is accessible at https://localhost
5. ✅ All health checks pass

## Recommendations

1. **High Priority**: Fix the engine RabbitMQ authentication bug in the source code
2. **Medium Priority**: Add comprehensive integration tests for setup process
3. **Low Priority**: Improve error messages for Docker image tag mismatches 