# Test Results: Full DML Lifecycle WAL Generation (Physical vs. Logical)

This document presents the results of a comprehensive WAL (Write-Ahead Log) generation test comparing PostgreSQL's `replica` and `logical` `wal_level` settings across a full DML lifecycle: `INSERT`, `UPDATE`, and `DELETE`.

## I. Test Summary

*   **Workload:** 1,000,000 rows were inserted, then updated, then deleted.
*   **Batch Size:** 100 rows per transaction.
*   **Objective:** To isolate and compare the performance and WAL volume for each DML operation under both replication settings.

## II. Performance Comparison (Execution Time)

| DML Phase | `wal_level = replica` | `wal_level = logical` | Difference |
|-----------|-----------------------|-----------------------|------------|
| `INSERT`  | 59.19 seconds         | 58.63 seconds         | -0.9%      |
| `UPDATE`  | 65.05 seconds         | 64.96 seconds         | -0.1%      |
| `DELETE`  | 13.61 seconds         | 14.02 seconds         | +3.0%      |

**Observation:** The execution time for all DML operations was nearly identical between the two modes, with no significant performance penalty observed for `wal_level = logical`.

## III. WAL Generation Comparison

This table shows the calculated delta of WAL records and bytes generated *for each specific phase*.

| DML Phase | `wal_level` | `wal_records` (Delta) | `wal_bytes` (Delta)       | `wal_bytes` (Human) |
|-----------|-------------|-----------------------|---------------------------|---------------------|
| `INSERT`  | `replica`   | 2,017,086             | 200,863,665               | ~191.5 MB           |
| `INSERT`  | `logical`   | 2,004,735             | 200,097,950               | ~190.8 MB           |
|           |             |                       |                           |                     |
| `UPDATE`  | `replica`   | 3,001,198             | 275,277,220               | ~262.5 MB           |
| `UPDATE`  | `logical`   | 3,010,527             | 275,844,961               | ~263.1 MB           |
|           |             |                       |                           |                     |
| `DELETE`  | `replica`   | 1,012,374             | 56,669,662                | ~54.0 MB            |
| `DELETE`  | `logical`   | 1,000,015             | **92,301,395**            | **~88.0 MB**        |

## IV. Analysis and Conclusion

The results of this comprehensive test are definitive and confirm the findings from the previous `INSERT`-only test, while revealing the true cost of `DELETE` operations.

**1. `INSERT` and `UPDATE` Operations:**
As observed previously, the WAL generation for both `INSERT` and `UPDATE` operations is **virtually identical** between `replica` and `logical` modes. The minor variations are negligible and fall within the bounds of normal operational noise. This strongly suggests that for `INSERT`s and `UPDATE`s (where the new row data contains all necessary information), PostgreSQL's WAL format is already sufficient for the needs of logical decoding without requiring significant extra data.

**2. `DELETE` Operations (The Key Finding):**
The hypothesis is confirmed. The `DELETE` phase shows a dramatic difference in WAL generation:
*   **`logical` mode generated ~63% more WAL bytes than `replica` mode for the `DELETE` operation.**

This is the expected overhead. In `replica` mode, a `DELETE` can be a very compact WAL record, often just referencing the block and tuple ID to be removed. However, in `logical` mode, PostgreSQL must write enough information for a downstream system like Debezium to identify *which row was deleted*. This typically means writing the primary key of the deleted row to the WAL, which carries a significantly higher byte cost, as demonstrated by the ~34 MB of extra WAL data generated in this test.

**Overall Conclusion:**

The performance cost of enabling `wal_level = logical` is not in the raw execution speed of DML operations, but specifically in the **storage I/O cost of `DELETE` statements**.

*   Systems with `INSERT` and `UPDATE`-heavy workloads can adopt logical replication with minimal concern for WAL volume overhead.
*   Systems with `DELETE`-heavy workloads (e.g., frequent data purging, session cleanup) will experience a notable increase in WAL generation. This needs to be factored into disk space planning and I/O capacity for the WAL drive to prevent performance bottlenecks.