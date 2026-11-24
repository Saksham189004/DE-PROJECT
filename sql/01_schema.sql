-- =====================================================================
-- MakeMyTrip Travel Booking Database: Schema Design (Phase 2)
-- Schema: mmt
-- Constraints only (PK, FK, UNIQUE, NOT NULL, CHECK)
-- NO secondary indexes (to ensure pure untuned baseline for Phase 3)
-- =====================================================================

CREATE SCHEMA IF NOT EXISTS mmt;
SET search_path TO mmt;

-- Drop existing tables in reverse dependency order
DROP TABLE IF EXISTS hotel_reviews CASCADE;
DROP TABLE IF EXISTS hotel_bookings CASCADE;
DROP TABLE IF EXISTS passengers CASCADE;
DROP TABLE IF EXISTS flight_bookings CASCADE;
DROP TABLE IF EXISTS bookings CASCADE;
DROP TABLE IF EXISTS coupons CASCADE;
DROP TABLE IF EXISTS customers CASCADE;
DROP TABLE IF EXISTS room_types CASCADE;
DROP TABLE IF EXISTS hotels CASCADE;
DROP TABLE IF EXISTS flights CASCADE;
DROP TABLE IF EXISTS airlines CASCADE;
DROP TABLE IF EXISTS airports CASCADE;

-- ---------------------------------------------------------------------
-- 1. Airports
-- Master lookup of airports identified by 3-letter IATA codes
-- ---------------------------------------------------------------------
CREATE TABLE airports (
    iata_code       CHAR(3) PRIMARY KEY,
    airport_name    VARCHAR(150) NOT NULL,
    city_name       VARCHAR(100) NOT NULL,
    country_code    CHAR(2) NOT NULL DEFAULT 'IN',
    CONSTRAINT airports_iata_code_format_chk CHECK (iata_code ~ '^[A-Z]{3}$'),
    CONSTRAINT airports_country_code_format_chk CHECK (country_code ~ '^[A-Z]{2}$')
);

-- ---------------------------------------------------------------------
-- 2. Airlines
-- Master lookup of airlines identified by 2-character IATA airline codes
-- ---------------------------------------------------------------------
CREATE TABLE airlines (
    airline_code    CHAR(2) PRIMARY KEY,
    airline_name    VARCHAR(100) NOT NULL,
    CONSTRAINT airlines_code_format_chk CHECK (airline_code ~ '^[A-Z0-9]{2}$')
);

-- ---------------------------------------------------------------------
-- 3. Flights
-- Specific dated flight instances scheduled between two distinct airports
-- ---------------------------------------------------------------------
CREATE TABLE flights (
    flight_id       INTEGER PRIMARY KEY,
    airline_code    CHAR(2) NOT NULL REFERENCES airlines(airline_code) ON DELETE RESTRICT,
    flight_no       VARCHAR(20) NOT NULL,
    origin          CHAR(3) NOT NULL REFERENCES airports(iata_code) ON DELETE RESTRICT,
    destination     CHAR(3) NOT NULL REFERENCES airports(iata_code) ON DELETE RESTRICT,
    departure_at    TIMESTAMPTZ NOT NULL,
    arrival_at      TIMESTAMPTZ NOT NULL,
    aircraft        VARCHAR(50) NOT NULL,
    total_seats     INTEGER NOT NULL,
    base_fare       NUMERIC(10,2) NOT NULL,
    status          VARCHAR(20) NOT NULL,
    CONSTRAINT flights_route_distinct_chk CHECK (origin <> destination),
    CONSTRAINT flights_chronology_chk CHECK (arrival_at > departure_at),
    CONSTRAINT flights_seats_positive_chk CHECK (total_seats > 0),
    CONSTRAINT flights_base_fare_positive_chk CHECK (base_fare > 0),
    CONSTRAINT flights_status_valid_chk CHECK (status IN ('SCHEDULED', 'DELAYED', 'DEPARTED', 'LANDED', 'CANCELLED'))
);

-- ---------------------------------------------------------------------
-- 4. Hotels
-- Accommodations catalog with star rating, user rating, and JSONB amenities
-- ---------------------------------------------------------------------
CREATE TABLE hotels (
    hotel_id        INTEGER PRIMARY KEY,
    hotel_name      VARCHAR(200) NOT NULL,
    city_name       VARCHAR(100) NOT NULL,
    star_rating     INTEGER NOT NULL,
    user_rating     NUMERIC(2,1) NULL,
    amenities       JSONB NOT NULL,
    check_in_time   TIME NOT NULL,
    check_out_time  TIME NOT NULL,
    CONSTRAINT hotels_star_rating_range_chk CHECK (star_rating BETWEEN 1 AND 5),
    CONSTRAINT hotels_user_rating_range_chk CHECK (user_rating IS NULL OR (user_rating >= 0.0 AND user_rating <= 5.0))
);

