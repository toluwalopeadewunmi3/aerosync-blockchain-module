;; Payment Mirror Smart Contract
;; Anchors hashes of off-chain financial transactions
;; for transparent reconciliation between airlines, handlers, and service providers

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-found (err u101))
(define-constant err-unauthorized (err u102))
(define-constant err-invalid-data (err u103))
(define-constant err-already-settled (err u104))
(define-constant err-invalid-status (err u105))

;; Data Variables
(define-data-var payment-nonce uint u0)

;; Payment Status Types
(define-constant status-pending "PENDING")
(define-constant status-processing "PROCESSING")
(define-constant status-settled "SETTLED")
(define-constant status-disputed "DISPUTED")
(define-constant status-refunded "REFUNDED")

;; Payment Types
(define-constant type-cargo "CARGO_FEE")
(define-constant type-maintenance "MAINTENANCE")
(define-constant type-handling "HANDLING_FEE")
(define-constant type-fuel "FUEL")
(define-constant type-parking "PARKING")
(define-constant type-other "OTHER")

;; Data Maps
(define-map payment-records
  { payment-id: uint }
  {
    payer: principal,
    payee: principal,
    amount: uint,
    currency: (string-ascii 10),
    payment-type: (string-ascii 20),
    invoice-hash: (string-ascii 64),
    transaction-hash: (optional (string-ascii 64)),
    status: (string-ascii 20),
    reference-id: (string-ascii 100),
    data-hash: (string-ascii 64),
    created-at: uint,
    settled-at: (optional uint),
    notes: (string-ascii 200)
  }
)

(define-map payment-disputes
  { payment-id: uint }
  {
    disputed-by: principal,
    dispute-reason: (string-ascii 200),
    dispute-hash: (string-ascii 64),
    disputed-at: uint,
    resolved: bool,
    resolved-at: (optional uint)
  }
)

(define-map payer-payment-history
  { payer: principal, sequence: uint }
  { payment-id: uint, amount: uint, timestamp: uint }
)

(define-map payee-payment-history
  { payee: principal, sequence: uint }
  { payment-id: uint, amount: uint, timestamp: uint }
)

(define-map payer-stats
  { payer: principal }
  { total-payments: uint, total-amount: uint, pending-amount: uint }
)

(define-map payee-stats
  { payee: principal }
  { total-received: uint, total-amount: uint, pending-amount: uint }
)

(define-map payment-type-stats
  { payment-type: (string-ascii 20) }
  { count: uint, total-amount: uint }
)

;; Authorization Maps
(define-map authorized-payers
  { payer: principal }
  { authorized: bool }
)

(define-map authorized-payees
  { payee: principal }
  { authorized: bool }
)

;; Read-only functions

(define-read-only (get-payment-record (payment-id uint))
  (map-get? payment-records { payment-id: payment-id })
)

(define-read-only (get-payment-dispute (payment-id uint))
  (map-get? payment-disputes { payment-id: payment-id })
)

(define-read-only (get-payer-payment-history (payer principal) (sequence uint))
  (map-get? payer-payment-history { payer: payer, sequence: sequence })
)

(define-read-only (get-payee-payment-history (payee principal) (sequence uint))
  (map-get? payee-payment-history { payee: payee, sequence: sequence })
)

(define-read-only (get-payer-stats (payer principal))
  (default-to { total-payments: u0, total-amount: u0, pending-amount: u0 } 
    (map-get? payer-stats { payer: payer }))
)

(define-read-only (get-payee-stats (payee principal))
  (default-to { total-received: u0, total-amount: u0, pending-amount: u0 } 
    (map-get? payee-stats { payee: payee }))
)

(define-read-only (get-payment-type-stats (payment-type (string-ascii 20)))
  (default-to { count: u0, total-amount: u0 } 
    (map-get? payment-type-stats { payment-type: payment-type }))
)

(define-read-only (is-payer-authorized (payer principal))
  (match (map-get? authorized-payers { payer: payer })
    entry (get authorized entry)
    false
  )
)

(define-read-only (is-payee-authorized (payee principal))
  (match (map-get? authorized-payees { payee: payee })
    entry (get authorized entry)
    false
  )
)

(define-read-only (get-current-payment-nonce)
  (var-get payment-nonce)
)

;; Public functions

(define-public (authorize-payer (payer principal))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (ok (map-set authorized-payers
      { payer: payer }
      { authorized: true }
    ))
  )
)

(define-public (authorize-payee (payee principal))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (ok (map-set authorized-payees
      { payee: payee }
      { authorized: true }
    ))
  )
)

(define-public (revoke-payer (payer principal))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (ok (map-delete authorized-payers { payer: payer }))
  )
)

