# Test Results: WAL Generation for Logged vs. Unlogged Tables

This document presents the results of the WAL (Write-Ahead Log) generation test as outlined in `wal_generation_test_plan.md`. The test involved inserting 1 million rows into both a standard `LOGGED` table and an `UNLOGGED` table and measuring the amount of WAL data generated.

## I. Test Execution Summary

*   **Workload:** 1,000,000 rows inserted into each table.
*   **Parallelism:** 10 concurrent processes.
*   **Batch Size:** 1,000 rows per transaction batch.

### Performance Observations

*   **`logged_bulk_test` duration:** 23.08 seconds
*   **`unlogged_bulk_test` duration:** 13.17 seconds

The data load into the `UNLOGGED` table was approximately **43% faster** than the `LOGGED` table.

## II. WAL Generation Comparison

The following table shows the delta in WAL statistics before and after the data load for each table type.

| Metric        | `logged_bulk_test` (Delta) | `unlogged_bulk_test` (Delta) | Reduction Factor |
|---------------|----------------------------|------------------------------|------------------|
| `wal_records` | 2,004,732                  | 10,345                       | ~194x            |
| `wal_bytes`   | 189,214,022 (~180.4 MB)    | 642,319 (~0.6 MB)            | ~295x            |

## III. Analysis and Conclusion

The results clearly and dramatically demonstrate the core trade-off of using `UNLOGGED` tables in PostgreSQL.

1.  **`LOGGED` Table:** As expected, inserting 1 million rows into the standard `LOGGED` table generated a substantial amount of WAL traffic. Over 2 million WAL records were created, consuming approximately **180.4 MB** of WAL space. This is the standard behavior required to ensure durability (crash safety) and to enable point-in-time recovery and replication.

2.  **`UNLOGGED` Table:** The `UNLOGGED` table generated a tiny fraction of the WAL traffic. The ~0.6 MB of WAL data generated is likely due to metadata operations (e.g., file extension) rather than the row data itself, which is not logged. This resulted in a **~295x reduction in WAL bytes** written to disk.

**Conclusion:**

The hypothesis in the test plan is confirmed. Using `UNLOGGED` tables provides a significant performance boost and drastically reduces I/O for write-heavy, transient workloads by bypassing the WAL mechanism. This comes at the cost of durability and the inability to replicate these tables.

This makes `UNLOGGED` tables an excellent choice for:
*   Staging tables for large data loads in an ETL process.
*   Tables holding transient session data.
*   Any scenario where performance is critical and the data can be easily regenerated or is not required to survive a database crash.