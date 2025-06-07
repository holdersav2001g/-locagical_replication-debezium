# PostgreSQL Setup Guide for Debezium Logical Replication

This document outlines the necessary PostgreSQL configurations and SQL commands required to enable logical replication for use with Debezium. These steps can be broken down into individual tasks or Jira tickets.

## I. PostgreSQL Server Configuration (`postgresql.conf`)

These settings typically require a server restart to take effect.

**Jira Ticket Suggestion:** Configure PostgreSQL for Logical Replication

**Description:** Modify the `postgresql.conf` file to enable logical replication and configure related parameters. A server restart will be required after these changes.

**Tasks:**

1.  **Set `wal_level`:**
    *   **Action:** Ensure `wal_level` is set to `logical`. This enables the generation of Write-Ahead Log (WAL) records with enough information for logical decoding.
    *   **Configuration:**
        ```ini
        wal_level = logical
        ```
    *   **Note:** This change requires a server restart.

2.  **Configure `max_wal_senders`:**
    *   **Action:** Set the maximum number of concurrent WAL sender processes. This should be at least the number of expected streaming replication clients (including Debezium) plus any physical replicas.
    *   **Configuration (Example from project):**
        ```ini
        max_wal_senders = 10
        ```
    *   **Note:** This change requires a server restart. Adjust the value based on your environment's needs.

3.  **Configure `wal_keep_size` (or `wal_keep_segments` for older PostgreSQL versions):**
    *   **Action:** Specify the minimum amount of WAL segments to keep in the `pg_wal` directory. This is important to ensure Debezium can catch up if it falls behind or during initial snapshotting if the slot is created beforehand.
    *   **Configuration (Example from project):**
        ```ini
        wal_keep_size = 256MB
        ```
    *   **Note:** If using PostgreSQL versions prior to 13, you might use `wal_keep_segments` instead.

4.  **Configure `max_replication_slots`:**
    *   **Action:** Set the maximum number of replication slots the server can support. Each Debezium connector requires one logical replication slot.
    *   **Configuration (Example from project):**
        ```ini
        max_replication_slots = 10
        ```
    *   **Note:** This change requires a server restart. Ensure this is greater than or equal to the number of Debezium connectors plus any other replication slots in use.

5.  **Configure `max_logical_replication_workers`:**
    *   **Action:** Set the maximum number of logical replication workers. This includes workers for applying changes on subscribers and also affects initial data synchronization for tables.
    *   **Configuration (Example from project):**
        ```ini
        max_logical_replication_workers = 4
        ```
    *   **Note:** The default is often sufficient, but can be tuned.

## II. Host-Based Authentication (`pg_hba.conf`)

These changes allow the Debezium user to connect to the database for replication and snapshotting. Changes to `pg_hba.conf` typically require a server reload (e.g., `SELECT pg_reload_conf();` or `pg_ctl reload`).

**Jira Ticket Suggestion:** Configure PostgreSQL Access for Debezium User (`pg_hba.conf`)

**Description:** Update the `pg_hba.conf` file to grant the necessary connection permissions for the Debezium user from the Kafka Connect host(s).

**Tasks:**

1.  **Allow Connection for Replication:**
    *   **Action:** Add an entry to allow the Debezium user (or a dedicated replication role it uses) to connect to the `replication` pseudo-database.
    *   **Configuration (Example for user `debezium_user` from any IP):**
        ```
        # TYPE  DATABASE        USER            ADDRESS                 METHOD
        host    replication     debezium_user   0.0.0.0/0               scram-sha-256
        host    replication     debezium_user   ::/0                    scram-sha-256
        ```
    *   **Note:** Replace `debezium_user` if you use a different user for the Debezium connector. For production, restrict `ADDRESS` to the specific IP(s) or subnet(s) of your Kafka Connect instances. `scram-sha-256` is recommended for password authentication.

2.  **Allow Connection to Target Database(s):**
    *   **Action:** Add an entry to allow the Debezium user to connect to the specific database(s) it will be monitoring.
    *   **Configuration (Example for user `debezium_user` to `inventory_db` from any IP):**
        ```
        # TYPE  DATABASE        USER            ADDRESS                 METHOD
        host    inventory_db    debezium_user   0.0.0.0/0               scram-sha-256
        host    inventory_db    debezium_user   ::/0                    scram-sha-256
        ```
    *   **Note:** Adjust `inventory_db` and `debezium_user` as needed. Restrict `ADDRESS` in production.

## III. Database Users, Permissions, and Publication (SQL Commands)

These SQL commands should be executed in the target database by a superuser or a user with sufficient privileges.

**Jira Ticket Suggestion 1:** Create Debezium User and Grant Replication Privileges

