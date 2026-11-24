# Phase 2: Schema Design, Normalization & Ingestion

## 1. Overview & Architecture
The MakeMyTrip relational database is structured in PostgreSQL 16 under the dedicated schema `mmt` (`SET search_path TO mmt;`). The schema is reconstructed directly from production data exports and enforces strict primary keys, foreign keys with referential actions, uniqueness guarantees, NOT NULL constraints, and 24 domain-specific CHECK constraints.

Following strict Phase 2 guidelines, **no non-PK/non-UNIQUE secondary indexes** were created during this stage. The baseline database maintains purely natural table heap structures to establish a rigorous, untuned performance benchmark.

---

## 2. Entity Relationship Diagram

### 2.1 Visual Diagram
The high-resolution ER diagram is rendered in [er_diagram.png](../diagrams/er_diagram.png).

### 2.2 Relational Mermaid Specification
```mermaid
erDiagram
    AIRPORTS ||--o{ FLIGHTS : "originates / arrives"
    AIRLINES ||--o{ FLIGHTS : "operates"
    CUSTOMERS ||--o{ BOOKINGS : "places"
    COUPONS ||--o{ BOOKINGS : "applies_to"
    FLIGHTS ||--o{ FLIGHT_BOOKINGS : "booked_on"
    BOOKINGS ||--o| FLIGHT_BOOKINGS : "specializes_as (1:1)"
    BOOKINGS ||--o| HOTEL_BOOKINGS : "specializes_as (1:1)"
    BOOKINGS ||--o{ PASSENGERS : "manifested_for"
    HOTELS ||--o{ ROOM_TYPES : "contains"
    HOTELS ||--o{ HOTEL_BOOKINGS : "reserved_at"
    ROOM_TYPES ||--o{ HOTEL_BOOKINGS : "allocated_type"
    BOOKINGS ||--o| HOTEL_REVIEWS : "reviewed_by"
    HOTELS ||--o{ HOTEL_REVIEWS : "received_for"

    AIRPORTS {
        char(3) iata_code PK
        varchar(150) airport_name
        varchar(100) city_name
        char(2) country_code
    }
    AIRLINES {
        char(2) airline_code PK
        varchar(100) airline_name
    }
    FLIGHTS {
        int flight_id PK
        char(2) airline_code FK
        varchar(20) flight_no
        char(3) origin FK
        char(3) destination FK
        timestamptz departure_at
        timestamptz arrival_at
        varchar(50) aircraft
        int total_seats
        numeric(10,2) base_fare
        varchar(20) status
    }
    CUSTOMERS {
        int customer_id PK
        varchar(150) full_name
        varchar(255) email UQ
        varchar(20) phone UQ
        varchar(20) loyalty_tier
        timestamptz created_at
    }
    COUPONS {
        varchar(30) coupon_code PK
        varchar(20) applies_to
        numeric(5,2) discount_pct
        numeric(10,2) max_discount
        date valid_from
        date valid_to
    }
    BOOKINGS {
        int booking_id PK
        varchar(20) booking_ref UQ
        int customer_id FK
        varchar(20) booking_type
        timestamptz booked_at
        numeric(10,2) total_amount
        varchar(30) coupon_code FK
        numeric(10,2) discount
        varchar(20) payment_method
        varchar(30) status
        timestamptz cancelled_at
        numeric(10,2) refund_amount
    }
    FLIGHT_BOOKINGS {
        int booking_id PK,FK
        int flight_id FK
        varchar(20) cabin
        int passengers
        numeric(10,2) fare_paid
    }
    PASSENGERS {
        int booking_id PK,FK
        int seq_no PK
        varchar(150) full_name
        int age
        char(1) gender
        varchar(10) seat_no
    }
    HOTELS {
        int hotel_id PK
        varchar(200) hotel_name
        varchar(100) city_name
        int star_rating
        numeric(2,1) user_rating
        jsonb amenities
        time check_in_time
        time check_out_time
    }
    ROOM_TYPES {
        int room_type_id PK
        int hotel_id FK
        varchar(100) room_name
        int max_guests
        numeric(10,2) price_per_night
        int total_rooms
    }
    HOTEL_BOOKINGS {
        int booking_id PK,FK
        int hotel_id FK
        int room_type_id FK
        date check_in
        date check_out
        int rooms
        int guests
        varchar(20) room_number
    }
    HOTEL_REVIEWS {
        int review_id PK
        int booking_id FK
        int hotel_id FK
        int rating
        varchar(255) title
        text review_text
        timestamptz created_at
    }
```

