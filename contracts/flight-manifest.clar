;; Flight Manifest Smart Contract
;; Links blockchain logs to passenger or cargo manifests securely
;; Provides end-to-end visibility from flight planning to ground operations and cargo handling
;; Designed for IATA One Record API interoperability

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-found (err u101))
(define-constant err-unauthorized (err u102))
(define-constant err-invalid-data (err u103))
(define-constant err-already-verified (err u104))
(define-constant err-invalid-status (err u105))
(define-constant err-manifest-locked (err u106))

;; Data Variables
(define-data-var manifest-nonce uint u0)

;; Manifest Status Types
(define-constant status-draft "DRAFT")
(define-constant status-submitted "SUBMITTED")
(define-constant status-verified "VERIFIED")
(define-constant status-locked "LOCKED")
(define-constant status-departed "DEPARTED")
(define-constant status-arrived "ARRIVED")
(define-constant status-completed "COMPLETED")

;; Manifest Types
(define-constant type-passenger "PASSENGER")
(define-constant type-cargo "CARGO")
(define-constant type-mixed "MIXED")

;; Data Maps
(define-map flight-manifests
  { manifest-id: uint }
  {
    flight-number: (string-ascii 20),
    aircraft-id: (string-ascii 50),
    airline: (string-ascii 100),
    operator: principal,
    manifest-type: (string-ascii 20),
    origin-airport: (string-ascii 10),
    destination-airport: (string-ascii 10),
    departure-time: uint,
    arrival-time: (optional uint),
    manifest-hash: (string-ascii 64),
    iata-one-record-id: (optional (string-ascii 100)),
    passenger-count: uint,
    cargo-count: uint,
    total-weight: uint,
    status: (string-ascii 20),
    created-by: principal,
    created-at: uint,
    verified-by: (optional principal),
    verified-at: (optional uint),
    locked: bool
  }
)

(define-map manifest-items
  { manifest-id: uint, item-index: uint }
  {
    item-type: (string-ascii 20),
    item-id: (string-ascii 100),
    description: (string-ascii 200),
    weight: uint,
    item-hash: (string-ascii 64),
    special-handling: (optional (string-ascii 100)),
    linked-cargo-id: (optional uint)
  }
)

(define-map manifest-item-count
  { manifest-id: uint }
  { count: uint }
)

(define-map manifest-status-history
  { manifest-id: uint, sequence: uint }
  {
    status: (string-ascii 20),
    updated-by: principal,
    updated-at: uint,
    location: (string-ascii 50),
    notes-hash: (string-ascii 64)
  }
)

(define-map manifest-status-count
  { manifest-id: uint }
  { count: uint }
)

(define-map flight-manifest-index
  { flight-number: (string-ascii 20), departure-time: uint }
  { manifest-id: uint }
)

(define-map airline-manifest-history
  { airline: (string-ascii 100), sequence: uint }
  { manifest-id: uint, flight-number: (string-ascii 20), created-at: uint }
)

(define-map airline-manifest-count
  { airline: (string-ascii 100) }
  { count: uint }
)

(define-map operator-stats
  { operator: principal }
  { total-manifests: uint, verified-manifests: uint, total-flights: uint }
)

;; Authorization Maps
(define-map authorized-operators
  { operator: principal }
  { authorized: bool, airline: (string-ascii 100) }
)

(define-map authorized-verifiers
  { verifier: principal }
  { authorized: bool, authority-level: uint }
)

;; Read-only functions

(define-read-only (get-flight-manifest (manifest-id uint))
  (map-get? flight-manifests { manifest-id: manifest-id })
)

(define-read-only (get-manifest-item (manifest-id uint) (item-index uint))
  (map-get? manifest-items { manifest-id: manifest-id, item-index: item-index })
)

(define-read-only (get-manifest-status-history (manifest-id uint) (sequence uint))
  (map-get? manifest-status-history { manifest-id: manifest-id, sequence: sequence })
)

(define-read-only (get-manifest-by-flight (flight-number (string-ascii 20)) (departure-time uint))
  (match (map-get? flight-manifest-index { flight-number: flight-number, departure-time: departure-time })
    entry (get-flight-manifest (get manifest-id entry))
    none
  )
)

(define-read-only (get-airline-manifest-history (airline (string-ascii 100)) (sequence uint))
  (map-get? airline-manifest-history { airline: airline, sequence: sequence })
)

(define-read-only (get-airline-stats (airline (string-ascii 100)))
  (default-to { count: u0 } (map-get? airline-manifest-count { airline: airline }))
)

