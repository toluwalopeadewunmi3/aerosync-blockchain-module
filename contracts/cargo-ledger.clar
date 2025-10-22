;; Cargo Ledger Smart Contract
;; Handles cargo registration, status updates, and delivery proofs
;; ensuring verifiable cargo movement across handlers and airports

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-found (err u101))
(define-constant err-already-exists (err u102))
(define-constant err-unauthorized (err u103))
(define-constant err-invalid-status (err u104))
(define-constant err-invalid-data (err u105))

;; Data Variables
(define-data-var cargo-nonce uint u0)

;; Cargo Status Types
(define-constant status-registered "REGISTERED")
(define-constant status-in-transit "IN_TRANSIT")
(define-constant status-at-handler "AT_HANDLER")
(define-constant status-loaded "LOADED")
(define-constant status-in-flight "IN_FLIGHT")
(define-constant status-delivered "DELIVERED")

;; Data Maps
(define-map cargo-records
  { cargo-id: uint }
  {
    airline: (string-ascii 100),
    handler: principal,
    origin: (string-ascii 50),
    destination: (string-ascii 50),
    weight: uint,
    status: (string-ascii 20),
    data-hash: (string-ascii 64),
    registered-by: principal,
    registered-at: uint,
    last-updated: uint,
    delivery-proof: (optional (string-ascii 64))
  }
)

(define-map cargo-status-history
  { cargo-id: uint, sequence: uint }
  {
    status: (string-ascii 20),
    updated-by: principal,
    updated-at: uint,
    location: (string-ascii 50),
    notes-hash: (string-ascii 64)
  }
)

(define-map cargo-status-count
  { cargo-id: uint }
  { count: uint }
)

(define-map handler-cargo-count
  { handler: principal }
  { total: uint, active: uint }
)

;; Authorization Map
(define-map authorized-handlers
  { handler: principal }
  { authorized: bool }
)

;; Read-only functions

(define-read-only (get-cargo-record (cargo-id uint))
  (map-get? cargo-records { cargo-id: cargo-id })
)

(define-read-only (get-cargo-status-history (cargo-id uint) (sequence uint))
  (map-get? cargo-status-history { cargo-id: cargo-id, sequence: sequence })
)

(define-read-only (get-cargo-status-count (cargo-id uint))
  (default-to { count: u0 } (map-get? cargo-status-count { cargo-id: cargo-id }))
)

(define-read-only (get-handler-stats (handler principal))
  (default-to { total: u0, active: u0 } (map-get? handler-cargo-count { handler: handler }))
)

(define-read-only (is-handler-authorized (handler principal))
  (match (map-get? authorized-handlers { handler: handler })
    entry (get authorized entry)
    false
  )
)

(define-read-only (get-current-cargo-nonce)
  (var-get cargo-nonce)
)

;; Public functions

(define-public (authorize-handler (handler principal))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (ok (map-set authorized-handlers
      { handler: handler }
      { authorized: true }
    ))
  )
)

(define-public (revoke-handler (handler principal))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (ok (map-set authorized-handlers
      { handler: handler }
      { authorized: false }
    ))
  )
)

(define-public (register-cargo
  (airline (string-ascii 100))
  (handler principal)
  (origin (string-ascii 50))
  (destination (string-ascii 50))
  (weight uint)
  (data-hash (string-ascii 64))
)
  (let
    (
      (new-cargo-id (+ (var-get cargo-nonce) u1))
      (current-stats (get-handler-stats handler))
    )
    (asserts! (is-handler-authorized handler) err-unauthorized)
    (asserts! (> weight u0) err-invalid-data)
    (asserts! (> (len airline) u0) err-invalid-data)
    (asserts! (> (len origin) u0) err-invalid-data)
    (asserts! (> (len destination) u0) err-invalid-data)
    
    (map-set cargo-records
      { cargo-id: new-cargo-id }
      {
        airline: airline,
        handler: handler,
        origin: origin,
        destination: destination,
        weight: weight,
        status: status-registered,
        data-hash: data-hash,
        registered-by: tx-sender,
        registered-at: stacks-block-height,
        last-updated: stacks-block-height,
        delivery-proof: none
      }
    )
    
    (map-set cargo-status-history
      { cargo-id: new-cargo-id, sequence: u0 }
      {
        status: status-registered,
        updated-by: tx-sender,
        updated-at: stacks-block-height,
        location: origin,
        notes-hash: data-hash
      }
    )
    
    (map-set cargo-status-count
      { cargo-id: new-cargo-id }
      { count: u1 }
    )
    
    (map-set handler-cargo-count
      { handler: handler }
      { total: (+ (get total current-stats) u1), active: (+ (get active current-stats) u1) }
    )
    
    (var-set cargo-nonce new-cargo-id)
    (ok new-cargo-id)
  )
)

(define-public (update-cargo-status
  (cargo-id uint)
  (new-status (string-ascii 20))
  (location (string-ascii 50))
  (notes-hash (string-ascii 64))
)
  (let
    (
      (cargo (unwrap! (map-get? cargo-records { cargo-id: cargo-id }) err-not-found))
      (status-count (get count (get-cargo-status-count cargo-id)))
      (handler (get handler cargo))
    )
    (asserts! (or (is-eq tx-sender handler) (is-handler-authorized tx-sender)) err-unauthorized)
    (asserts! (> (len new-status) u0) err-invalid-status)
    
    (map-set cargo-records
      { cargo-id: cargo-id }
      (merge cargo {
        status: new-status,
        last-updated: stacks-block-height
      })
    )
    
    (map-set cargo-status-history
      { cargo-id: cargo-id, sequence: status-count }
      {
        status: new-status,
        updated-by: tx-sender,
        updated-at: stacks-block-height,
        location: location,
        notes-hash: notes-hash
      }
    )
    
    (map-set cargo-status-count
      { cargo-id: cargo-id }
      { count: (+ status-count u1) }
    )
    
    (ok true)
  )
)

(define-public (record-delivery-proof
  (cargo-id uint)
  (proof-hash (string-ascii 64))
  (final-location (string-ascii 50))
)
  (let
    (
      (cargo (unwrap! (map-get? cargo-records { cargo-id: cargo-id }) err-not-found))
      (handler (get handler cargo))
      (current-stats (get-handler-stats handler))
    )
    (asserts! (or (is-eq tx-sender handler) (is-handler-authorized tx-sender)) err-unauthorized)
    (asserts! (is-none (get delivery-proof cargo)) err-invalid-status)
    
    (map-set cargo-records
      { cargo-id: cargo-id }
      (merge cargo {
        status: status-delivered,
        delivery-proof: (some proof-hash),
        last-updated: stacks-block-height
      })
    )
    
    (map-set handler-cargo-count
      { handler: handler }
      { total: (get total current-stats), active: (- (get active current-stats) u1) }
    )
    
    (try! (update-cargo-status cargo-id status-delivered final-location proof-hash))
    
    (ok true)
  )
)

(define-public (verify-cargo (cargo-id uint) (expected-hash (string-ascii 64)))
  (let
    (
      (cargo (unwrap! (map-get? cargo-records { cargo-id: cargo-id }) err-not-found))
    )
    (ok (is-eq (get data-hash cargo) expected-hash))
  )
)

;; title: cargo-ledger
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