---

## 3. Data Dictionary

### 3.1 `airports`
| Column | Data Type | Nullable | Constraints & References | Justification |
|:---|:---|:---|:---|:---|
| `iata_code` | `CHAR(3)` | NO | PRIMARY KEY, CHECK (`^[A-Z]{3}$`) | Standard 3-letter uppercase IATA international airport identifier. |
| `airport_name`| `VARCHAR(150)`| NO | NOT NULL | Official airport facility name. |
| `city_name` | `VARCHAR(100)`| NO | NOT NULL | Metropolitan city served by the airport. |
| `country_code`| `CHAR(2)` | NO | NOT NULL, DEFAULT `'IN'`, CHECK (`^[A-Z]{2}$`) | ISO 3166-1 alpha-2 country code. |

### 3.2 `airlines`
| Column | Data Type | Nullable | Constraints & References | Justification |
|:---|:---|:---|:---|:---|
| `airline_code` | `CHAR(2)` | NO | PRIMARY KEY, CHECK (`^[A-Z0-9]{2}$`) | Standard 2-character IATA airline code (e.g. `6E`, `AI`). |
| `airline_name` | `VARCHAR(100)`| NO | NOT NULL | Registered commercial carrier name. |

### 3.3 `flights`
| Column | Data Type | Nullable | Constraints & References | Justification |
|:---|:---|:---|:---|:---|
| `flight_id` | `INTEGER` | NO | PRIMARY KEY | Synthetic surrogate primary key for flight schedules. |
| `airline_code`| `CHAR(2)` | NO | REFERENCES `airlines(airline_code)` ON DELETE RESTRICT | Operating carrier. RESTRICT prevents deleting active airlines. |
| `flight_no` | `VARCHAR(20)` | NO | NOT NULL | Flight designator (e.g., `6E-137`, `AI-174`). |
| `origin` | `CHAR(3)` | NO | REFERENCES `airports(iata_code)` ON DELETE RESTRICT | Departure airport IATA code. |
| `destination` | `CHAR(3)` | NO | REFERENCES `airports(iata_code)` ON DELETE RESTRICT | Arrival airport IATA code; CHECK (`origin <> destination`). |
| `departure_at`| `TIMESTAMPTZ`| NO | NOT NULL | Departure timestamp with exact timezone (`+05:30`). |
| `arrival_at` | `TIMESTAMPTZ`| NO | NOT NULL, CHECK (`arrival_at > departure_at`) | Arrival timestamp with exact timezone; strictly after departure. |
| `aircraft` | `VARCHAR(50)` | NO | NOT NULL | Aircraft model variant (`A320neo`, `A321neo`, `B737-8`). |
| `total_seats` | `INTEGER` | NO | NOT NULL, CHECK (`total_seats > 0`) | Cabin seat capacity. |
| `base_fare` | `NUMERIC(10,2)`| NO | NOT NULL, CHECK (`base_fare > 0`) | Base ticket fare in INR. |
| `status` | `VARCHAR(20)` | NO | CHECK (`status IN ('SCHEDULED', 'DELAYED', 'DEPARTED', 'LANDED', 'CANCELLED')`) | Operational flight status lifecycle. |

### 3.4 `hotels`
| Column | Data Type | Nullable | Constraints & References | Justification |
|:---|:---|:---|:---|:---|
| `hotel_id` | `INTEGER` | NO | PRIMARY KEY | Unique property identifier. |
| `hotel_name` | `VARCHAR(200)`| NO | NOT NULL | Commercial lodging property name. |
| `city_name` | `VARCHAR(100)`| NO | NOT NULL | Geographic location. |
| `star_rating` | `INTEGER` | NO | CHECK (`star_rating BETWEEN 1 AND 5`) | Official government/industry classification. |
| `user_rating` | `NUMERIC(2,1)`| YES | CHECK (`user_rating BETWEEN 0.0 AND 5.0`) | Aggregated customer score (NULL when unrated). |
| `amenities` | `JSONB` | NO | NOT NULL | Binary JSON holding structured features (`pool`, `wifi`, etc.). |
| `check_in_time`| `TIME` | NO | NOT NULL | Standard check-in daily cutoff (e.g., `14:00:00`). |
| `check_out_time`| `TIME` | NO | NOT NULL | Standard check-out daily cutoff (e.g., `11:00:00`). |

