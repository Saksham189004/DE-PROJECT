-- =====================================================================
-- MakeMyTrip Travel Booking Database: Data Ingestion (Phase 2 & Phase 5)
-- Loads dataset CSVs in foreign key dependency order.
-- Default configured for large_data (10.4M rows) as provided.
-- =====================================================================

SET search_path TO mmt;

\copy airports FROM 'large_data/airports.csv' WITH (FORMAT csv, HEADER true)
\copy airlines FROM 'large_data/airlines.csv' WITH (FORMAT csv, HEADER true)
\copy customers FROM 'large_data/customers.csv' WITH (FORMAT csv, HEADER true)
\copy coupons FROM 'large_data/coupons.csv' WITH (FORMAT csv, HEADER true)
\copy hotels FROM 'large_data/hotels.csv' WITH (FORMAT csv, HEADER true)
\copy room_types FROM 'large_data/room_types.csv' WITH (FORMAT csv, HEADER true)
\copy flights FROM 'large_data/flights.csv' WITH (FORMAT csv, HEADER true)
\copy bookings FROM 'large_data/bookings.csv' WITH (FORMAT csv, HEADER true)
\copy flight_bookings FROM 'large_data/flight_bookings.csv' WITH (FORMAT csv, HEADER true)
\copy passengers FROM 'large_data/passengers.csv' WITH (FORMAT csv, HEADER true)
\copy hotel_bookings FROM 'large_data/hotel_bookings.csv' WITH (FORMAT csv, HEADER true)
\copy hotel_reviews FROM 'large_data/hotel_reviews.csv' WITH (FORMAT csv, HEADER true)

ANALYZE;