-- ---------------------------------------------------------------------
-- 5. Room Types
-- Room configurations belonging to hotels with inventory and nightly rates
-- ---------------------------------------------------------------------
CREATE TABLE room_types (
    room_type_id    INTEGER PRIMARY KEY,
    hotel_id        INTEGER NOT NULL REFERENCES hotels(hotel_id) ON DELETE CASCADE,
    room_name       VARCHAR(100) NOT NULL,
    max_guests      INTEGER NOT NULL,
    price_per_night NUMERIC(10,2) NOT NULL,
    total_rooms     INTEGER NOT NULL,
    CONSTRAINT room_types_max_guests_chk CHECK (max_guests > 0),
    CONSTRAINT room_types_price_positive_chk CHECK (price_per_night > 0),
    CONSTRAINT room_types_total_rooms_positive_chk CHECK (total_rooms > 0)
);

-- ---------------------------------------------------------------------
-- 6. Customers
-- MakeMyTrip users with unique email/phone contacts and loyalty tier
-- ---------------------------------------------------------------------
CREATE TABLE customers (
    customer_id     INTEGER PRIMARY KEY,
    full_name       VARCHAR(150) NOT NULL,
    email           VARCHAR(255) NOT NULL UNIQUE,
    phone           VARCHAR(20) NOT NULL UNIQUE,
    loyalty_tier    VARCHAR(20) NOT NULL,
    created_at      TIMESTAMPTZ NOT NULL,
    CONSTRAINT customers_loyalty_tier_chk CHECK (loyalty_tier IN ('BLUE', 'SILVER', 'GOLD', 'PLATINUM')),
    CONSTRAINT customers_email_format_chk CHECK (email ~* '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$')
);

-- ---------------------------------------------------------------------
-- 7. Coupons
-- Promotional discount vouchers applicable to flights, hotels, or both
-- ---------------------------------------------------------------------
CREATE TABLE coupons (
    coupon_code     VARCHAR(30) PRIMARY KEY,
    applies_to      VARCHAR(20) NOT NULL,
    discount_pct    NUMERIC(5,2) NOT NULL,
    max_discount    NUMERIC(10,2) NOT NULL,
    valid_from      DATE NOT NULL,
    valid_to        DATE NOT NULL,
    CONSTRAINT coupons_applies_to_chk CHECK (applies_to IN ('FLIGHT', 'HOTEL', 'ALL')),
    CONSTRAINT coupons_discount_pct_range_chk CHECK (discount_pct > 0 AND discount_pct <= 100),
    CONSTRAINT coupons_max_discount_non_negative_chk CHECK (max_discount >= 0),
    CONSTRAINT coupons_validity_window_chk CHECK (valid_to >= valid_from)
);

-- ---------------------------------------------------------------------
-- 8. Bookings
-- Master order entity for flight journeys and hotel reservations
-- ---------------------------------------------------------------------
CREATE TABLE bookings (
    booking_id      INTEGER PRIMARY KEY,
    booking_ref     VARCHAR(20) NOT NULL UNIQUE,
    customer_id     INTEGER NOT NULL REFERENCES customers(customer_id) ON DELETE RESTRICT,
    booking_type    VARCHAR(20) NOT NULL,
    booked_at       TIMESTAMPTZ NOT NULL,
    total_amount    NUMERIC(10,2) NOT NULL,
    coupon_code     VARCHAR(30) NULL REFERENCES coupons(coupon_code) ON DELETE SET NULL,
    discount        NUMERIC(10,2) NOT NULL DEFAULT 0.00,
    payment_method  VARCHAR(20) NOT NULL,
    status          VARCHAR(30) NOT NULL,
    cancelled_at    TIMESTAMPTZ NULL,
    refund_amount   NUMERIC(10,2) NULL,
    CONSTRAINT bookings_type_valid_chk CHECK (booking_type IN ('FLIGHT', 'HOTEL')),
    CONSTRAINT bookings_payment_method_valid_chk CHECK (payment_method IN ('CARD', 'NETBANKING', 'UPI', 'WALLET', 'EMI')),
    CONSTRAINT bookings_status_valid_chk CHECK (status IN ('PENDING_PAYMENT', 'CONFIRMED', 'COMPLETED', 'CANCELLED')),
    CONSTRAINT bookings_total_amount_non_negative_chk CHECK (total_amount >= 0),
    CONSTRAINT bookings_discount_non_negative_chk CHECK (discount >= 0),
    CONSTRAINT bookings_cancellation_consistency_chk CHECK (
        (status = 'CANCELLED' AND cancelled_at IS NOT NULL) OR 
        (status <> 'CANCELLED' AND cancelled_at IS NULL)
    ),
    CONSTRAINT bookings_refund_consistency_chk CHECK (
        (status = 'CANCELLED' AND refund_amount IS NOT NULL AND refund_amount <= total_amount AND refund_amount >= 0) OR 
        (status <> 'CANCELLED' AND refund_amount IS NULL)
    ),
    CONSTRAINT bookings_coupon_discount_chk CHECK (
        (discount = 0.00) OR 
        (discount > 0.00 AND coupon_code IS NOT NULL)
    )
);