### 3.5 `room_types`
| Column | Data Type | Nullable | Constraints & References | Justification |
|:---|:---|:---|:---|:---|
| `room_type_id` | `INTEGER` | NO | PRIMARY KEY | Room type tier identifier. |
| `hotel_id` | `INTEGER` | NO | REFERENCES `hotels(hotel_id)` ON DELETE CASCADE | Parent hotel property. CASCADE removes room types on hotel deletion. |
| `room_name` | `VARCHAR(100)`| NO | NOT NULL | Category name (`Standard Room`, `Deluxe Room`, `Suite`). |
| `max_guests` | `INTEGER` | NO | CHECK (`max_guests > 0`) | Maximum occupancy capacity per room. |
| `price_per_night`| `NUMERIC(10,2)`| NO | CHECK (`price_per_night > 0`) | Base room rate per night in INR. |
| `total_rooms` | `INTEGER` | NO | CHECK (`total_rooms > 0`) | Physical room inventory of this specific category. |

### 3.6 `customers`
| Column | Data Type | Nullable | Constraints & References | Justification |
|:---|:---|:---|:---|:---|
| `customer_id` | `INTEGER` | NO | PRIMARY KEY | Unique user account identifier. |
| `full_name` | `VARCHAR(150)`| NO | NOT NULL | Customer legal name. |
| `email` | `VARCHAR(255)`| NO | UNIQUE, CHECK (email format) | Primary login identifier. UNIQUE enforces single account per email. |
| `phone` | `VARCHAR(20)` | NO | UNIQUE | Primary SMS/OTP contact number. UNIQUE prevents duplicate profiles. |
| `loyalty_tier` | `VARCHAR(20)` | NO | CHECK (`loyalty_tier IN ('BLUE', 'SILVER', 'GOLD', 'PLATINUM')`) | Reward loyalty tier progression. |
| `created_at` | `TIMESTAMPTZ`| NO | NOT NULL | Customer registration timestamp. |

### 3.7 `coupons`
| Column | Data Type | Nullable | Constraints & References | Justification |
|:---|:---|:---|:---|:---|
| `coupon_code` | `VARCHAR(30)` | NO | PRIMARY KEY | Alphanumeric campaign voucher code (e.g., `DIWALI19`). |
| `applies_to` | `VARCHAR(20)` | NO | CHECK (`applies_to IN ('FLIGHT', 'HOTEL', 'ALL')`) | Eligible travel category. |
| `discount_pct`| `NUMERIC(5,2)`| NO | CHECK (`discount_pct > 0 AND discount_pct <= 100`) | Percentage discount. |
| `max_discount`| `NUMERIC(10,2)`| NO | CHECK (`max_discount >= 0`) | Monetary discount ceiling cap in INR. |
| `valid_from` | `DATE` | NO | NOT NULL | Promotional campaign launch date. |
| `valid_to` | `DATE` | NO | NOT NULL, CHECK (`valid_to >= valid_from`) | Campaign expiration date. |

