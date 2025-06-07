import psycopg2
from psycopg2.extras import execute_batch
import json

# Set your variable
loop_count = 10000
batch_size = 1000
# Load database connection parameters from JSON config
with open('debezium-connector-config/pg-connector.json', 'r') as f:
    config = json.load(f)
conn_params = {
    "dbname": config.get("database.dbname"),
    "user": "postgres_user",
    "password": "postgres_password",
    "host": config.get("database.hostname"),
    "port": config.get("database.port", 5432)
}


# Example data for insertion (adjust columns as needed)
def generate_row(i):
    # Replace with actual column values
    return (f"product_{i}", 10 + i, 1.99 + i)

# Connect to the PostgreSQL database
conn = psycopg2.connect(**conn_params)
cur = conn.cursor()

# Insert rows in batches
for start in range(0, loop_count, batch_size):
    batch = [generate_row(i) for i in range(start, min(start + batch_size, loop_count))]
    execute_batch(
        cur,
        "INSERT INTO products (name, description, quantity) VALUES (%s, %s, %s);",
        batch
    )
    conn.commit()

cur.close()
conn.close()

if __name__ == "__main__":
    generate_row(10)