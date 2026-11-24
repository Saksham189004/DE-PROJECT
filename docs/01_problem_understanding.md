# Phase 1: Problem Understanding & Workload Analysis

## Executive Summary
MakeMyTrip operates a high-throughput multi-service travel marketplace delivering scheduled flight bookings and hotel accommodations across domestic and international routes. The platform's rapid expansion resulted in severe performance bottlenecks across real-time user-facing flows (search, booking, check-in, checkout) and mission-critical back-office reporting (revenue reconciliation, partner settlements, operational manifests).

This document analyzes the eight core operational problems (P1–P8) identified by cross-functional business units, identifies primary stakeholders, categorizes workload dynamics (Customer-Facing/Real-Time vs. Reporting/Analytics), sets performance latency targets, and articulates foundational architectural assumptions.

---

## Analysis of Problem Statements (P1 – P8)

| ID | Problem Statement & Business Need | Impacted Stakeholder(s) | Workload Classification | Related Queries | Latency Target / SLA |
|:---|:---|:---|:---|:---|:---|
| **P1** | **Flight Search, Fare Calendar & Real-Time Availability**<br>Travellers search for point-to-point flights on specific dates and view 30-day fare calendars. Current searches suffer from severe response latency, while seat availability calculation lags behind concurrent bookings. The business needs sub-second response times and atomic seat decrementing. | • Travellers<br>• Revenue Management<br>• Airline Partners | **Customer-Facing / Real-Time (OLTP)** | `R01`, `R02`, `R10` | < 50 ms (Search)<br>< 100 ms (Calendar) |
| **P2** | **Hotel Search, Amenity Filtering & Multi-Day Availability**<br>Guests filter properties by city, star rating, and specific amenities (JSON parsing for `pool`, `wifi`, etc.) while computing true room availability over multi-day overlapping stay windows. Inefficient JSON extraction and full table scans cause customer drop-off. | • Travellers<br>• Hotel Partners | **Customer-Facing / Real-Time (OLTP)** | `R03`, `R04`, `R18`, `R24` | < 100 ms |
| **P3** | **Customer Account Hub & Booking Lookup ("My Trips")**<br>Travellers accessing upcoming trip itineraries or customer support agents looking up reservations by booking reference experience UI freezes due to unindexed customer lookups and unindexed booking reference searches. | • Travellers<br>• Customer Support | **Customer-Facing / Real-Time (OLTP)** | `R05`, `R06`, `R23` | < 20 ms |
| **P4** | **Airline Operations: Flight Manifests & Route Health**<br>Airline partners require instant seat-ordered passenger manifests for boarding/dispatch (`flight_id = 13047`), low-occupancy flight identification, and real-time cancellation analytics. Delays in manifest generation threaten airline departure punctuality and regulatory compliance. | • Airline Partners<br>• Flight Operations | **Operational Real-Time & Nearline Reporting** | `R07`, `R08`, `R14`, `R19`, `W04` | < 50 ms (Manifests)<br>< 500 ms (Batch Ops) |
| **P5** | **Checkout, Payment Processing & State Transitions**<br>Checkout creates pending reservations that must be confirmed upon payment callback or expired after 30 minutes. High concurrency leads to row lock contention, deadlocks, and slow scans on `status = 'PENDING_PAYMENT'`. Payment timeouts directly cause cart abandonment and revenue leakage. | • Travellers<br>• Payment Gateway Integrations<br>• Finance Operations | **Customer-Facing / Real-Time (OLTP)** | `R11`, `W01`, `W02`, `W03` | < 30 ms (Checkout/Callback)<br>< 100 ms (Queue Scan) |
| **P6** | **Marketing Coupon Utilization & Zero-Yield Bug**<br>Marketing campaigns evaluate coupon effectiveness and track dormant promo codes. The current implementation relies on `WHERE coupon_code NOT IN (SELECT coupon_code FROM bookings)`, which yields zero rows because unapplied bookings store `NULL` values. The query must be rewritten to handle 3-valued boolean logic correctly. | • Marketing Team<br>• Growth & Promotions | **Reporting / Analytics (OLAP)** | `R13` | < 50 ms (Accurate result) |
| **P7** | **Hotel Partner Settlements & Front-Desk Check-In**<br>Hotel partners need monthly room-night consumption per city for commission settlements, while front-desk staff require instantaneous room number assignment for guests arriving today. Sequential scans on large booking tables delay hotel front-desk operations. | • Hotel Partners<br>• Front Desk Operations<br>• Finance Team | **Hybrid (Operational Writes + Analytics)** | `R15`, `W05` | < 50 ms (Check-in write)<br>< 500 ms (Monthly aggregation) |
| **P8** | **Executive Insights, Concessions, Financial Audit & 20× Scalability**<br>Finance and executive teams require monthly revenue reconciliations, senior-citizen route concessions, advance-purchase lead time distributions, and pagination across 100,000+ bookings. As booking volume surges by 20× (from 144k to 2.9M+ bookings), unindexed full table scans cause query timeouts. | • Executive Leadership<br>• Finance & Accounting<br>• Loyalty Strategy Team | **Reporting / Analytics (OLAP)** | `R09`, `R12`, `R16`, `R17`, `R20`, `R21`, `R22`, `R25` | < 1,000 ms (Analytical reports)<br>< 100 ms (Console pagination) |

---

## Architectural & Business Assumptions

1. **Schema Integrity & Isolation**:
   - All tables reside within the dedicated PostgreSQL schema `mmt` (`SET search_path TO mmt;`).
   - A single booking record represents either a flight booking or a hotel booking (`booking_type IN ('FLIGHT', 'HOTEL')`), enforced via mutually exclusive child records in `flight_bookings` or `hotel_bookings`.
2. **Temporal Consistency**:
   - Booking timestamp (`booked_at`) strictly precedes departure (`departure_at`) or hotel check-in (`check_in`).
   - Flight arrival timestamp (`arrival_at`) is strictly greater than departure timestamp (`departure_at`).
   - Hotel check-out date (`check_out`) is strictly greater than check-in date (`check_in`).
3. **Financial Constraints**:
   - `refund_amount` is non-null if and only if booking status is `'CANCELLED'`, and cannot exceed the original `total_amount`.
   - `discount` is non-negative and requires a non-null `coupon_code` when greater than zero.
4. **Data Types & Encoding**:
   - Timestamps include explicit time zone offsets (`TIMESTAMPTZ`) aligned to Indian Standard Time (`+05:30`).
   - Financial amounts and fares use fixed-point decimal arithmetic (`NUMERIC(10,2)`).
   - Hotel amenities are stored in structured `JSONB` for optimized binary storage and GIN indexing capability.
5. **Phase 2 Baseline Rule**:
   - During Phase 2 and Phase 3, no secondary indexes beyond implicit constraints (PRIMARY KEY and UNIQUE) will be created, ensuring baseline timings reflect untuned physical table storage.
