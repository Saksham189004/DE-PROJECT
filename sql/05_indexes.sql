-- =====================================================================
-- MakeMyTrip Travel Booking Database: Performance Indexing (Phase 4)
-- Schema: mmt
-- Optimized B-Tree, Partial, Covering, Expression, and GIN Trigram Indexes
-- =====================================================================

SET search_path TO mmt, public;

-- Enable trigram extension for substring text searches
CREATE EXTENSION IF NOT EXISTS pg_trgm WITH SCHEMA public;

-- ---------------------------------------------------------------------
-- 1. FLIGHT SEARCH & FARE CALENDAR (Serves R01, R02)
-- Composite B-Tree index on (origin, destination, departure_at).
-- Column order: equality predicates (origin, destination) first to narrow
-- candidate flight partitions, then range predicate (departure_at) for
-- leaf-page b-tree range traversal.
-- ---------------------------------------------------------------------
DROP INDEX IF EXISTS idx_flights_route_depart;
CREATE INDEX idx_flights_route_depart 
ON flights(origin, destination, departure_at) 
INCLUDE (flight_id, flight_no, arrival_at, base_fare, total_seats, status);

-- ---------------------------------------------------------------------
-- 2. FLIGHT STATUS & REVENUE MANAGEMENT (Serves R08, R10, W04)
-- Partial indexes on flights:
-- Rare statuses (DELAYED, SCHEDULED) comprise a small fraction of the table.
-- Indexing only target status values minimizes index footprint and write overhead.
-- ---------------------------------------------------------------------
DROP INDEX IF EXISTS idx_flights_delayed;
CREATE INDEX idx_flights_delayed 
ON flights(departure_at) 
INCLUDE (flight_id, flight_no, origin, destination) 
WHERE status = 'DELAYED';

DROP INDEX IF EXISTS idx_flights_sched_depart;
CREATE INDEX idx_flights_sched_depart 
ON flights(departure_at) 
INCLUDE (flight_id, flight_no) 
WHERE status = 'SCHEDULED';

DROP INDEX IF EXISTS idx_flights_depart_cutoff;
CREATE INDEX idx_flights_depart_cutoff 
ON flights(departure_at) 
WHERE status IN ('SCHEDULED', 'DELAYED');

-- ---------------------------------------------------------------------
-- 3. FLIGHT BOOKINGS LOOKUPS & JOINS (Serves R01, R07, R08, R09, R14, R19, R21, R25)
-- Foreign key covering index on flight_bookings(flight_id).
-- PostgreSQL does not automatically index FK columns. Including booking_id
-- and passengers enables Index Only Scans for seat sums and manifests.
-- ---------------------------------------------------------------------
DROP INDEX IF EXISTS idx_flight_bookings_flight_id;
CREATE INDEX idx_flight_bookings_flight_id 
ON flight_bookings(flight_id) 
INCLUDE (booking_id, passengers, cabin);

-- ---------------------------------------------------------------------
-- 4. HOTEL SEARCH & AMENITY FILTERING (Serves R03, R15, R18, R24)
-- Partial composite index for 4+ star hotels in Goa with pool amenities.
-- Eliminates seq scan and sorts via pre-ordered b-tree on user_rating DESC.
-- ---------------------------------------------------------------------
DROP INDEX IF EXISTS idx_hotels_goa_pool;
CREATE INDEX idx_hotels_goa_pool 
ON hotels(star_rating, user_rating DESC NULLS LAST) 
INCLUDE (hotel_id, hotel_name) 
WHERE city_name = 'Goa' AND (amenities ->> 'pool' = 'true');

DROP INDEX IF EXISTS idx_hotels_city_id;
CREATE INDEX idx_hotels_city_id 
ON hotels(city_name) 
INCLUDE (hotel_id, hotel_name);

-- ---------------------------------------------------------------------
-- 5. ROOM AVAILABILITY & STAYS (Serves R04, R15, W05)
-- Covering index on room_types for hotel lookup and inventory data.
-- Range index on hotel_bookings for date overlap checks.
-- ---------------------------------------------------------------------
DROP INDEX IF EXISTS idx_room_types_hotel_id;
CREATE INDEX idx_room_types_hotel_id 
ON room_types(hotel_id) 
INCLUDE (room_type_id, room_name, price_per_night, total_rooms);

DROP INDEX IF EXISTS idx_hotel_bookings_room_dates;
CREATE INDEX idx_hotel_bookings_room_dates 
ON hotel_bookings(room_type_id, check_in, check_out) 
INCLUDE (booking_id, rooms);

DROP INDEX IF EXISTS idx_hotel_bookings_dates;
CREATE INDEX idx_hotel_bookings_dates 
ON hotel_bookings(check_in, check_out) 
INCLUDE (hotel_id, rooms, booking_id);

