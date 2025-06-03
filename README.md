# PostgreSQL with Logical Replication and Debezium CDC

This project sets up a Docker environment with PostgreSQL configured for logical replication, and Debezium capturing changes from a test table and publishing them to Kafka.

## Prerequisites

*   **Docker:** Ensure Docker is installed and running on your system. ([Install Docker](https://docs.docker.com/get-docker/))
*   **Docker Compose:** Ensure Docker Compose is installed. (It's usually included with Docker Desktop). ([Install Docker Compose](https://docs.docker.com/compose/install/))
*   **`curl`:** (Optional, for interacting with Kafka Connect API via command line)
*   **Kafka client tools:** (Optional, for consuming messages directly from Kafka topics, e.g., `kafkacat` or standard Kafka CLI tools)

## Directory Structure

The project should have the following directory structure:

```
.
├── docker-compose.yml
├── init.sql
├── postgres-config/
│   ├── pg_hba.conf
│   └── postgresql.conf
├── debezium-connector-config/
│   └── pg-connector.json
└── README.md
```

*   `docker-compose.yml`: Defines the Docker services (PostgreSQL `15-alpine`, Debezium Zookeeper `2.6`, Kafka `2.6`, and Connect `2.6`).
*   `init.sql`: SQL script to initialize the PostgreSQL database, create users, schema, table, and publication.
*   `postgres-config/`: Contains custom PostgreSQL configuration files.
    *   `postgresql.conf`: Main PostgreSQL configuration, enabling logical replication (`wal_level = logical`).
    *   `pg_hba.conf`: PostgreSQL host-based authentication configuration.
*   `debezium-connector-config/`: Contains the Debezium connector configuration.
    *   `pg-connector.json`: JSON configuration for the Debezium PostgreSQL connector.
*   `README.md`: This file.

A `pgdata` directory will be created automatically by Docker Compose to persist PostgreSQL data.

## 1. Starting the Services

Navigate to the root directory of this project in your terminal and run:

```bash
docker-compose up -d
```

This command will:
1.  Pull the necessary Docker images if they are not already present locally.
2.  Create and start the containers for PostgreSQL, Zookeeper, Kafka, and Kafka Connect in detached mode (`-d`).
3.  Mount the configuration files and the initialization script into the PostgreSQL container.
4.  The `init.sql` script will be executed automatically when the PostgreSQL container starts for the first time, setting up the database, users, schema, table, and publication.

To see the logs of all services:
```bash
docker-compose logs -f
```
To see logs for a specific service (e.g., `postgres`):
```bash
docker-compose logs -f postgres
```

## 2. Checking PostgreSQL and Replication

### a. Connect to PostgreSQL

You can connect to the PostgreSQL database using any SQL client (e.g., `psql`, DBeaver, pgAdmin).
The connection details are:
*   **Host:** `localhost`
*   **Port:** `5432`
*   **Database:** `inventory_db`
*   **User:** `postgres_user`
*   **Password:** `postgres_password` (as defined in `docker-compose.yml`)

Using `psql` from your host (if installed):
```bash
psql -h localhost -p 5432 -U postgres_user -d inventory_db
```
You will be prompted for the password.

### b. Verify Table and Schema

Once connected, you can verify that the `inventory` schema and `products` table were created:

```sql
\dn; -- List schemas
-- Expected output should include 'inventory'

\dt inventory.*; -- List tables in the 'inventory' schema
-- Expected output should include 'products'

SELECT * FROM inventory.products; -- Should be empty initially
```

### c. Check PostgreSQL Logs for Replication Activity

Check the PostgreSQL container logs for messages related to logical replication:
```bash
docker-compose logs postgres
```
Look for lines indicating that the `wal_level` is `logical` and that the system is ready to accept connections.

### d. Check Replication Slots (Initially Empty or Debezium's)

Connect to PostgreSQL and run:
```sql
SELECT * FROM pg_replication_slots;
```
Initially, this might be empty. After Debezium connects and creates its slot (named `debezium_slot_inventory` as per `pg-connector.json`), you will see it listed here.

## 3. Registering the Debezium Connector

The Debezium connector configuration is defined in `debezium-connector-config/pg-connector.json`. We need to post this configuration to the Kafka Connect API.

The Kafka Connect service is exposed on port `8083`.

Open a new terminal and run the following `curl` command:

```bash
curl -i -X POST -H "Accept:application/json" -H "Content-Type:application/json" \
localhost:8083/connectors/ -d @debezium-connector-config/pg-connector.json
```

**Expected Output (Success):**
You should receive an HTTP `201 Created` response, along with the JSON configuration of the created connector.

```json
HTTP/1.1 201 Created
Date: ...
Content-Type: application/json
Content-Length: ...
Server: Jetty(...)
...

{
  "name": "inventory-postgres-connector",
  "config": {
    "connector.class": "io.debezium.connector.postgresql.PostgresConnector",
    "tasks.max": "1",
    "database.hostname": "postgres",
    // ... other config values ...
    "name": "inventory-postgres-connector"
  },
  "tasks": [],
  "type": "source"
}
```

### Check Connector Status:

You can check the status of the connector:
```bash
curl -H "Accept:application/json" localhost:8083/connectors/inventory-postgres-connector/status
```
Look for `"connector": {"state": "RUNNING", ...}` and `"tasks": [{"state": "RUNNING", ...}]`.

If there are issues, check the Kafka Connect container logs:
```bash
docker-compose logs -f connect
```

## 4. Verifying Debezium is Working

### a. Insert Data into PostgreSQL

Connect to the PostgreSQL database (as shown in step 2a) and insert some data into the `inventory.products` table:

```sql
INSERT INTO inventory.products (name, description, quantity) VALUES
('Laptop X1', 'High-performance laptop', 10),
('Wireless Mouse M200', 'Ergonomic wireless mouse', 50);

SELECT * FROM inventory.products;
```

### b. Check Kafka Topics and Messages

Debezium will publish change events to Kafka topics. The topic name is typically `database.server.name.schema_name.table_name`.
Based on our `pg-connector.json`, the server name is `inventory_server`, so the topic for the `products` table will be:
`inventory_server.inventory.products`

You can use a Kafka client tool to consume messages from this topic.

**Using `kafkacat` (if installed):**
```bash
kafkacat -b localhost:9092 -t inventory_server.inventory.products -C -J -q
```
*   `-b localhost:9092`: Kafka broker address (note: `kafkacat` runs on host, Kafka is `localhost:9092` from host perspective).
*   `-t inventory_server.inventory.products`: Topic name.
*   `-C`: Consume messages.
*   `-J`: Output messages as JSON.
*   `-q`: Quiet mode (suppress connection logs).

You should see JSON messages representing the `INSERT` operations you performed. Each message will contain a `payload` with fields like `before` (null for inserts), `after` (the new row data), `source` (metadata about the source), `op` (`c` for create/insert), and `ts_ms` (timestamp).

**Using Dockerized Kafka CLI tools (if `kafkacat` is not available):**
First, find the network your Kafka container is on (usually `logical-replication_default` if your project folder is `logical-replication`):
```bash
docker network ls
docker network inspect <your_project_name>_default
```
Then run the Kafka console consumer:
```bash
docker-compose exec kafka /kafka/bin/kafka-console-consumer.sh \
  --bootstrap-server kafka:9092 \
  --topic inventory_server.inventory.products \
  --from-beginning \
  --property print.key=true \
  --property key.separator=" | "
```
This command runs the consumer inside the Kafka container, so `kafka:9092` is the correct address.

### c. Update and Delete Data

Try updating and deleting data in PostgreSQL and observe the corresponding messages in Kafka:

**Update:**
```sql
UPDATE inventory.products SET quantity = 8 WHERE name = 'Laptop X1';
UPDATE inventory.products SET description = 'Super ergonomic wireless mouse' WHERE name = 'Wireless Mouse M200';
```
You should see messages with `op: "u"` (update) in Kafka.

**Delete:**
```sql
DELETE FROM inventory.products WHERE name = 'Wireless Mouse M200';
```
You should see a message with `op: "d"` (delete) and potentially a tombstone message (if `tombstones.on.delete` is true, which it is in our config).

### d. Check Debezium Logs

Check the Kafka Connect container logs for Debezium activity:
```bash
docker-compose logs -f connect
```
You should see logs related to snapshots, streaming changes, and publishing to Kafka.

## 5. Monitoring PostgreSQL Replication Slots

Connect to PostgreSQL and run this query to check the status of replication slots:

```sql
SELECT
    slot_name,
    plugin,
    slot_type,
    datoid,
    database,
    temporary,
    active,
    active_pid,
    xmin,
    catalog_xmin,
    restart_lsn,
    confirmed_flush_lsn,
    pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn)) AS replication_lag_bytes
FROM pg_replication_slots
WHERE slot_name = 'debezium_slot_inventory';
```

*   `slot_name`: Should be `debezium_slot_inventory`.
*   `plugin`: Should be `pgoutput`.
*   `active`: Should be `true` when Debezium is connected and streaming.
*   `restart_lsn`: The Log Sequence Number from which replication can restart.
*   `replication_lag_bytes`: Shows how much WAL data is pending to be consumed by the slot. This should ideally be small. If it grows very large, it means the consumer (Debezium) is not keeping up or is disconnected, and PostgreSQL will retain WAL files, potentially filling up disk space.

## 6. Cleaning Up

To stop and remove all the containers, networks, and volumes created by Docker Compose:

```bash
docker-compose down -v
```
*   `down`: Stops and removes containers, networks.
*   `-v`: Removes named volumes (like `pgdata` where PostgreSQL stores its data). If you omit `-v`, the PostgreSQL data will persist, and the next `docker-compose up` will reuse it.

This ensures a clean state if you want to restart the environment from scratch.

## Troubleshooting Tips

*   **Port Conflicts:** If any of the ports (5432, 2181, 9092, 8083) are already in use on your host machine, `docker-compose up` will fail. You can change the host-side port mapping in `docker-compose.yml` (e.g., change ` "5433:5432"` to map container port 5432 to host port 5433).
*   **Kafka Connect Errors:** Check `docker-compose logs -f connect`. Common issues include:
    *   Inability to connect to PostgreSQL (check `pg_hba.conf`, user credentials, network).
    *   Incorrect connector configuration.
    *   Problems with the replication slot or publication.
*   **PostgreSQL Errors:** Check `docker-compose logs -f postgres`. Common issues:
    *   Incorrect `postgresql.conf` or `pg_hba.conf` settings.
    *   Permissions issues with the `pgdata` volume.
*   **Debezium Slot Issues:** If the replication slot `debezium_slot_inventory` becomes inactive or causes problems, you might need to drop it manually in PostgreSQL (after stopping Debezium/Kafka Connect) and let Debezium recreate it:
    ```sql
    -- First, ensure no process is using the slot. Stop the Kafka Connect service.
    -- Then, in psql:
    SELECT pg_drop_replication_slot('debezium_slot_inventory');
    ```
    Restarting Kafka Connect should then allow Debezium to create a new slot.
*   **Disk Space:** Logical replication slots cause PostgreSQL to retain WAL files until they are consumed. If Debezium stops consuming for a long time, these WAL files can fill up your disk. Monitor the `replication_lag_bytes` and ensure your consumers are active.

## Appendix: Troubleshooting and Setup Summary

This section summarizes key steps and commands used during initial setup and troubleshooting:

### Initial PostgreSQL Connection (pgAdmin)

*   **Problem:** pgAdmin couldn't connect, error "server closed the connection unexpectedly".
*   **Solution Steps:**
    1.  Verified Docker container `postgres_db` was running and healthy: `docker ps`
    2.  Checked `pg_hba.conf` and `postgresql.conf`.
    3.  Enabled detailed logging in `postgresql.conf`:
        ```ini
        log_connections = on
        log_disconnections = on
        log_error_verbosity = verbose
        listen_addresses = '*'
        ```
    4.  Restarted PostgreSQL: `docker restart postgres_db`
    5.  The issue was resolved by **creating a new server connection in pgAdmin** with:
        *   Host: `127.0.0.1`
        *   Port: `5432`
        *   Maintenance Database: `inventory_db`
        *   Username: `postgres_user`
        *   Password: `postgres_password`

### Database Not Initialized (`inventory_db` missing)

*   **Problem:** `inventory_db`, tables, and replication setup were missing. PostgreSQL logs showed "Skipping initialization" because the `pgdata` volume was not empty.
*   **Solution Steps:**
    1.  Stopped services: `docker-compose down`
    2.  Removed the data volume: `rm -rf pgdata` (or `rd /s /q pgdata` on Windows CMD)
    3.  Restarted services: `docker-compose up -d`. This forced `init.sql` to run.
    4.  Verified `init.sql` execution in `docker logs postgres_db`.

### Debezium Connector Not Creating Replication Slot

*   **Problem:** `SELECT * FROM pg_replication_slots;` was empty.
*   **Solution Steps:**
    1.  Checked `kafka_connect` logs (`docker logs kafka_connect`). Found no indication that the connector was deployed.
    2.  Realized the connector configuration (`pg-connector.json`) needs to be POSTed to the Kafka Connect API.
    3.  Deployed the connector:
        ```bash
        docker exec kafka_connect sh -c "cat /kafka/connect/debezium-connector-config/pg-connector.json | curl -X POST -H 'Content-Type: application/json' --data @- http://localhost:8083/connectors"
        ```
    4.  Verified connector startup and slot creation in `docker logs kafka_connect`.
    5.  Confirmed slot `debezium_slot_inventory` was visible with `SELECT * FROM pg_replication_slots;`.

### Consuming Kafka Messages

*   **Problem:** `kafkacat: command not found` when trying to consume from host.
*   **Solution:** Used the Kafka console consumer script from within the `kafka` container:
    ```bash
    docker exec kafka sh -c "/kafka/bin/kafka-console-consumer.sh --bootstrap-server kafka:9092 --topic inventory_server.inventory.products --from-beginning --property print.key=true --property key.separator=':'"
    ```

### Monitoring Debezium

*   **Connector Status (REST API):**
    ```bash
    docker exec kafka_connect curl -s http://localhost:8083/connectors/inventory-postgres-connector/status
    ```
    *(Expected: connector and task state "RUNNING")*
*   **Kafka Connect Logs:**
    ```bash
    docker logs kafka_connect
    ```
*   **PostgreSQL Replication Slot:**
    ```sql
    SELECT slot_name, plugin, slot_type, active, restart_lsn, confirmed_flush_lsn FROM pg_replication_slots WHERE slot_name = 'debezium_slot_inventory';
    ```