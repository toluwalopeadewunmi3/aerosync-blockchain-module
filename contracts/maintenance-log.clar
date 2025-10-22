;; Maintenance Log Smart Contract
;; Stores immutable maintenance records for aircraft
;; Links technician identity, tasks, costs, and timestamps for tamper-proof verification

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-found (err u101))
(define-constant err-unauthorized (err u102))
(define-constant err-invalid-data (err u103))
(define-constant err-already-verified (err u104))
(define-constant err-invalid-status (err u105))

;; Data Variables
(define-data-var maintenance-nonce uint u0)

;; Maintenance Status Types
(define-constant status-pending "PENDING")
(define-constant status-in-progress "IN_PROGRESS")
(define-constant status-completed "COMPLETED")
(define-constant status-verified "VERIFIED")

;; Data Maps
(define-map maintenance-records
  { maintenance-id: uint }
  {
    aircraft-id: (string-ascii 50),
    task-description: (string-ascii 200),
    task-category: (string-ascii 50),
    technician: principal,
    supervisor: (optional principal),
    cost: uint,
    currency: (string-ascii 10),
    status: (string-ascii 20),
    data-hash: (string-ascii 64),
    started-at: uint,
    completed-at: (optional uint),
    verified-at: (optional uint),
    verification-hash: (optional (string-ascii 64)),
    next-maintenance-due: (optional uint)
  }
)

(define-map maintenance-parts
  { maintenance-id: uint, part-index: uint }
  {
    part-name: (string-ascii 100),
    part-number: (string-ascii 50),
    quantity: uint,
    cost: uint
  }
)

(define-map maintenance-part-count
  { maintenance-id: uint }
  { count: uint }
)

(define-map aircraft-maintenance-history
  { aircraft-id: (string-ascii 50), sequence: uint }
  { maintenance-id: uint, performed-at: uint }
)

(define-map aircraft-maintenance-count
  { aircraft-id: (string-ascii 50) }
  { count: uint, total-cost: uint }
)

(define-map technician-stats
  { technician: principal }
  { total-jobs: uint, verified-jobs: uint, total-cost-handled: uint }
)

;; Authorization Maps
(define-map authorized-technicians
  { technician: principal }
  { authorized: bool, certification-level: uint }
)

(define-map authorized-supervisors
  { supervisor: principal }
  { authorized: bool }
)

;; Read-only functions

(define-read-only (get-maintenance-record (maintenance-id uint))
  (map-get? maintenance-records { maintenance-id: maintenance-id })
)

(define-read-only (get-maintenance-part (maintenance-id uint) (part-index uint))
  (map-get? maintenance-parts { maintenance-id: maintenance-id, part-index: part-index })
)

(define-read-only (get-aircraft-maintenance-history (aircraft-id (string-ascii 50)) (sequence uint))
  (map-get? aircraft-maintenance-history { aircraft-id: aircraft-id, sequence: sequence })
)

(define-read-only (get-aircraft-stats (aircraft-id (string-ascii 50)))
  (default-to { count: u0, total-cost: u0 } (map-get? aircraft-maintenance-count { aircraft-id: aircraft-id }))
)

(define-read-only (get-technician-stats (technician principal))
  (default-to { total-jobs: u0, verified-jobs: u0, total-cost-handled: u0 } 
    (map-get? technician-stats { technician: technician }))
)

(define-read-only (is-technician-authorized (technician principal))
  (match (map-get? authorized-technicians { technician: technician })
    entry (get authorized entry)
    false
  )
)

(define-read-only (is-supervisor-authorized (supervisor principal))
  (match (map-get? authorized-supervisors { supervisor: supervisor })
    entry (get authorized entry)
    false
  )
)

(define-read-only (get-current-maintenance-nonce)
  (var-get maintenance-nonce)
)

;; Public functions

(define-public (authorize-technician (technician principal) (certification-level uint))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (ok (map-set authorized-technicians
      { technician: technician }
      { authorized: true, certification-level: certification-level }
    ))
  )
)

(define-public (authorize-supervisor (supervisor principal))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (ok (map-set authorized-supervisors
      { supervisor: supervisor }
      { authorized: true }
    ))
  )
)

(define-public (revoke-technician (technician principal))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (ok (map-delete authorized-technicians { technician: technician }))
  )
)