DROP INDEX IF EXISTS idx_hotel_bookings_checkin_unassigned;
CREATE INDEX idx_hotel_bookings_checkin_unassigned 
ON hotel_bookings(check_in, booking_id) 
WHERE room_number IS NULL;

-- ---------------------------------------------------------------------
-- 6. CUSTOMER AUTHENTICATION (Serves R23)
-- Functional Expression Index on lower(email).
-- Matches WHERE lower(email) = '...' predicate exactly, converting a 40k row
-- full sequential scan into an instantaneous Index Only Scan.
-- ---------------------------------------------------------------------
DROP INDEX IF EXISTS idx_customers_lower_email;
CREATE INDEX idx_customers_lower_email 
ON customers(lower(email)) 
INCLUDE (customer_id, full_name, loyalty_tier);

-- ---------------------------------------------------------------------
-- 7. CUSTOMER PORTAL & TRIPS (Serves R05, R16, R17)
-- Composite index on bookings(customer_id, status) with covering payload.
-- Drastically accelerates "My Trips" itinerary retrieval for account dashboards.
-- ---------------------------------------------------------------------
DROP INDEX IF EXISTS idx_bookings_customer_status;
CREATE INDEX idx_bookings_customer_status 
ON bookings(customer_id, status) 
INCLUDE (booking_id, booking_ref, booking_type, total_amount, booked_at);

DROP INDEX IF EXISTS idx_bookings_customer_completed;
CREATE INDEX idx_bookings_customer_completed 
ON bookings(customer_id, booked_at) 
INCLUDE (total_amount) 
WHERE status = 'COMPLETED';

-- ---------------------------------------------------------------------
-- 8. CHECKOUT & PAYMENT QUEUES (Serves R11, W02)
-- Partial index on pending payment bookings.
-- Only active unpaid orders are indexed, providing sub-millisecond retrieval
-- for oldest pending order resolution and payment timeout worker jobs.
-- ---------------------------------------------------------------------
DROP INDEX IF EXISTS idx_bookings_pending_payment;
CREATE INDEX idx_bookings_pending_payment 
ON bookings(booked_at, booking_id) 
WHERE status = 'PENDING_PAYMENT';

DROP INDEX IF EXISTS idx_bookings_pending_payment_id;
CREATE INDEX idx_bookings_pending_payment_id 
ON bookings(booking_id) 
WHERE status = 'PENDING_PAYMENT';

-- ---------------------------------------------------------------------
-- 9. FINANCIAL REPORTING & ANALYTICS (Serves R09, R12, R20, R22, R25)
-- Partial covering indexes on active/completed bookings for date aggregations.
-- Index on booked_at DESC for deep support console pagination (R22).
-- ---------------------------------------------------------------------
DROP INDEX IF EXISTS idx_bookings_booked_at_active;
CREATE INDEX idx_bookings_booked_at_active 
ON bookings(booked_at, booking_type) 
INCLUDE (total_amount) 
WHERE status <> 'CANCELLED';

DROP INDEX IF EXISTS idx_bookings_booked_at_flight;
CREATE INDEX idx_bookings_booked_at_flight 
ON bookings(booked_at) 
INCLUDE (booking_id) 
WHERE booking_type = 'FLIGHT';

DROP INDEX IF EXISTS idx_bookings_booked_at_desc;
CREATE INDEX idx_bookings_booked_at_desc 
ON bookings(booked_at DESC) 
INCLUDE (booking_id, booking_ref, booking_type, status, total_amount);

DROP INDEX IF EXISTS idx_bookings_coupon_code;
CREATE INDEX idx_bookings_coupon_code 
ON bookings(coupon_code) 
WHERE coupon_code IS NOT NULL;

-- ---------------------------------------------------------------------
-- 10. REVIEWS & PASSENGER MANIFESTS (Serves R07, R18, R19, R21, R24)
-- GIN Trigram index on hotel_reviews(review_text) for fast ILIKE pattern matching.
-- Covering foreign key index on passengers(booking_id) for manifests and senior concessions.
-- ---------------------------------------------------------------------
DROP INDEX IF EXISTS idx_hotel_reviews_hotel_rating;
CREATE INDEX idx_hotel_reviews_hotel_rating 
ON hotel_reviews(hotel_id) 
INCLUDE (rating);

DROP INDEX IF EXISTS idx_hotel_reviews_trgm;
CREATE INDEX idx_hotel_reviews_trgm 
ON hotel_reviews USING gin (review_text gin_trgm_ops);

DROP INDEX IF EXISTS idx_passengers_booking_id;
CREATE INDEX idx_passengers_booking_id 
ON passengers(booking_id) 
INCLUDE (seq_no, full_name, age, gender, seat_no);

DROP INDEX IF EXISTS idx_passengers_seniors;
CREATE INDEX idx_passengers_seniors 
ON passengers(booking_id) 
WHERE age >= 60;

VACUUM ANALYZE;