### 3.8 `bookings`
| Column | Data Type | Nullable | Constraints & References | Justification |
|:---|:---|:---|:---|:---|
| `booking_id` | `INTEGER` | NO | PRIMARY KEY | Master booking transaction identifier. |
| `booking_ref` | `VARCHAR(20)` | NO | UNIQUE | 8-character human-readable alphanumeric PNR (e.g., `MM01B808`). |
| `customer_id` | `INTEGER` | NO | REFERENCES `customers(customer_id)` ON DELETE RESTRICT | Account owner. RESTRICT prevents deleting active accounts. |
| `booking_type`| `VARCHAR(20)` | NO | CHECK (`booking_type IN ('FLIGHT', 'HOTEL')`) | Discriminator column for 1:1 specialization. |
| `booked_at` | `TIMESTAMPTZ`| NO | NOT NULL | Booking timestamp with timezone offset. |
| `total_amount`| `NUMERIC(10,2)`| NO | CHECK (`total_amount >= 0`) | Net payable order amount after discounts. |
| `coupon_code` | `VARCHAR(30)` | YES | REFERENCES `coupons(coupon_code)` ON DELETE SET NULL | Promo voucher applied (NULL if none). |
| `discount` | `NUMERIC(10,2)`| NO | DEFAULT 0.00, CHECK (`discount >= 0`) | Discount amount deducted; requires `coupon_code` if `> 0`. |
| `payment_method`| `VARCHAR(20)`| NO | CHECK (`payment_method IN ('CARD', 'NETBANKING', 'UPI', 'WALLET', 'EMI')`) | Payment channel selected by customer. |
| `status` | `VARCHAR(30)` | NO | CHECK (`status IN ('PENDING_PAYMENT', 'CONFIRMED', 'COMPLETED', 'CANCELLED')`) | Order lifecycle status. |
| `cancelled_at`| `TIMESTAMPTZ`| YES | CHECK (cancelled consistency) | Non-null if and only if `status = 'CANCELLED'`. |
| `refund_amount`| `NUMERIC(10,2)`| YES | CHECK (refund consistency) | Non-null if and only if `status = 'CANCELLED'`; `<=` `total_amount`. |

### 3.9 `flight_bookings`
| Column | Data Type | Nullable | Constraints & References | Justification |
|:---|:---|:---|:---|:---|
| `booking_id` | `INTEGER` | NO | PRIMARY KEY, REFERENCES `bookings(booking_id)` ON DELETE CASCADE | 1:1 subtype relationship. CASCADE deletes flight sector on booking cancel. |
| `flight_id` | `INTEGER` | NO | REFERENCES `flights(flight_id)` ON DELETE RESTRICT | Booked flight segment. RESTRICT prevents deleting scheduled flights. |
| `cabin` | `VARCHAR(20)` | NO | CHECK (`cabin IN ('ECONOMY', 'PREMIUM', 'BUSINESS')`) | Cabin class tier. |
| `passengers` | `INTEGER` | NO | CHECK (`passengers > 0`) | Total passengers booked on this ticket header. |
| `fare_paid` | `NUMERIC(10,2)`| NO | CHECK (`fare_paid >= 0`) | Gross flight fare before booking-level discounts. |

### 3.10 `passengers`
| Column | Data Type | Nullable | Constraints & References | Justification |
|:---|:---|:---|:---|:---|
| `booking_id` | `INTEGER` | NO | REFERENCES `bookings(booking_id)` ON DELETE CASCADE | Associated flight booking. |
| `seq_no` | `INTEGER` | NO | CHECK (`seq_no > 0`) | Passenger sequence index (1..N) within the booking. |
| — | — | — | PRIMARY KEY (`booking_id`, `seq_no`) | Composite PK uniquely identifying each ticketed traveller. |
| `full_name` | `VARCHAR(150)`| NO | NOT NULL | Passenger legal name. |
| `age` | `INTEGER` | NO | CHECK (`age >= 0 AND age <= 125`) | Traveller age in years. |
| `gender` | `CHAR(1)` | NO | CHECK (`gender IN ('M', 'F', 'X')`) | Gender marker (including non-binary 'X'). |
| `seat_no` | `VARCHAR(10)` | YES | NULL allowed before check-in | Seat designation (e.g., `16D`, `17E`); NULL prior to web check-in. |

