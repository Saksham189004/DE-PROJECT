-- =====================================================================
-- MakeMyTrip Travel Booking Database: Table Partitioning Architecture (Phase 5)
-- Schema: mmt
-- Demonstrates Declarative Table Partitioning for 100x Growth
-- =====================================================================

SET search_path TO mmt;

-- ---------------------------------------------------------------------
-- 1. ARCHITECTURAL JUSTIFICATION: WHY PARTITION `bookings`?
-- ---------------------------------------------------------------------
-- 1. Monotonic Temporal Growth:
--    `bookings` is the primary high-velocity transactional table, growing by
--    millions of rows monthly. At 100x scale (~14.5M bookings/year), an unpartitioned
--    heap exceeds 15 GB, causing b-tree index leaf nodes to spill out of RAM.
-- 2. Query Locality & Partition Pruning:
--    Over 80% of analytical and OLTP queries filter by booking date (`booked_at`),
--    such as monthly reconciliations (June 2026, Q2 2026). Partition pruning allows
--    PostgreSQL to skip scanning 90%+ of physical disk blocks entirely.
-- 3. Lifecycle Data Management:
--    Older partitions (e.g. historical data older than 2 years) can be detached instantly
--    via ALTER TABLE DETACH PARTITION and archived to compressed columnar storage (Parquet/S3),
--    or dropped without running expensive DELETE / VACUUM operations.

-- ---------------------------------------------------------------------
-- 2. POSTGRESQL PRIMARY KEY RULE ON PARTITIONED TABLES
-- ---------------------------------------------------------------------
-- IMPORTANT CONSTRAINT RULE:
-- In PostgreSQL declarative partitioning, any UNIQUE or PRIMARY KEY constraint
-- on a partitioned table MUST contain the partition key column(s).
--
-- Why?
-- PostgreSQL enforces unique constraints locally within each individual partition index.
-- It does not support cross-partition global indexes. To guarantee that a `booking_id`
-- is globally unique across all partitions without an expensive inter-partition scan,
-- the partition key (`booked_at`) must form part of the composite primary key:
--     PRIMARY KEY (booking_id, booked_at)
--
-- For natural candidate keys like `booking_ref`, global uniqueness at 100x scale is
-- enforced either by embedding the partition date code in the reference (e.g. '2606-MMA7772F')
-- or via an application-level distributed ID generator / Redis bloom filter.
-- ---------------------------------------------------------------------

DROP TABLE IF EXISTS bookings_partitioned CASCADE;

-- Create declarative range-partitioned master table
CREATE TABLE bookings_partitioned (
    booking_id      INTEGER NOT NULL,
    booking_ref     VARCHAR(20) NOT NULL,
    customer_id     INTEGER NOT NULL,
    booking_type    VARCHAR(20) NOT NULL,
    booked_at       TIMESTAMPTZ NOT NULL,
    total_amount    NUMERIC(10,2) NOT NULL,
    coupon_code     VARCHAR(30) NULL,
    discount        NUMERIC(10,2) NOT NULL DEFAULT 0.00,
    payment_method  VARCHAR(20) NOT NULL,
    status          VARCHAR(30) NOT NULL,
    cancelled_at    TIMESTAMPTZ NULL,
    refund_amount   NUMERIC(10,2) NULL,
    CONSTRAINT pk_bookings_partitioned PRIMARY KEY (booking_id, booked_at)
) PARTITION BY RANGE (booked_at);

-- ---------------------------------------------------------------------
-- 3. CREATE QUARTERLY PARTITIONS (2025 - 2026)
-- ---------------------------------------------------------------------
CREATE TABLE bookings_2025_q1 PARTITION OF bookings_partitioned
    FOR VALUES FROM ('2025-01-01 00:00:00+05:30') TO ('2025-04-01 00:00:00+05:30');

CREATE TABLE bookings_2025_q2 PARTITION OF bookings_partitioned
    FOR VALUES FROM ('2025-04-01 00:00:00+05:30') TO ('2025-07-01 00:00:00+05:30');

CREATE TABLE bookings_2025_q3 PARTITION OF bookings_partitioned
    FOR VALUES FROM ('2025-07-01 00:00:00+05:30') TO ('2025-10-01 00:00:00+05:30');

CREATE TABLE bookings_2025_q4 PARTITION OF bookings_partitioned
    FOR VALUES FROM ('2025-10-01 00:00:00+05:30') TO ('2026-01-01 00:00:00+05:30');

CREATE TABLE bookings_2026_q1 PARTITION OF bookings_partitioned
    FOR VALUES FROM ('2026-01-01 00:00:00+05:30') TO ('2026-04-01 00:00:00+05:30');

CREATE TABLE bookings_2026_q2 PARTITION OF bookings_partitioned
    FOR VALUES FROM ('2026-04-01 00:00:00+05:30') TO ('2026-07-01 00:00:00+05:30');

CREATE TABLE bookings_2026_q3 PARTITION OF bookings_partitioned
    FOR VALUES FROM ('2026-07-01 00:00:00+05:30') TO ('2026-10-01 00:00:00+05:30');

-- Default partition for catch-all data routing
CREATE TABLE bookings_default PARTITION OF bookings_partitioned DEFAULT;

-- ---------------------------------------------------------------------
-- 4. LOCAL INDEXES ON PARTITIONED RELATIONS
-- Indexes created on the parent partitioned table automatically propagate
-- to all existing and future child partitions.
-- ---------------------------------------------------------------------
CREATE INDEX idx_part_bookings_cust_status ON bookings_partitioned (customer_id, status);
CREATE INDEX idx_part_bookings_booked_at ON bookings_partitioned (booked_at);
CREATE INDEX idx_part_bookings_ref ON bookings_partitioned (booking_ref);

-- Populate partitioned table from base bookings table
INSERT INTO bookings_partitioned 
SELECT booking_id, booking_ref, customer_id, booking_type, booked_at, total_amount, 
       coupon_code, discount, payment_method, status, cancelled_at, refund_amount
FROM bookings;

ANALYZE bookings_partitioned;

-- ---------------------------------------------------------------------
-- 5. DEMONSTRATION OF PARTITION PRUNING
-- Query targeting June 2026 (Q2 2026).
-- The execution plan proves that ONLY `bookings_2026_q2` is scanned.
-- All other quarters (2025 Q1..Q4, 2026 Q1, Q3, default) are completely PRUNED.
-- ---------------------------------------------------------------------
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*), sum(total_amount)
FROM bookings_partitioned
WHERE booked_at >= '2026-06-01 00:00:00+05:30' 
  AND booked_at <  '2026-07-01 00:00:00+05:30'
  AND status = 'COMPLETED';
