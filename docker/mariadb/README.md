Quick start for MariaDB (development)

1. Copy .env and set passwords:

   cp .env.example .env
   # edit .env: set MARIADB_ROOT_PASSWORD and other values

2. Start the service:

   cd /home/oaq/linux-tools/docker/mariadb
   docker compose up -d

3. Check status and logs:

   docker compose ps
   docker compose logs -f mariadb

4. Validate (example):

   # from host (requires mysql client)
   mysql -h 127.0.0.1 -P 3306 -u root -p
   # then enter MARIADB_ROOT_PASSWORD from .env

5. Data persistence:

   Data stored in the named volume `mariadb_data`.
   To back up:

   docker run --rm --volumes-from mariadb -v $(pwd):/backup ubuntu \
     bash -c "tar czf /backup/mariadb-data-$(date +%F).tgz /var/lib/mysql"

Notes:
- The compose file supports an optional custom my.cnf mount at ./my.cnf -> /etc/mysql/conf.d/my.cnf (uncomment in compose to enable).
- For production, pin the image to a specific tag, enable backups, and restrict network access.
