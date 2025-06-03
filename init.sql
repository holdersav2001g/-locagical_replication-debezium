-- This script is executed by POSTGRES_USER (postgres_user) within POSTGRES_DB (inventory_db).

-- Set a more secure search_path
SET search_path = public, pg_catalog;

-- 1. Create a dedicated replication user
-- This user is often specified in pg_hba.conf for 'replication' type connections.
-- Debezium's actual connector user ('debezium_user') will also need REPLICATION privilege.
CREATE USER replicator WITH LOGIN REPLICATION PASSWORD 'ReplicatorP@ssw0rdStr0ng!';

-- 2. Create the Debezium user
CREATE USER debezium_user WITH LOGIN PASSWORD 'DebeziumP@ssw0rdStr0ng!';

-- Grant REPLICATION privilege to debezium_user. This is crucial for Debezium to stream changes.
ALTER USER debezium_user WITH REPLICATION;

-- 3. Create schema for inventory data
-- The main application user (postgres_user) will own this schema.
CREATE SCHEMA IF NOT EXISTS inventory AUTHORIZATION postgres_user;

-- 4. Grant USAGE on the schema to debezium_user
GRANT USAGE ON SCHEMA inventory TO debezium_user;

-- 5. Grant CREATE on database to debezium_user
-- This allows Debezium to create/manage its own publication if 'publication.autocreate.mode' is not 'disabled'.
GRANT CREATE ON DATABASE inventory_db TO debezium_user;

-- Switch to the inventory schema for table creation
SET search_path = inventory, public;

-- 6. Create the products table
CREATE TABLE products (
    id SERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    description TEXT,
    quantity INTEGER NOT NULL CHECK (quantity >= 0),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
ALTER TABLE products OWNER TO postgres_user;

-- Create a function to automatically update the 'updated_at' timestamp
CREATE OR REPLACE FUNCTION trigger_set_timestamp()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;
ALTER FUNCTION trigger_set_timestamp() OWNER TO postgres_user; -- Ensure owner is correct

-- Create a trigger on the products table to use the function
CREATE TRIGGER set_timestamp_products_trigger
BEFORE UPDATE ON products
FOR EACH ROW
EXECUTE FUNCTION trigger_set_timestamp();

-- 7. Grant SELECT on the products table to debezium_user
GRANT SELECT ON TABLE products TO debezium_user;

-- 8. Grant necessary privileges for the main application user (postgres_user)
-- Note: postgres_user is already the owner of the schema and table by AUTHORIZATION and ALTER TABLE OWNER.
-- These grants ensure it has explicit operational privileges.
GRANT ALL ON SCHEMA inventory TO postgres_user;
GRANT ALL PRIVILEGES ON TABLE products TO postgres_user;
GRANT USAGE, SELECT ON SEQUENCE products_id_seq TO postgres_user; -- Grant on the sequence for SERIAL
GRANT EXECUTE ON FUNCTION trigger_set_timestamp() TO postgres_user;

-- Set default privileges for future objects created by postgres_user in the inventory schema
ALTER DEFAULT PRIVILEGES IN SCHEMA inventory FOR USER postgres_user
    GRANT ALL ON TABLES TO postgres_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA inventory FOR USER postgres_user
    GRANT ALL ON SEQUENCES TO postgres_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA inventory FOR USER postgres_user
    GRANT EXECUTE ON FUNCTIONS TO postgres_user;

-- 9. Create the publication for Debezium
-- This publication will be used by the Debezium connector.
-- The name 'dbz_publication' should match the 'publication.name' in the connector configuration.
CREATE PUBLICATION dbz_publication FOR TABLE products;
-- Alternatively, to include all tables in the 'inventory' schema (if you add more later):
-- CREATE PUBLICATION dbz_inventory_publication FOR ALL TABLES IN SCHEMA inventory;
-- Or, for all tables in the entire database (use with caution, generally too broad for production):
-- CREATE PUBLICATION dbz_all_tables_publication FOR ALL TABLES;

-- Reset search_path to default
SET search_path = "$user", public;

-- Grant connect to the database for the users if not already implicitly granted
GRANT CONNECT ON DATABASE inventory_db TO replicator;
GRANT CONNECT ON DATABASE inventory_db TO debezium_user;
GRANT CONNECT ON DATABASE inventory_db TO postgres_user;

-- Make sure postgres_user can create publications if needed (already superuser in this context)
-- ALTER USER postgres_user WITH CREATEPUBLICATION; -- Not strictly needed as it's the effective superuser

-- Output a success message (optional, for logs)
SELECT 'PostgreSQL initialization script completed successfully.' AS status;