### 3.11 `hotel_bookings`
| Column | Data Type | Nullable | Constraints & References | Justification |
|:---|:---|:---|:---|:---|
| `booking_id` | `INTEGER` | NO | PRIMARY KEY, REFERENCES `bookings(booking_id)` ON DELETE CASCADE | 1:1 subtype relationship. |
| `hotel_id` | `INTEGER` | NO | REFERENCES `hotels(hotel_id)` ON DELETE RESTRICT | Property reserved. |
| `room_type_id`| `INTEGER` | NO | REFERENCES `room_types(room_type_id)` ON DELETE RESTRICT | Specific room configuration reserved. |
| `check_in` | `DATE` | NO | NOT NULL | Stay commencement date. |
| `check_out` | `DATE` | NO | NOT NULL, CHECK (`check_out > check_in`) | Stay departure date; strictly after check-in. |
| `rooms` | `INTEGER` | NO | CHECK (`rooms > 0`) | Number of rooms reserved. |
| `guests` | `INTEGER` | NO | CHECK (`guests > 0`) | Number of occupants. |
| `room_number` | `VARCHAR(20)` | YES | NULL allowed before check-in | Physical room key/number assigned at hotel front-desk arrival. |

### 3.12 `hotel_reviews`
| Column | Data Type | Nullable | Constraints & References | Justification |
|:---|:---|:---|:---|:---|
| `review_id` | `INTEGER` | NO | PRIMARY KEY | Unique guest review identifier. |
| `booking_id` | `INTEGER` | NO | REFERENCES `bookings(booking_id)` ON DELETE CASCADE | Completed stay reference. |
| `hotel_id` | `INTEGER` | NO | REFERENCES `hotels(hotel_id)` ON DELETE CASCADE | Property evaluated. |
| `rating` | `INTEGER` | NO | CHECK (`rating BETWEEN 1 AND 5`) | Customer satisfaction rating (1 to 5 stars). |
| `title` | `VARCHAR(255)`| NO | NOT NULL | Review summary title. |
| `review_text` | `TEXT` | YES | NULL allowed | Detailed feedback commentary (optional). |
| `created_at` | `TIMESTAMPTZ`| NO | NOT NULL | Feedback submission timestamp. |

---

## 4. Normalization Analysis (1NF → 2NF → 3NF / BCNF)

### 4.1 Functional Dependency (FD) Analysis per Entity
1. **`airports`**: `iata_code → airport_name, city_name, country_code`. Candidate Key: `{iata_code}`. All non-prime attributes are fully functionally dependent on the candidate key with no transitive dependencies. Satisfies **BCNF**.
2. **`airlines`**: `airline_code → airline_name`. Candidate Key: `{airline_code}`. Satisfies **BCNF**.
3. **`flights`**: `flight_id → airline_code, flight_no, origin, destination, departure_at, arrival_at, aircraft, total_seats, base_fare, status`. Candidate Key: `{flight_id}`. Satisfies **BCNF**.
4. **`hotels`**: `hotel_id → hotel_name, city_name, star_rating, user_rating, amenities, check_in_time, check_out_time`. Candidate Key: `{hotel_id}`. Satisfies **BCNF**.
5. **`room_types`**: `room_type_id → hotel_id, room_name, max_guests, price_per_night, total_rooms`. Candidate Key: `{room_type_id}`. Satisfies **BCNF**.
6. **`customers`**: `customer_id → full_name, email, phone, loyalty_tier, created_at`. Candidate Keys: `{customer_id}`, `{email}`, `{phone}`. Satisfies **BCNF**.
7. **`coupons`**: `coupon_code → applies_to, discount_pct, max_discount, valid_from, valid_to`. Candidate Key: `{coupon_code}`. Satisfies **BCNF**.
8. **`bookings`**: `booking_id → booking_ref, customer_id, booking_type, booked_at, total_amount, coupon_code, discount, payment_method, status, cancelled_at, refund_amount`. Candidate Keys: `{booking_id}`, `{booking_ref}`. Satisfies **BCNF**.
9. **`flight_bookings`**: `booking_id → flight_id, cabin, passengers, fare_paid`. Candidate Key: `{booking_id}`. Satisfies **BCNF**.
10. **`passengers`**: `{booking_id, seq_no} → full_name, age, gender, seat_no`. Candidate Key: `{booking_id, seq_no}`. Since the key is composite, 2NF requires that no non-prime attribute depends on a proper subset of the key. `full_name`, `age`, `gender`, and `seat_no` describe the individual passenger in that specific seat, not the entire booking. Thus, no partial dependency exists. Satisfies **3NF/BCNF**.
11. **`hotel_bookings`**: `booking_id → hotel_id, room_type_id, check_in, check_out, rooms, guests, room_number`. Candidate Key: `{booking_id}`. Satisfies **BCNF**.
12. **`hotel_reviews`**: `review_id → booking_id, hotel_id, rating, title, review_text, created_at`. Candidate Key: `{review_id}`.