(define-read-only (get-operator-stats (operator principal))
  (default-to { total-manifests: u0, verified-manifests: u0, total-flights: u0 }
    (map-get? operator-stats { operator: operator }))
)

(define-read-only (is-operator-authorized (operator principal))
  (match (map-get? authorized-operators { operator: operator })
    entry (get authorized entry)
    false
  )
)

(define-read-only (is-verifier-authorized (verifier principal))
  (match (map-get? authorized-verifiers { verifier: verifier })
    entry (get authorized entry)
    false
  )
)

(define-read-only (get-current-manifest-nonce)
  (var-get manifest-nonce)
)

;; Public functions

(define-public (authorize-operator (operator principal) (airline (string-ascii 100)))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (ok (map-set authorized-operators
      { operator: operator }
      { authorized: true, airline: airline }
    ))
  )
)

(define-public (authorize-verifier (verifier principal) (authority-level uint))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (ok (map-set authorized-verifiers
      { verifier: verifier }
      { authorized: true, authority-level: authority-level }
    ))
  )
)

(define-public (revoke-operator (operator principal))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (ok (map-delete authorized-operators { operator: operator }))
  )
)

(define-public (create-flight-manifest
  (flight-number (string-ascii 20))
  (aircraft-id (string-ascii 50))
  (airline (string-ascii 100))
  (manifest-type (string-ascii 20))
  (origin-airport (string-ascii 10))
  (destination-airport (string-ascii 10))
  (departure-time uint)
  (manifest-hash (string-ascii 64))
  (passenger-count uint)
  (cargo-count uint)
  (total-weight uint)
)
  (let
    (
      (new-manifest-id (+ (var-get manifest-nonce) u1))
      (operator-current-stats (get-operator-stats tx-sender))
      (airline-count (get count (get-airline-stats airline)))
    )
    (asserts! (is-operator-authorized tx-sender) err-unauthorized)
    (asserts! (> (len flight-number) u0) err-invalid-data)
    (asserts! (> (len aircraft-id) u0) err-invalid-data)
    (asserts! (> departure-time u0) err-invalid-data)
    
    (map-set flight-manifests
      { manifest-id: new-manifest-id }
      {
        flight-number: flight-number,
        aircraft-id: aircraft-id,
        airline: airline,
        operator: tx-sender,
        manifest-type: manifest-type,
        origin-airport: origin-airport,
        destination-airport: destination-airport,
        departure-time: departure-time,
        arrival-time: none,
        manifest-hash: manifest-hash,
        iata-one-record-id: none,
        passenger-count: passenger-count,
        cargo-count: cargo-count,
        total-weight: total-weight,
        status: status-draft,
        created-by: tx-sender,
        created-at: stacks-block-height,
        verified-by: none,
        verified-at: none,
        locked: false
      }
    )
    
    (map-set flight-manifest-index
      { flight-number: flight-number, departure-time: departure-time }
      { manifest-id: new-manifest-id }
    )
    
    (map-set manifest-status-history
      { manifest-id: new-manifest-id, sequence: u0 }
      {
        status: status-draft,
        updated-by: tx-sender,
        updated-at: stacks-block-height,
        location: origin-airport,
        notes-hash: manifest-hash
      }
    )
    
    (map-set manifest-status-count
      { manifest-id: new-manifest-id }
      { count: u1 }
    )
    
    (map-set manifest-item-count
      { manifest-id: new-manifest-id }
      { count: u0 }
    )
    
    (map-set airline-manifest-history
      { airline: airline, sequence: airline-count }
      { manifest-id: new-manifest-id, flight-number: flight-number, created-at: stacks-block-height }
    )
    
    (map-set airline-manifest-count
      { airline: airline }
      { count: (+ airline-count u1) }
    )
    
    (map-set operator-stats
      { operator: tx-sender }
      {
        total-manifests: (+ (get total-manifests operator-current-stats) u1),
        verified-manifests: (get verified-manifests operator-current-stats),
        total-flights: (+ (get total-flights operator-current-stats) u1)
      }
    )
    
    (var-set manifest-nonce new-manifest-id)
    (ok new-manifest-id)
  )
)