(define-public (log-maintenance
  (aircraft-id (string-ascii 50))
  (task-description (string-ascii 200))
  (task-category (string-ascii 50))
  (cost uint)
  (currency (string-ascii 10))
  (data-hash (string-ascii 64))
  (next-maintenance-due (optional uint))
)
  (let
    (
      (new-maintenance-id (+ (var-get maintenance-nonce) u1))
      (aircraft-stats (get-aircraft-stats aircraft-id))
      (tech-stats (get-technician-stats tx-sender))
      (aircraft-count (get count aircraft-stats))
    )
    (asserts! (is-technician-authorized tx-sender) err-unauthorized)
    (asserts! (> (len aircraft-id) u0) err-invalid-data)
    (asserts! (> (len task-description) u0) err-invalid-data)
    (asserts! (>= cost u0) err-invalid-data)
    
    (map-set maintenance-records
      { maintenance-id: new-maintenance-id }
      {
        aircraft-id: aircraft-id,
        task-description: task-description,
        task-category: task-category,
        technician: tx-sender,
        supervisor: none,
        cost: cost,
        currency: currency,
        status: status-pending,
        data-hash: data-hash,
        started-at: stacks-block-height,
        completed-at: none,
        verified-at: none,
        verification-hash: none,
        next-maintenance-due: next-maintenance-due
      }
    )
    
    (map-set aircraft-maintenance-history
      { aircraft-id: aircraft-id, sequence: aircraft-count }
      { maintenance-id: new-maintenance-id, performed-at: stacks-block-height }
    )
    
    (map-set aircraft-maintenance-count
      { aircraft-id: aircraft-id }
      { count: (+ aircraft-count u1), total-cost: (+ (get total-cost aircraft-stats) cost) }
    )
    
    (map-set technician-stats
      { technician: tx-sender }
      {
        total-jobs: (+ (get total-jobs tech-stats) u1),
        verified-jobs: (get verified-jobs tech-stats),
        total-cost-handled: (+ (get total-cost-handled tech-stats) cost)
      }
    )
    
    (map-set maintenance-part-count
      { maintenance-id: new-maintenance-id }
      { count: u0 }
    )
    
    (var-set maintenance-nonce new-maintenance-id)
    (ok new-maintenance-id)
  )
)

(define-public (add-maintenance-part
  (maintenance-id uint)
  (part-name (string-ascii 100))
  (part-number (string-ascii 50))
  (quantity uint)
  (cost uint)
)
  (let
    (
      (maintenance (unwrap! (map-get? maintenance-records { maintenance-id: maintenance-id }) err-not-found))
      (part-count (default-to { count: u0 } (map-get? maintenance-part-count { maintenance-id: maintenance-id })))
      (current-count (get count part-count))
    )
    (asserts! (is-eq tx-sender (get technician maintenance)) err-unauthorized)
    (asserts! (> quantity u0) err-invalid-data)
    
    (map-set maintenance-parts
      { maintenance-id: maintenance-id, part-index: current-count }
      {
        part-name: part-name,
        part-number: part-number,
        quantity: quantity,
        cost: cost
      }
    )
    
    (map-set maintenance-part-count
      { maintenance-id: maintenance-id }
      { count: (+ current-count u1) }
    )
    
    (ok true)
  )
)

(define-public (update-maintenance-status
  (maintenance-id uint)
  (new-status (string-ascii 20))
)
  (let
    (
      (maintenance (unwrap! (map-get? maintenance-records { maintenance-id: maintenance-id }) err-not-found))
    )
    (asserts! (is-eq tx-sender (get technician maintenance)) err-unauthorized)
    
    (map-set maintenance-records
      { maintenance-id: maintenance-id }
      (merge maintenance {
        status: new-status,
        completed-at: (if (is-eq new-status status-completed) (some stacks-block-height) (get completed-at maintenance))
      })
    )
    
    (ok true)
  )
)

(define-public (verify-maintenance
  (maintenance-id uint)
  (verification-hash (string-ascii 64))
)
  (let
    (
      (maintenance (unwrap! (map-get? maintenance-records { maintenance-id: maintenance-id }) err-not-found))
      (technician (get technician maintenance))
      (tech-stats (get-technician-stats technician))
    )
    (asserts! (is-supervisor-authorized tx-sender) err-unauthorized)
    (asserts! (is-none (get verified-at maintenance)) err-already-verified)
    (asserts! (is-eq (get status maintenance) status-completed) err-invalid-status)
    
    (map-set maintenance-records
      { maintenance-id: maintenance-id }
      (merge maintenance {
        status: status-verified,
        supervisor: (some tx-sender),
        verified-at: (some stacks-block-height),
        verification-hash: (some verification-hash)
      })
    )
    
    (map-set technician-stats
      { technician: technician }
      (merge tech-stats {
        verified-jobs: (+ (get verified-jobs tech-stats) u1)
      })
    )
    
    (ok true)
  )
)

(define-public (verify-maintenance-data (maintenance-id uint) (expected-hash (string-ascii 64)))
  (let
    (
      (maintenance (unwrap! (map-get? maintenance-records { maintenance-id: maintenance-id }) err-not-found))
    )
    (ok (is-eq (get data-hash maintenance) expected-hash))
  )
)

;; title: maintenance-log
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

