Quick start for redis-stack (development)

1. Copy the example env and set a strong password:

   cp .env.example .env
   # edit .env: set REDIS_PASSWORD

2. Start the container in the background:

   docker compose up -d

3. Check service status / logs:

   docker compose ps
   docker compose logs -f redis

4. Validate Redis responds (example):

   # from host, using redis-cli (may need to install redis-tools)
   redis-cli -a "$REDIS_PASSWORD" PING

5. RedisInsight / UI is available on http://localhost:8001

Notes:
- Data is stored in the named volume `redis_data`.
- For production, consider setting resource limits, backups and bind-mounting a config file.
