# Test Plan: Measuring WAL Generation for Logged vs. Unlogged Tables

### **Objective**
To measure and compare the amount of Write-Ahead Log (WAL) data generated when performing a bulk insert of 1 million rows into a standard (`LOGGED`) table versus an `UNLOGGED` table in PostgreSQL.

### **Methodology**
The test will be conducted in two distinct runs. Each run will involve resetting WAL statistics, performing a parallelized, batched data load into the target table, and then capturing the final WAL statistics. The key metric for comparison will be the delta in `wal_bytes` and `wal_records` before and after the data load.

---

### **Phase 1: Environment Preparation**

This phase involves setting up the necessary database objects.

1.  **Create Test Tables:**
    *   Connect to your PostgreSQL database (e.g., `inventory_db`) as a superuser or a user with table creation privileges.
    *   Execute the following SQL to create two tables with identical structures: one standard `LOGGED` table and one `UNLOGGED` table.

    ```sql
    -- Table 1: Standard LOGGED table
    CREATE TABLE logged_bulk_test (
        id INT PRIMARY KEY,
        payload TEXT NOT NULL
    );

    -- Table 2: UNLOGGED table
    CREATE UNLOGGED TABLE unlogged_bulk_test (
        id INT PRIMARY KEY,
        payload TEXT NOT NULL
    );
    ```

2.  **Prepare Data Loading Script:**
    *   A Python script is ideal for this task due to its excellent `psycopg2` library and `multiprocessing` module for parallelism.
    *   **Script Name:** `parallel_data_loader.py`
    *   **Core Logic:**
        *   The script will accept command-line arguments for the database connection details and the target table name (e.g., `logged_bulk_test` or `unlogged_bulk_test`).
        *   It will use Python's `multiprocessing.Pool` to create a pool of 10 worker processes.
        *   The total workload of 1 million rows will be divided among the 10 workers (100,000 rows each).
        *   Each worker will connect to the database and perform its inserts in batches to maximize efficiency. A batch size of 1,000 is reasonable (meaning each worker will execute 100 batch inserts).
        *   The script will use `psycopg2.extras.execute_batch()` for high-performance batch inserting.
        *   The data to be inserted can be simple generated data (e.g., `id` from a range, `payload` as a random string).

3.  **Prepare WAL Statistics Query:**
    *   Create a simple SQL script to query the `pg_stat_wal` view. This view provides cumulative WAL statistics since the last reset.
    *   **Script Name:** `get_wal_stats.sql`
    *   **Content:**
        ```sql
        SELECT
            wal_records,
            wal_fpi,
            wal_bytes
        FROM pg_stat_wal;
        ```

---

### **Phase 2: Test Execution Plan**

This is the step-by-step process for running the tests. The following flowchart illustrates the process for a single run. This entire process will be performed twice—once for each table type.

```mermaid
graph TD
    A[Start Run] --> B(Reset Server-Wide WAL Statistics);
    B --> C(Truncate Target Table);
    C --> D(Capture "Before" WAL Stats);
    D --> E(Execute Parallel Data Loading Script);
    E --> F(Capture "After" WAL Stats);
    F --> G(Calculate and Record the Delta);
    G --> H[End Run];
```

#### **Test Run 1: LOGGED Table**

1.  **Reset Statistics:** Connect to the database as a superuser and reset all server-wide statistics, including WAL stats.
    ```sql
    SELECT pg_stat_reset_shared('wal');
    ```
2.  **Prepare Table:** Ensure the table is empty.
    ```sql
    TRUNCATE TABLE logged_bulk_test;
    ```
3.  **Capture "Before" Stats:** Run the `get_wal_stats.sql` script and record the output for `wal_records` and `wal_bytes`. These values should be 0 or very close to it.
4.  **Execute Data Load:** Run the Python script, targeting the `logged_bulk_test` table.
    ```bash
    python parallel_data_loader.py --table logged_bulk_test
    ```
5.  **Capture "After" Stats:** Immediately after the script finishes, run `get_wal_stats.sql` again and record the new output.
6.  **Calculate Delta:** Subtract the "Before" values from the "After" values to get the total WAL records and bytes generated.

#### **Test Run 2: UNLOGGED Table**

1.  **Reset Statistics:** Reset the stats again to ensure a clean slate for the second test.
    ```sql
    SELECT pg_stat_reset_shared('wal');
    ```
2.  **Prepare Table:** Ensure the table is empty.
    ```sql
    TRUNCATE TABLE unlogged_bulk_test;
    ```
3.  **Capture "Before" Stats:** Run `get_wal_stats.sql` and record the output.
4.  **Execute Data Load:** Run the Python script, this time targeting the `unlogged_bulk_test` table.
    ```bash
    python parallel_data_loader.py --table unlogged_bulk_test
    ```
5.  **Capture "After" Stats:** Immediately after the script finishes, run `get_wal_stats.sql` again and record the new output.
6.  **Calculate Delta:** Subtract the "Before" values from the "After" values.

---

### **Phase 3: Analysis and Expected Outcome**

**Hypothesis:**

*   The **`logged_bulk_test`** run will generate a significant amount of WAL data, measurable in many megabytes or even gigabytes, and a very high number of WAL records.
*   The **`unlogged_bulk_test`** run will generate a negligible amount of WAL data, if any. `INSERT`, `UPDATE`, and `DELETE` operations on unlogged tables do not write to the WALs. Only certain metadata changes might generate a tiny amount of WAL traffic, which should be orders of magnitude less than the logged table.

**Comparison:**

Present the results in a simple table for easy comparison:

| Metric        | LOGGED Table (Delta) | UNLOGGED Table (Delta) |
|---------------|----------------------|------------------------|
| `wal_records` | ~1,000,000+          | ~0                     |
| `wal_bytes`   | (High value in MB/GB)| ~0                     |

This stark difference will clearly demonstrate the primary characteristic of `UNLOGGED` tables: they trade durability and replication capability for significantly reduced I/O and higher performance on data modification operations.