### 4.2 Analysis of Redundant / Derived Columns
The relational schema retains a few intentional denormalized attributes for operational throughput and performance:
1. **`flight_bookings.passengers` vs. `COUNT(passengers)`**:
   - *Nature*: Derived aggregate.
   - *Justification*: The `passengers` count in `flight_bookings` is used by flight capacity calculations (`R01`, `R08`, `R09`) without needing expensive joins and scans over 163,380+ passenger manifest records.
2. **`flight_bookings.fare_paid` vs. `bookings.total_amount + bookings.discount`**:
   - *Nature*: Redundant financial snapshot.
   - *Justification*: In multi-product platforms or mixed bookings, `fare_paid` records the exact flight tariff at time of booking, shielding sector pricing from coupon allocation rules and cart-level adjustments.
3. **`hotel_reviews.hotel_id` vs. `hotel_bookings.hotel_id`**:
   - *Nature*: Transitive redundancy (`booking_id → hotel_id`).
   - *Justification*: Review queries (`R18`, `R24`) filter directly by `hotel_id` and join on `hotels`. Storing `hotel_id` directly in `hotel_reviews` eliminates an unnecessary double-join through `bookings` and `hotel_bookings`.

---

## 5. Ingestion Verification & Integrity Checks

All 12 files from `seed_data/` and `large_data/` were ingested using PostgreSQL `\copy` with zero constraint violations. The row counts strictly match the official baseline and 20× large scale specifications:

### Seed Dataset (144k Bookings Baseline)
| Table | CSV File | Loaded Rows | Expected Rows | Status |
|:---|:---|---:|---:|:---:|
| `airports` | `airports.csv` | 16 | 16 | Verified |
| `airlines` | `airlines.csv` | 5 | 5 | Verified |
| `flights` | `flights.csv` | 13,848 | 13,848 | Verified |
| `hotels` | `hotels.csv` | 3,000 | 3,000 | Verified |
| `room_types` | `room_types.csv` | 9,000 | 9,000 | Verified |
| `customers` | `customers.csv` | 40,000 | 40,000 | Verified |
| `coupons` | `coupons.csv` | 30 | 30 | Verified |
| `bookings` | `bookings.csv` | 144,792 | 144,792 | Verified |
| `flight_bookings` | `flight_bookings.csv` | 84,899 | 84,899 | Verified |
| `passengers` | `passengers.csv` | 163,380 | 163,380 | Verified |
| `hotel_bookings` | `hotel_bookings.csv` | 59,893 | 59,893 | Verified |
| `hotel_reviews` | `hotel_reviews.csv` | 15,913 | 15,913 | Verified |

### Large Dataset (10.4 Million Rows Phase 5 Round)
| Table | CSV File | Loaded Rows | Scale Multiple | Status |
|:---|:---|---:|---:|:---:|
| `airports` | `airports.csv` | 16 | 1.0× | Verified |
| `airlines` | `airlines.csv` | 5 | 1.0× | Verified |
| `flights` | `flights.csv` | 13,848 | 1.0× | Verified |
| `hotels` | `hotels.csv` | 60,000 | 20.0× | Verified |
| `room_types` | `room_types.csv` | 180,000 | 20.0× | Verified |
| `customers` | `customers.csv` | 800,000 | 20.0× | Verified |
| `coupons` | `coupons.csv` | 30 | 1.0× | Verified |
| `bookings` | `bookings.csv` | 2,897,285 | 20.0× | Verified |
| `flight_bookings` | `flight_bookings.csv` | 1,698,936 | 20.0× | Verified |
| `passengers` | `passengers.csv` | 3,272,394 | 20.0× | Verified |
| `hotel_bookings` | `hotel_bookings.csv` | 1,198,349 | 20.0× | Verified |
| `hotel_reviews` | `hotel_reviews.csv` | 318,847 | 20.0× | Verified |

### 5.1 Verification Queries & Results

