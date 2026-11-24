# Phase 3: Baseline Query Timings (Seed Dataset)

## 1. Benchmarking Methodology
All 30 queries (`R01`–`R25` reads and `W01`–`W05` writes) from `queries/workload_30.sql` were benchmarked using the standard automated evaluation harness `./benchmarks/run_benchmark.sh mmt_db baseline`.
- **Environment**: PostgreSQL 16.16 running in isolated container `mmt-pg` on Apple Silicon.
- **Repetitions**: Every query was executed **3 consecutive times** with `EXPLAIN (ANALYZE, BUFFERS)` to collect exact kernel execution times and buffer hit ratios.
- **Isolation**: Write transactions (`W01`–`W05`) were executed inside atomic `BEGIN ... ROLLBACK` blocks ensuring data immutability across iterations.
- **Storage State**: Untuned natural heap tables with only PRIMARY KEY and UNIQUE implicit b-tree indexes. Zero secondary indexes.

---

## 2. Baseline Timing Table

| SQL Query | Type | Run 1 (ms) | Run 2 (ms) | Run 3 (ms) | Average (ms) |
|:---|:---|---:|---:|---:|---:|
| **R01**: Flight search: Delhi → Mumbai on 5 July 2026 with seats left | READ | 9.784 | 6.779 | 6.590 | 7.718 |
| **R02**: Fare calendar: cheapest Bengaluru → Delhi fare for each day of July 2026 | READ | 0.622 | 0.624 | 0.602 | 0.616 |
| **R03**: Hotel search: 4★+ hotels in Goa with a swimming pool, best rated first | READ | 0.340 | 0.208 | 0.213 | 0.254 |
| **R04**: Room availability: rooms left per room type of hotel 208 for 10–12 July 2026 | READ | 2.021 | 1.884 | 1.946 | 1.950 |
| **R05**: "My Trips": customer 1021's upcoming confirmed trips | READ | 9.048 | 6.270 | 6.158 | 7.159 |
| **R06**: Support: open a booking by its reference | READ | 0.043 | 0.034 | 0.040 | 0.039 |
| **R07**: Airline manifest: passengers on flight 13047 ordered by seat | READ | 2.037 | 1.870 | 1.928 | 1.945 |
| **R08**: Revenue management: July 2026 flights with fewer than 5 passengers booked | READ | 7.101 | 7.274 | 7.127 | 7.167 |
| **R09**: Trends: 10 most-booked routes in June 2026 | READ | 13.532 | 13.461 | 13.589 | 13.527 |
| **R10**: Flight status board: delayed flights | READ | 0.640 | 0.656 | 0.651 | 0.649 |
| **R11**: Payments: bookings waiting for payment for more than 30 minutes | READ | 5.516 | 5.440 | 5.254 | 5.403 |
| **R12**: Finance: revenue per booking type per month in 2026 (excluding cancellations) | READ | 15.224 | 15.427 | 15.490 | 15.380 |
| **R13**: Marketing: coupons that have never been used | READ | 13.943 | 14.084 | 14.022 | 14.016 |
| **R14**: Airline partnerships: cancellation rate of flight bookings per airline | READ | 31.997 | 31.433 | 31.506 | 31.645 |
| **R15**: Hotel partnerships: room-nights sold per city for stays in June 2026 | READ | 16.805 | 16.472 | 16.453 | 16.577 |
| **R16**: Insights: average days between booking and travel, per booking type and loyalty tier | READ | 65.467 | 66.653 | 67.783 | 66.634 |
| **R17**: Loyalty: customers with 3 or more completed trips that started in 2026 | READ | 20.424 | 19.581 | 19.208 | 19.738 |
| **R18**: Hotel page: Goa reviews that mention breakfast | READ | 4.479 | 3.795 | 3.912 | 4.062 |
| **R19**: Operations: passengers booked on every flight departing in June 2026 | READ | 999.565 | 962.049 | 951.901 | 971.172 |
| **R20**: Finance: bookings per day and running total for June 2026 | READ | 6.416 | 6.095 | 5.871 | 6.127 |
| **R21**: Concessions: senior-citizen passengers (60+) per route in 2026 | READ | 21.058 | 18.220 | 18.288 | 19.189 |
| **R22**: Support console: all bookings, newest first, page 4,001 (25 per page) | READ | 34.310 | 34.581 | 34.622 | 34.504 |
| **R23**: Sign-in: find the customer by email, ignoring case | READ | 8.502 | 8.191 | 8.144 | 8.279 |
| **R24**: Hotel ranking: Goa hotels with at least 5 reviews, by average review rating | READ | 1.801 | 1.841 | 1.780 | 1.807 |
| **R25**: Insights: last-minute flight bookings (< 24 hours before departure) in 2026 | READ | 20.793 | 20.056 | 20.437 | 20.429 |
| **W01**: Checkout: create a pending flight booking for customer 1021 | WRITE | 0.497 | 0.429 | 0.384 | 0.437 |
| **W02**: Payment gateway callback: confirm the oldest booking waiting for payment | WRITE | 11.747 | 10.101 | 10.404 | 10.751 |
| **W03**: Customer cancels booking MMA7772F with a 70% refund | WRITE | 0.303 | 0.248 | 0.181 | 0.244 |
| **W04**: Flight ops: every flight scheduled before 1 July 2026 has departed | WRITE | 0.995 | 1.016 | 0.965 | 0.992 |
| **W05**: Front desk: assign room numbers to guests checking in on 1 July 2026 | WRITE | 3.287 | 2.660 | 2.157 | 2.701 |
| **Total (sum of all 30)** | | | | | **1291.111** |