-- ---------------------------------------------------------------------
-- 9. Flight Bookings
-- 1:1 specialization of bookings holding flight sector details
-- ---------------------------------------------------------------------
CREATE TABLE flight_bookings (
    booking_id      INTEGER PRIMARY KEY REFERENCES bookings(booking_id) ON DELETE CASCADE,
    flight_id       INTEGER NOT NULL REFERENCES flights(flight_id) ON DELETE RESTRICT,
    cabin           VARCHAR(20) NOT NULL,
    passengers      INTEGER NOT NULL,
    fare_paid       NUMERIC(10,2) NOT NULL,
    CONSTRAINT flight_bookings_cabin_valid_chk CHECK (cabin IN ('ECONOMY', 'PREMIUM', 'BUSINESS')),
    CONSTRAINT flight_bookings_passengers_positive_chk CHECK (passengers > 0),
    CONSTRAINT flight_bookings_fare_non_negative_chk CHECK (fare_paid >= 0)
);

-- ---------------------------------------------------------------------
-- 10. Passengers
-- Individual passenger details tied to a flight booking (composite PK)
-- ---------------------------------------------------------------------
CREATE TABLE passengers (
    booking_id      INTEGER NOT NULL REFERENCES bookings(booking_id) ON DELETE CASCADE,
    seq_no          INTEGER NOT NULL,
    full_name       VARCHAR(150) NOT NULL,
    age             INTEGER NOT NULL,
    gender          CHAR(1) NOT NULL,
    seat_no         VARCHAR(10) NULL,
    PRIMARY KEY (booking_id, seq_no),
    CONSTRAINT passengers_seq_no_positive_chk CHECK (seq_no > 0),
    CONSTRAINT passengers_age_range_chk CHECK (age >= 0 AND age <= 125),
    CONSTRAINT passengers_gender_valid_chk CHECK (gender IN ('M', 'F', 'X'))
);

-- ---------------------------------------------------------------------
-- 11. Hotel Bookings
-- 1:1 specialization of bookings holding hotel stay duration & room counts
-- ---------------------------------------------------------------------
CREATE TABLE hotel_bookings (
    booking_id      INTEGER PRIMARY KEY REFERENCES bookings(booking_id) ON DELETE CASCADE,
    hotel_id        INTEGER NOT NULL REFERENCES hotels(hotel_id) ON DELETE RESTRICT,
    room_type_id    INTEGER NOT NULL REFERENCES room_types(room_type_id) ON DELETE RESTRICT,
    check_in        DATE NOT NULL,
    check_out       DATE NOT NULL,
    rooms           INTEGER NOT NULL,
    guests          INTEGER NOT NULL,
    room_number     VARCHAR(20) NULL,
    CONSTRAINT hotel_bookings_dates_chronology_chk CHECK (check_out > check_in),
    CONSTRAINT hotel_bookings_rooms_positive_chk CHECK (rooms > 0),
    CONSTRAINT hotel_bookings_guests_positive_chk CHECK (guests > 0)
);

-- ---------------------------------------------------------------------
-- 12. Hotel Reviews
-- Feedback and customer ratings for completed hotel stays
-- ---------------------------------------------------------------------
CREATE TABLE hotel_reviews (
    review_id       INTEGER PRIMARY KEY,
    booking_id      INTEGER NOT NULL REFERENCES bookings(booking_id) ON DELETE CASCADE,
    hotel_id        INTEGER NOT NULL REFERENCES hotels(hotel_id) ON DELETE CASCADE,
    rating          INTEGER NOT NULL,
    title           VARCHAR(255) NOT NULL,
    review_text     TEXT NULL,
    created_at      TIMESTAMPTZ NOT NULL,
    CONSTRAINT hotel_reviews_rating_range_chk CHECK (rating BETWEEN 1 AND 5)
);
