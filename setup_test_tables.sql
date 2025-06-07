-- Drop tables if they exist to ensure a clean state
DROP TABLE IF EXISTS public.logged_bulk_test;
DROP TABLE IF EXISTS public.unlogged_bulk_test;

-- Create a standard LOGGED table for the test
CREATE TABLE public.logged_bulk_test (
    id INT PRIMARY KEY,
    payload TEXT
);

-- Create an UNLOGGED table for comparison if needed
CREATE UNLOGGED TABLE public.unlogged_bulk_test (
    id INT PRIMARY KEY,
    payload TEXT
);

-- Grant permissions to the application user
GRANT ALL PRIVILEGES ON TABLE public.logged_bulk_test TO postgres_user;
GRANT ALL PRIVILEGES ON TABLE public.unlogged_bulk_test TO postgres_user;

COMMIT;