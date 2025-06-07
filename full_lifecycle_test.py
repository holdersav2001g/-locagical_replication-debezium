import time
import argparse
import uuid
from multiprocessing import Pool, current_process
import psycopg2
from psycopg2.extras import execute_batch

# --- Configuration ---
DB_HOST = "localhost"
DB_PORT = "5432"
DB_NAME = "inventory_db"
DB_USER = "postgres_user"
DB_PASS = "postgres_password"
NUM_PROCESSES = 10
TOTAL_ROWS = 1000000
BATCH_SIZE = 100 # As requested by the user

def get_db_connection():
    """Establishes a new database connection."""
    return psycopg2.connect(
        dbname=DB_NAME, user=DB_USER, password=DB_PASS, host=DB_HOST, port=DB_PORT
    )

def insert_data_worker(worker_args):
    """Worker function to insert a chunk of data."""
    start_id, num_rows, table_name = worker_args
    process_name = current_process().name
    print(f"[{process_name}] Starting INSERT, assigned {num_rows} rows starting from ID {start_id}.")
    
    data_to_insert = [
        (start_id + i, f"Payload for row {start_id + i} - {uuid.uuid4()}")
        for i in range(num_rows)
    ]
    
    conn = get_db_connection()
    cursor = conn.cursor()
    execute_batch(
        cursor,
        f"INSERT INTO public.{table_name} (id, payload) VALUES (%s, %s)",
        data_to_insert,
        page_size=BATCH_SIZE
    )
    conn.commit()
    cursor.close()
    conn.close()
    print(f"[{process_name}] Successfully INSERTED {num_rows} rows.")

def update_data_worker(worker_args):
    """Worker function to update a chunk of data."""
    start_id, num_rows, table_name = worker_args
    process_name = current_process().name
    print(f"[{process_name}] Starting UPDATE, assigned {num_rows} rows starting from ID {start_id}.")
    
    data_to_update = [
        (f"Updated payload at {time.time_ns()} - {uuid.uuid4()}", start_id + i)
        for i in range(num_rows)
    ]

    conn = get_db_connection()
    cursor = conn.cursor()
    execute_batch(
        cursor,
        f"UPDATE public.{table_name} SET payload = %s WHERE id = %s",
        data_to_update,
        page_size=BATCH_SIZE
    )
    conn.commit()
    cursor.close()
    conn.close()
    print(f"[{process_name}] Successfully UPDATED {num_rows} rows.")

def delete_data_worker(worker_args):
    """Worker function to delete a chunk of data."""
    start_id, num_rows, table_name = worker_args
    process_name = current_process().name
    print(f"[{process_name}] Starting DELETE, assigned {num_rows} rows starting from ID {start_id}.")
    
    # Generate IDs to delete
    ids_to_delete = [(start_id + i,) for i in range(num_rows)]

    conn = get_db_connection()
    cursor = conn.cursor()
    execute_batch(
        cursor,
        f"DELETE FROM public.{table_name} WHERE id = %s",
        ids_to_delete,
        page_size=BATCH_SIZE
    )
    conn.commit()
    cursor.close()
    conn.close()
    print(f"[{process_name}] Successfully DELETED {num_rows} rows.")

def run_phase(phase_function, table_name, phase_name):
    """Generic function to run a DML phase."""
    print("\n" + "="*30)
    print(f"Starting {phase_name.upper()} phase for table: '{table_name}'")
    print(f"Total Rows: {TOTAL_ROWS}, Processes: {NUM_PROCESSES}, Batch Size: {BATCH_SIZE}")
    print("-"*30)
    
    start_time = time.time()
    
    rows_per_process = TOTAL_ROWS // NUM_PROCESSES
    worker_args = [
        (i * rows_per_process, rows_per_process, table_name)
        for i in range(NUM_PROCESSES)
    ]

    with Pool(NUM_PROCESSES) as pool:
        pool.map(phase_function, worker_args)
        
    end_time = time.time()
    duration = end_time - start_time
    
    print("-"*30)
    print(f"{phase_name.upper()} phase complete for table '{table_name}'.")
    print(f"Total time taken: {duration:.2f} seconds.")
    print("="*30 + "\n")

def main():
    parser = argparse.ArgumentParser(description="Run a full DML lifecycle test on a PostgreSQL table.")
    parser.add_argument('--phase', required=True, choices=['insert', 'update', 'delete'], help='The DML phase to execute.')
    parser.add_argument('--table', required=True, help='The name of the target table.')
    args = parser.parse_args()

    if args.phase == 'insert':
        run_phase(insert_data_worker, args.table, 'insert')
    elif args.phase == 'update':
        run_phase(update_data_worker, args.table, 'update')
    elif args.phase == 'delete':
        run_phase(delete_data_worker, args.table, 'delete')

if __name__ == "__main__":
    main()