(define-public (add-manifest-item
  (manifest-id uint)
  (item-type (string-ascii 20))
  (item-id (string-ascii 100))
  (description (string-ascii 200))
  (weight uint)
  (item-hash (string-ascii 64))
  (special-handling (optional (string-ascii 100)))
  (linked-cargo-id (optional uint))
)
  (let
    (
      (manifest (unwrap! (map-get? flight-manifests { manifest-id: manifest-id }) err-not-found))
      (item-count (default-to { count: u0 } (map-get? manifest-item-count { manifest-id: manifest-id })))
      (current-count (get count item-count))
    )
    (asserts! (is-eq tx-sender (get operator manifest)) err-unauthorized)
    (asserts! (not (get locked manifest)) err-manifest-locked)
    (asserts! (> (len item-id) u0) err-invalid-data)
    
    (map-set manifest-items
      { manifest-id: manifest-id, item-index: current-count }
      {
        item-type: item-type,
        item-id: item-id,
        description: description,
        weight: weight,
        item-hash: item-hash,
        special-handling: special-handling,
        linked-cargo-id: linked-cargo-id
      }
    )
    
    (map-set manifest-item-count
      { manifest-id: manifest-id }
      { count: (+ current-count u1) }
    )
    
    (ok true)
  )
)

(define-public (update-manifest-status
  (manifest-id uint)
  (new-status (string-ascii 20))
  (location (string-ascii 50))
  (notes-hash (string-ascii 64))
)
  (let
    (
      (manifest (unwrap! (map-get? flight-manifests { manifest-id: manifest-id }) err-not-found))
      (status-count (get count (default-to { count: u0 } (map-get? manifest-status-count { manifest-id: manifest-id }))))
    )
    (asserts! (or (is-eq tx-sender (get operator manifest)) (is-verifier-authorized tx-sender)) err-unauthorized)
    (asserts! (> (len new-status) u0) err-invalid-status)
    
    (map-set flight-manifests
      { manifest-id: manifest-id }
      (merge manifest {
        status: new-status,
        arrival-time: (if (is-eq new-status status-arrived) (some stacks-block-height) (get arrival-time manifest))
      })
    )
    
    (map-set manifest-status-history
      { manifest-id: manifest-id, sequence: status-count }
      {
        status: new-status,
        updated-by: tx-sender,
        updated-at: stacks-block-height,
        location: location,
        notes-hash: notes-hash
      }
    )
    
    (map-set manifest-status-count
      { manifest-id: manifest-id }
      { count: (+ status-count u1) }
    )
    
    (ok true)
  )
)

(define-public (verify-manifest (manifest-id uint) (verification-hash (string-ascii 64)))
  (let
    (
      (manifest (unwrap! (map-get? flight-manifests { manifest-id: manifest-id }) err-not-found))
      (operator (get operator manifest))
      (operator-current-stats (get-operator-stats operator))
    )
    (asserts! (is-verifier-authorized tx-sender) err-unauthorized)
    (asserts! (is-none (get verified-at manifest)) err-already-verified)
    
    (map-set flight-manifests
      { manifest-id: manifest-id }
      (merge manifest {
        status: status-verified,
        verified-by: (some tx-sender),
        verified-at: (some stacks-block-height),
        locked: true
      })
    )
    
    (map-set operator-stats
      { operator: operator }
      (merge operator-current-stats {
        verified-manifests: (+ (get verified-manifests operator-current-stats) u1)
      })
    )
    
    (try! (update-manifest-status manifest-id status-verified (get origin-airport manifest) verification-hash))
    
    (ok true)
  )
)

(define-public (link-iata-one-record (manifest-id uint) (iata-record-id (string-ascii 100)))
  (let
    (
      (manifest (unwrap! (map-get? flight-manifests { manifest-id: manifest-id }) err-not-found))
    )
    (asserts! (or (is-eq tx-sender (get operator manifest)) (is-eq tx-sender contract-owner)) err-unauthorized)
    (asserts! (> (len iata-record-id) u0) err-invalid-data)
    
    (map-set flight-manifests
      { manifest-id: manifest-id }
      (merge manifest {
        iata-one-record-id: (some iata-record-id)
      })
    )
    
    (ok true)
  )
)

(define-public (verify-manifest-data (manifest-id uint) (expected-hash (string-ascii 64)))
  (let
    (
      (manifest (unwrap! (map-get? flight-manifests { manifest-id: manifest-id }) err-not-found))
    )
    (ok (is-eq (get manifest-hash manifest) expected-hash))
  )
)

(define-public (verify-manifest-item (manifest-id uint) (item-index uint) (expected-hash (string-ascii 64)))
  (let
    (
      (item (unwrap! (map-get? manifest-items { manifest-id: manifest-id, item-index: item-index }) err-not-found))
    )
    (ok (is-eq (get item-hash item) expected-hash))
  )
)

;; title: flight-manifest
;; version:
;; summary:
;; description:

;; traits
;;

;; token definitions
;;

;; constants
;;

;; data vars
;;

;; data maps
;;

;; public functions
;;

;; read only functions
;;

;; private functions
;;