(define-public (record-payment
  (payee principal)
  (amount uint)
  (currency (string-ascii 10))
  (payment-type (string-ascii 20))
  (invoice-hash (string-ascii 64))
  (reference-id (string-ascii 100))
  (data-hash (string-ascii 64))
  (notes (string-ascii 200))
)
  (let
    (
      (new-payment-id (+ (var-get payment-nonce) u1))
      (payer-current-stats (get-payer-stats tx-sender))
      (payee-current-stats (get-payee-stats payee))
      (type-stats (get-payment-type-stats payment-type))
      (payer-count (get total-payments payer-current-stats))
      (payee-count (get total-received payee-current-stats))
    )
    (asserts! (is-payer-authorized tx-sender) err-unauthorized)
    (asserts! (is-payee-authorized payee) err-unauthorized)
    (asserts! (> amount u0) err-invalid-data)
    (asserts! (> (len currency) u0) err-invalid-data)
    (asserts! (> (len reference-id) u0) err-invalid-data)
    
    (map-set payment-records
      { payment-id: new-payment-id }
      {
        payer: tx-sender,
        payee: payee,
        amount: amount,
        currency: currency,
        payment-type: payment-type,
        invoice-hash: invoice-hash,
        transaction-hash: none,
        status: status-pending,
        reference-id: reference-id,
        data-hash: data-hash,
        created-at: stacks-block-height,
        settled-at: none,
        notes: notes
      }
    )
    
    (map-set payer-payment-history
      { payer: tx-sender, sequence: payer-count }
      { payment-id: new-payment-id, amount: amount, timestamp: stacks-block-height }
    )
    
    (map-set payee-payment-history
      { payee: payee, sequence: payee-count }
      { payment-id: new-payment-id, amount: amount, timestamp: stacks-block-height }
    )
    
    (map-set payer-stats
      { payer: tx-sender }
      {
        total-payments: (+ payer-count u1),
        total-amount: (+ (get total-amount payer-current-stats) amount),
        pending-amount: (+ (get pending-amount payer-current-stats) amount)
      }
    )
    
    (map-set payee-stats
      { payee: payee }
      {
        total-received: (+ payee-count u1),
        total-amount: (+ (get total-amount payee-current-stats) amount),
        pending-amount: (+ (get pending-amount payee-current-stats) amount)
      }
    )
    
    (map-set payment-type-stats
      { payment-type: payment-type }
      {
        count: (+ (get count type-stats) u1),
        total-amount: (+ (get total-amount type-stats) amount)
      }
    )
    
    (var-set payment-nonce new-payment-id)
    (ok new-payment-id)
  )
)

(define-public (settle-payment
  (payment-id uint)
  (transaction-hash (string-ascii 64))
)
  (let
    (
      (payment (unwrap! (map-get? payment-records { payment-id: payment-id }) err-not-found))
      (payer (get payer payment))
      (payee (get payee payment))
      (amount (get amount payment))
      (payer-current-stats (get-payer-stats payer))
      (payee-current-stats (get-payee-stats payee))
    )
    (asserts! (or (is-eq tx-sender payer) (is-eq tx-sender payee) (is-eq tx-sender contract-owner)) err-unauthorized)
    (asserts! (is-eq (get status payment) status-pending) err-already-settled)
    
    (map-set payment-records
      { payment-id: payment-id }
      (merge payment {
        status: status-settled,
        transaction-hash: (some transaction-hash),
        settled-at: (some stacks-block-height)
      })
    )
    
    (map-set payer-stats
      { payer: payer }
      (merge payer-current-stats {
        pending-amount: (- (get pending-amount payer-current-stats) amount)
      })
    )
    
    (map-set payee-stats
      { payee: payee }
      (merge payee-current-stats {
        pending-amount: (- (get pending-amount payee-current-stats) amount)
      })
    )
    
    (ok true)
  )
)

(define-public (dispute-payment
  (payment-id uint)
  (dispute-reason (string-ascii 200))
  (dispute-hash (string-ascii 64))
)
  (let
    (
      (payment (unwrap! (map-get? payment-records { payment-id: payment-id }) err-not-found))
    )
    (asserts! (or (is-eq tx-sender (get payer payment)) (is-eq tx-sender (get payee payment))) err-unauthorized)
    (asserts! (not (is-eq (get status payment) status-settled)) err-already-settled)
    
    (map-set payment-disputes
      { payment-id: payment-id }
      {
        disputed-by: tx-sender,
        dispute-reason: dispute-reason,
        dispute-hash: dispute-hash,
        disputed-at: stacks-block-height,
        resolved: false,
        resolved-at: none
      }
    )
    
    (map-set payment-records
      { payment-id: payment-id }
      (merge payment { status: status-disputed })
    )
    
    (ok true)
  )
)

(define-public (resolve-dispute (payment-id uint))
  (let
    (
      (payment (unwrap! (map-get? payment-records { payment-id: payment-id }) err-not-found))
      (dispute (unwrap! (map-get? payment-disputes { payment-id: payment-id }) err-not-found))
    )
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (asserts! (is-eq (get status payment) status-disputed) err-invalid-status)
    (asserts! (not (get resolved dispute)) err-invalid-status)
    
    (map-set payment-disputes
      { payment-id: payment-id }
      (merge dispute {
        resolved: true,
        resolved-at: (some stacks-block-height)
      })
    )
    
    (map-set payment-records
      { payment-id: payment-id }
      (merge payment { status: status-pending })
    )
    
    (ok true)
  )
)

(define-public (verify-payment (payment-id uint) (expected-hash (string-ascii 64)))
  (let
    (
      (payment (unwrap! (map-get? payment-records { payment-id: payment-id }) err-not-found))
    )
    (ok (is-eq (get data-hash payment) expected-hash))
  )
)

;; title: payment-mirror
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