**Description:** Create a dedicated PostgreSQL user for Debezium and grant it the necessary privileges for logical replication.

**Tasks:**

1.  **Create Debezium User:**
    *   **Action:** Create a new user with a strong password.
    *   **SQL:**
        ```sql
        CREATE USER debezium_user WITH LOGIN PASSWORD 'YourStrongPasswordHere!';
        ```
    *   **Note:** Replace `debezium_user` and `YourStrongPasswordHere!` as appropriate.

2.  **Grant REPLICATION Privilege:**
    *   **Action:** Grant the `REPLICATION` privilege to the Debezium user.
    *   **SQL:**
        ```sql
        ALTER USER debezium_user WITH REPLICATION;
        ```

3.  **Grant CONNECT Privilege on Database:**
    *   **Action:** Allow the Debezium user to connect to the target database.
    *   **SQL (Example for `inventory_db`):**
        ```sql
        GRANT CONNECT ON DATABASE inventory_db TO debezium_user;
        ```

**Jira Ticket Suggestion 2:** Grant Schema and Table Permissions to Debezium User

**Description:** Grant the Debezium user the necessary permissions on the schemas and tables that will be captured.

**Tasks:**

1.  **Grant USAGE on Schema(s):**
    *   **Action:** Allow the Debezium user to access the schema(s) containing the tables to be replicated.
    *   **SQL (Example for `inventory` schema):**
        ```sql
        GRANT USAGE ON SCHEMA inventory TO debezium_user;
        ```
    *   **Note:** Repeat for all schemas Debezium needs to access.

2.  **Grant SELECT on Table(s):**
    *   **Action:** Allow the Debezium user to read from the tables to be replicated. This is required for the initial snapshot.
    *   **SQL (Example for `inventory.products` table):**
        ```sql
        GRANT SELECT ON TABLE inventory.products TO debezium_user;
        ```
    *   **Note:** Repeat for all tables to be captured, or use `GRANT SELECT ON ALL TABLES IN SCHEMA inventory TO debezium_user;` if appropriate.

3.  **(Optional) Grant CREATE on Database for Debezium-managed Publication:**
    *   **Action:** If you want Debezium to automatically create and manage its publication (via `publication.autocreate.mode` in connector config, not set to `disabled`), it needs `CREATE` privilege on the database.
    *   **SQL (Example for `inventory_db`):**
        ```sql
        GRANT CREATE ON DATABASE inventory_db TO debezium_user;
        ```

**Jira Ticket Suggestion 3:** Create PostgreSQL Publication for Debezium

**Description:** Create a PostgreSQL `PUBLICATION` that includes the tables Debezium should capture changes from. The publication name must match the `publication.name` property in the Debezium connector configuration.

**Tasks:**

1.  **Create Publication for Specific Tables:**
    *   **Action:** Create a publication and add the specific tables to it.
    *   **SQL (Example for `products` table in `inventory` schema, publication named `dbz_publication`):**
        ```sql
        CREATE PUBLICATION dbz_publication FOR TABLE inventory.products;
        ```
    *   **Note:** Add other tables as needed: `ALTER PUBLICATION dbz_publication ADD TABLE inventory.another_table;`

    **OR**

2.  **Create Publication for All Tables in a Schema:**
    *   **Action:** Create a publication that automatically includes all current and future tables in one or more specified schemas.
    *   **SQL (Example for all tables in `inventory` schema, publication named `dbz_inventory_publication`):**
        ```sql
        CREATE PUBLICATION dbz_inventory_publication FOR ALL TABLES IN SCHEMA inventory;
        ```
    *   **Note:** This is often more convenient if you want to capture all tables in a schema.

    **OR**

3.  **Create Publication for All Tables in the Database (Use with Caution):**
    *   **Action:** Create a publication that includes all tables in the entire database.
    *   **SQL (Example publication named `dbz_all_tables_publication`):**
        ```sql
        CREATE PUBLICATION dbz_all_tables_publication FOR ALL TABLES;
        ```
    *   **Note:** This is generally too broad for production environments unless explicitly intended.

---

**Important Considerations:**

*   **Security:** Always use strong, unique passwords for database users. Restrict network access in `pg_hba.conf` as much as possible (e.g., to specific IP addresses of your Kafka Connect hosts).
*   **User Privileges:** Grant only the necessary privileges to the Debezium user.
*   **Restart/Reload:** Remember that changes to `postgresql.conf` usually require a server restart, while `pg_hba.conf` changes typically require a reload. SQL DDL commands take effect immediately.
*   **Testing:** Thoroughly test the setup in a non-production environment before deploying to production.
*   **Version Compatibility:** Ensure your Debezium connector version is compatible with your PostgreSQL version.