#### Integrity Check 1: Exact Subtype Partitioning (Flight vs. Hotel)
Verifies that every master booking is partitioned into either a flight booking or a hotel booking, never both, with no orphans.
```sql
SELECT 
    (SELECT count(*) FROM bookings) AS total_bookings,
    (SELECT count(*) FROM flight_bookings) AS total_flight_bookings,
    (SELECT count(*) FROM hotel_bookings) AS total_hotel_bookings,
    (SELECT count(*) FROM flight_bookings fb JOIN hotel_bookings hb ON fb.booking_id = hb.booking_id) AS overlapping_bookings,
    (SELECT count(*) FROM bookings b WHERE b.booking_type = 'FLIGHT' AND NOT EXISTS (SELECT 1 FROM flight_bookings fb WHERE fb.booking_id = b.booking_id)) AS orphaned_flights,
    (SELECT count(*) FROM bookings b WHERE b.booking_type = 'HOTEL' AND NOT EXISTS (SELECT 1 FROM hotel_bookings hb WHERE hb.booking_id = b.booking_id)) AS orphaned_hotels;
```
**Result:**
```
 total_bookings | total_flight_bookings | total_hotel_bookings | overlapping_bookings | orphaned_flights | orphaned_hotels 
----------------+-----------------------+----------------------+----------------------+------------------+-----------------
         144792 |                 84899 |                59893 |                    0 |                0 |               0
```
*Conclusion*: 84,899 + 59,893 = 144,792. Exact 1:1 specialization with zero overlap and zero orphans.

#### Integrity Check 2: Passenger Header vs. Manifest Count Match
Verifies that the `passengers` count in `flight_bookings` exactly matches the count of child records in `passengers`.
```sql
SELECT count(*) AS passenger_mismatches
FROM flight_bookings fb
LEFT JOIN (
    SELECT booking_id, count(*) AS actual_passengers
    FROM passengers
    GROUP BY booking_id
) p ON p.booking_id = fb.booking_id
WHERE fb.passengers <> coalesce(p.actual_passengers, 0);
```
**Result:**
```
 passenger_mismatches 
----------------------
                    0
```

#### Integrity Check 3: Temporal Sanity of Bookings vs. Flight Departures
Verifies that no booking was created after the scheduled departure of the flight.
```sql
SELECT count(*) AS bookings_after_departure
FROM flight_bookings fb
JOIN bookings b ON b.booking_id = fb.booking_id
JOIN flights f ON f.flight_id = fb.flight_id
WHERE b.booked_at > f.departure_at;
```
**Result:**
```
 bookings_after_departure 
--------------------------
                        0
```

#### Integrity Check 4: Reviews Strictly Tied to Completed Stays
Verifies that hotel reviews originate strictly from completed hotel stays.
```sql
SELECT count(*) AS invalid_reviews
FROM hotel_reviews r
JOIN bookings b ON b.booking_id = r.booking_id
WHERE b.status <> 'COMPLETED' OR b.booking_type <> 'HOTEL';
```
**Result:**
```
 invalid_reviews 
-----------------
               0
```

---

## 6. Discovered Data Anomalies & Schema Handling
1. **Unassigned Seats & Rooms Prior to Check-In**:
   - `passengers.seat_no` is NULL for 21,612 rows (passengers who have not checked in online).
   - `hotel_bookings.room_number` is NULL for 6,815 rows (guests arriving in future dates or pending front-desk assignment).
   - *Schema Handling*: Defined columns as nullable `VARCHAR` without NOT NULL constraints.
2. **Nullable Coupon Codes and 3-Valued Logic**:
   - 127,144 out of 144,792 bookings did not use a coupon (`coupon_code` is NULL).
   - In SQL, `WHERE val NOT IN (SELECT nullable_col ...)` evaluates to `UNKNOWN` whenever the subquery contains a NULL value. This caused query `R13` to return zero rows.
3. **Payment Methods in Large Dataset**:
   - In `seed_data`, payment methods included `'CARD'`, `'NETBANKING'`, `'UPI'`, and `'WALLET'`.
   - Inspection of `large_data` revealed an additional payment method: `'EMI'`.
   - *Schema Handling*: Included `'EMI'` in `bookings_payment_method_valid_chk` to ensure complete forward compatibility.