---

## 3. Plan Scan Analysis & Performance Root Causes

| Query | Primary Scan Types in Plan | Root Cause Analysis (Why it is slow or fast) |
|:---|:---|:---|
| **R01** | `Seq Scan on flight_bookings`, `Seq Scan on flights`, `Index Scan on bookings_pkey` | Moderate (7.7 ms). Non-sargable expression `DATE(f.departure_at)` forces full scan on `flights`, followed by full scan of `flight_bookings` to compute seat sums. |
| **R02** | `Seq Scan on flights` | Fast (0.6 ms). Dataset contains only 13,848 flights, so in-memory seq scan is fast, but non-sargable `::date` prevents future b-tree index usage. |
| **R03** | `Seq Scan on hotels` | Fast (0.25 ms). Table has only 3,000 rows, but JSON text extraction `amenities ->> 'pool'` requires on-the-fly deserialization of every row. |
| **R04** | `Seq Scan on hotel_bookings`, `Seq Scan on room_types`, `Index Scan on bookings_pkey` | Moderate (1.95 ms). Full scan of `hotel_bookings` (59k rows) to aggregate room occupancy over date range. |
| **R05** | `Seq Scan on bookings`, `Index Scan on flight_bookings_pkey, flights_pkey, hotel_bookings_pkey` | Slow for OLTP (7.2 ms). Missing index on `bookings(customer_id, status)` forces sequential scan of 144k rows to find customer 1021's records. |
| **R06** | `Index Scan using bookings_booking_ref_key on bookings` | Extremely fast (0.039 ms). Directly utilizes implicit unique B-tree index on candidate key `booking_ref`. |
| **R07** | `Seq Scan on flight_bookings`, `Index Scan on bookings_pkey, passengers_pkey` | Moderate (1.95 ms). Missing foreign key index on `flight_bookings(flight_id)` forces seq scan of 84k rows to find flight 13047. |
| **R08** | `Seq Scan on flight_bookings`, `Seq Scan on flights` | Slow (7.2 ms). Dual full sequential scans over `flights` and `flight_bookings` to filter July 2026 scheduled flights. |
| **R09** | `Seq Scan on flight_bookings`, `Seq Scan on bookings`, `Seq Scan on flights` | Slow (13.5 ms). Joins three large tables using sequential scans and hash joins to filter by `booked_at` range. |
| **R10** | `Seq Scan on flights` | Fast (0.65 ms). Full scan of 13k flights; status `'DELAYED'` is rare and would benefit drastically from a partial index. |
| **R11** | `Seq Scan on bookings` | Slow for OLTP (5.4 ms). Scans all 144k bookings to find the small handful of pending payment rows older than 30 minutes. |
| **R12** | `Seq Scan on bookings` | Analytical (15.4 ms). Sequential scan of 144k rows evaluating non-sargable `EXTRACT(YEAR FROM booked_at)`. |
| **R13** | `Seq Scan on coupons`, `Seq Scan on bookings` | Analytical & Bugged (14.0 ms). Evaluates subplan over 144k bookings; returns 0 rows due to SQL 3-valued boolean logic on NULL coupon codes. |
| **R14** | `Seq Scan on bookings`, `Seq Scan on flight_bookings`, `Seq Scan on flights`, `Seq Scan on airlines` | Analytical (31.6 ms). Four-table hash join across 144k bookings to compute airline cancellation ratios. |
| **R15** | `Seq Scan on bookings`, `Seq Scan on hotel_bookings`, `Seq Scan on hotels` | Analytical (16.6 ms). Sequential scan of 59k hotel bookings and 144k bookings to compute room-night overlap. |
| **R16** | `Seq Scan on bookings, customers, flight_bookings, flights, hotel_bookings` | Very Slow (66.6 ms). Five-table hash join across 40k customers and 144k bookings computing lead time arithmetic. |
| **R17** | `Seq Scan on bookings` | Analytical (19.7 ms). Sequential scan and hash aggregation across 144k rows filtering completed 2026 bookings. |
| **R18** | `Seq Scan on hotel_reviews`, `Seq Scan on hotels` | Slow (4.1 ms). Substring regex pattern match `ILIKE '%breakfast%'` scans all 15k review texts sequentially. |
| **R19** | `Seq Scan on flights`, `Seq Scan on flight_bookings`, `Index Only Scan on passengers_pkey` | Critical Bottleneck (971.2 ms). Correlated scalar subquery in SELECT clause executes 960 times—once for every flight in June 2026. |
| **R20** | `Seq Scan on bookings` | Moderate (6.1 ms). Full scan of 144k bookings evaluating date casting `booked_at::date` followed by window aggregation. |
| **R21** | `Seq Scan on passengers`, `Seq Scan on flight_bookings`, `Seq Scan on flights` | Analytical (19.2 ms). Scans 163k passenger records to filter seniors (`age >= 60`) followed by hash join. |
| **R22** | `Seq Scan on bookings` | High Latency (34.5 ms). Classic deep pagination problem; scans, sorts, and discards 100,000 rows to return 25 rows. |
| **R23** | `Seq Scan on customers` | Slow for OLTP (8.3 ms). Function `lower(email)` bypasses the standard b-tree index on `email`, scanning all 40,000 customer accounts. |
| **R24** | `Seq Scan on hotel_reviews`, `Seq Scan on hotels` | Moderate (1.8 ms). Scans all reviews and joins hotels to calculate average property ratings. |
| **R25** | `Seq Scan on flight_bookings`, `Seq Scan on bookings`, `Seq Scan on flights` | Analytical (20.4 ms). Scans both bookings and flights to compute cross-table timestamp subtraction `< interval '24 hours'`. |
| **W01** | `(no scan)` | Instantaneous (0.44 ms). Plain single-row tuple insert into heap with primary key b-tree insertion. |
| **W02** | `Index Scan using bookings_pkey on bookings` | Latency Spike (10.75 ms). Subquery `(SELECT min(booking_id) FROM bookings WHERE status = 'PENDING_PAYMENT')` performs full sequential scan of 144k bookings. |
| **W03** | `Index Scan using bookings_booking_ref_key on bookings` | Fast (0.24 ms). Single-row lookup and in-place update using unique index on `booking_ref`. |
| **W04** | `Seq Scan on flights` | Moderate (0.99 ms). Scans 13k flights to update status of scheduled departures before cutoff. |
| **W05** | `Seq Scan on hotel_bookings`, `Index Scan on bookings_pkey on bookings` | Moderate (2.70 ms). Scans 59k hotel bookings joining on `bookings` to populate room numbers. |
