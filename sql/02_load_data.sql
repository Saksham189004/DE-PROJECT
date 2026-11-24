-- =====================================================================
-- MakeMyTrip Travel Booking Database: Data Ingestion (Phase 2)
-- Loads all 12 seed data CSVs in foreign key dependency order
-- =====================================================================

SET search_path TO mmt;

\copy airports FROM 'seed_data/airports.csv' WITH (FORMAT csv, HEADER true)
\copy airlines FROM 'seed_data/airlines.csv' WITH (FORMAT csv, HEADER true)
\copy customers FROM 'seed_data/customers.csv' WITH (FORMAT csv, HEADER true)
\copy coupons FROM 'seed_data/coupons.csv' WITH (FORMAT csv, HEADER true)
\copy hotels FROM 'seed_data/hotels.csv' WITH (FORMAT csv, HEADER true)
\copy room_types FROM 'seed_data/room_types.csv' WITH (FORMAT csv, HEADER true)
\copy flights FROM 'seed_data/flights.csv' WITH (FORMAT csv, HEADER true)
\copy bookings FROM 'seed_data/bookings.csv' WITH (FORMAT csv, HEADER true)
\copy flight_bookings FROM 'seed_data/flight_bookings.csv' WITH (FORMAT csv, HEADER true)
\copy passengers FROM 'seed_data/passengers.csv' WITH (FORMAT csv, HEADER true)
\copy hotel_bookings FROM 'seed_data/hotel_bookings.csv' WITH (FORMAT csv, HEADER true)
\copy hotel_reviews FROM 'seed_data/hotel_reviews.csv' WITH (FORMAT csv, HEADER true)

ANALYZE;
