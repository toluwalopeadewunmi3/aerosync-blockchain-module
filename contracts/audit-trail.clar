;; Audit Trail Smart Contract
;; Records every platform action (create/update/delete) with principal IDs
;; and timestamps to maintain transparent regulatory audit trails

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-found (err u101))
(define-constant err-unauthorized (err u102))
(define-constant err-invalid-data (err u103))

;; Data Variables
(define-data-var audit-nonce uint u0)

;; Action Types
(define-constant action-create "CREATE")
(define-constant action-update "UPDATE")
(define-constant action-delete "DELETE")
(define-constant action-read "READ")
(define-constant action-verify "VERIFY")
(define-constant action-approve "APPROVE")
(define-constant action-reject "REJECT")

;; Entity Types
(define-constant entity-cargo "CARGO")
(define-constant entity-maintenance "MAINTENANCE")
(define-constant entity-payment "PAYMENT")
(define-constant entity-user "USER")
(define-constant entity-handler "HANDLER")
(define-constant entity-aircraft "AIRCRAFT")

;; Data Maps
(define-map audit-records
  { audit-id: uint }
  {
    actor: principal,
    action-type: (string-ascii 20),
    entity-type: (string-ascii 20),
    entity-id: (string-ascii 100),
    description: (string-ascii 200),
    data-hash: (string-ascii 64),
    ip-hash: (optional (string-ascii 64)),
    timestamp: uint,
    stacks-block-height: uint,
    metadata: (string-ascii 200)
  }
)

(define-map actor-audit-history
  { actor: principal, sequence: uint }
  { audit-id: uint, timestamp: uint }
)

(define-map actor-audit-count
  { actor: principal }
  { count: uint }
)

(define-map entity-audit-history
  { entity-type: (string-ascii 20), entity-id: (string-ascii 100), sequence: uint }
  { audit-id: uint, timestamp: uint, action-type: (string-ascii 20) }
)

(define-map entity-audit-count
  { entity-type: (string-ascii 20), entity-id: (string-ascii 100) }
  { count: uint }
)

(define-map action-type-count
  { action-type: (string-ascii 20) }
  { count: uint, last-occurrence: uint }
)

;; Authorization Map
(define-map authorized-auditors
  { auditor: principal }
  { authorized: bool, access-level: uint }
)

(define-map authorized-loggers
  { logger: principal }
  { authorized: bool }
)

;; Read-only functions

(define-read-only (get-audit-record (audit-id uint))
  (map-get? audit-records { audit-id: audit-id })
)

(define-read-only (get-actor-audit-history (actor principal) (sequence uint))
  (map-get? actor-audit-history { actor: actor, sequence: sequence })
)

(define-read-only (get-actor-audit-count (actor principal))
  (default-to { count: u0 } (map-get? actor-audit-count { actor: actor }))
)

(define-read-only (get-entity-audit-history 
  (entity-type (string-ascii 20))
  (entity-id (string-ascii 100))
  (sequence uint)
)
  (map-get? entity-audit-history { entity-type: entity-type, entity-id: entity-id, sequence: sequence })
)

(define-read-only (get-entity-audit-count
  (entity-type (string-ascii 20))
  (entity-id (string-ascii 100))
)
  (default-to { count: u0 } (map-get? entity-audit-count { entity-type: entity-type, entity-id: entity-id }))
)

(define-read-only (get-action-type-stats (action-type (string-ascii 20)))
  (default-to { count: u0, last-occurrence: u0 } (map-get? action-type-count { action-type: action-type }))
)

(define-read-only (is-auditor-authorized (auditor principal))
  (match (map-get? authorized-auditors { auditor: auditor })
    entry (get authorized entry)
    false
  )
)

(define-read-only (is-logger-authorized (logger principal))
  (match (map-get? authorized-loggers { logger: logger })
    entry (get authorized entry)
    false
  )
)

(define-read-only (get-current-audit-nonce)
  (var-get audit-nonce)
)

;; Public functions

(define-public (authorize-auditor (auditor principal) (access-level uint))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (ok (map-set authorized-auditors
      { auditor: auditor }
      { authorized: true, access-level: access-level }
    ))
  )
)

(define-public (authorize-logger (logger principal))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (ok (map-set authorized-loggers
      { logger: logger }
      { authorized: true }
    ))
  )
)

(define-public (revoke-auditor (auditor principal))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (ok (map-delete authorized-auditors { auditor: auditor }))
  )
)

(define-public (log-action
  (action-type (string-ascii 20))
  (entity-type (string-ascii 20))
  (entity-id (string-ascii 100))
  (description (string-ascii 200))
  (data-hash (string-ascii 64))
  (metadata (string-ascii 200))
)
  (let
    (
      (new-audit-id (+ (var-get audit-nonce) u1))
      (actor-count (get count (get-actor-audit-count tx-sender)))
      (entity-count (get count (get-entity-audit-count entity-type entity-id)))
      (action-stats (get-action-type-stats action-type))
    )
    (asserts! (or (is-logger-authorized tx-sender) (is-eq tx-sender contract-owner)) err-unauthorized)
    (asserts! (> (len action-type) u0) err-invalid-data)
    (asserts! (> (len entity-type) u0) err-invalid-data)
    (asserts! (> (len entity-id) u0) err-invalid-data)
    
    (map-set audit-records
      { audit-id: new-audit-id }
      {
        actor: tx-sender,
        action-type: action-type,
        entity-type: entity-type,
        entity-id: entity-id,
        description: description,
        data-hash: data-hash,
        ip-hash: none,
        timestamp: stacks-block-height,
        stacks-block-height: stacks-block-height,
        metadata: metadata
      }
    )
    
    (map-set actor-audit-history
      { actor: tx-sender, sequence: actor-count }
      { audit-id: new-audit-id, timestamp: stacks-block-height }
    )
    
    (map-set actor-audit-count
      { actor: tx-sender }
      { count: (+ actor-count u1) }
    )
    
    (map-set entity-audit-history
      { entity-type: entity-type, entity-id: entity-id, sequence: entity-count }
      { audit-id: new-audit-id, timestamp: stacks-block-height, action-type: action-type }
    )
    
    (map-set entity-audit-count
      { entity-type: entity-type, entity-id: entity-id }
      { count: (+ entity-count u1) }
    )
    
    (map-set action-type-count
      { action-type: action-type }
      { count: (+ (get count action-stats) u1), last-occurrence: stacks-block-height }
    )
    
    (var-set audit-nonce new-audit-id)
    (ok new-audit-id)
  )
)

(define-public (log-action-with-ip
  (action-type (string-ascii 20))
  (entity-type (string-ascii 20))
  (entity-id (string-ascii 100))
  (description (string-ascii 200))
  (data-hash (string-ascii 64))
  (metadata (string-ascii 200))
  (ip-hash (string-ascii 64))
)
  (let
    (
      (new-audit-id (+ (var-get audit-nonce) u1))
      (actor-count (get count (get-actor-audit-count tx-sender)))
      (entity-count (get count (get-entity-audit-count entity-type entity-id)))
      (action-stats (get-action-type-stats action-type))
    )
    (asserts! (or (is-logger-authorized tx-sender) (is-eq tx-sender contract-owner)) err-unauthorized)
    (asserts! (> (len action-type) u0) err-invalid-data)
    (asserts! (> (len entity-type) u0) err-invalid-data)
    (asserts! (> (len entity-id) u0) err-invalid-data)
    
    (map-set audit-records
      { audit-id: new-audit-id }
      {
        actor: tx-sender,
        action-type: action-type,
        entity-type: entity-type,
        entity-id: entity-id,
        description: description,
        data-hash: data-hash,
        ip-hash: (some ip-hash),
        timestamp: stacks-block-height,
        stacks-block-height: stacks-block-height,
        metadata: metadata
      }
    )
    
    (map-set actor-audit-history
      { actor: tx-sender, sequence: actor-count }
      { audit-id: new-audit-id, timestamp: stacks-block-height }
    )
    
    (map-set actor-audit-count
      { actor: tx-sender }
      { count: (+ actor-count u1) }
    )
    
    (map-set entity-audit-history
      { entity-type: entity-type, entity-id: entity-id, sequence: entity-count }
      { audit-id: new-audit-id, timestamp: stacks-block-height, action-type: action-type }
    )
    
    (map-set entity-audit-count
      { entity-type: entity-type, entity-id: entity-id }
      { count: (+ entity-count u1) }
    )
    
    (map-set action-type-count
      { action-type: action-type }
      { count: (+ (get count action-stats) u1), last-occurrence: stacks-block-height }
    )
    
    (var-set audit-nonce new-audit-id)
    (ok new-audit-id)
  )
)

(define-public (verify-audit-record (audit-id uint) (expected-hash (string-ascii 64)))
  (let
    (
      (audit (unwrap! (map-get? audit-records { audit-id: audit-id }) err-not-found))
    )
    (ok (is-eq (get data-hash audit) expected-hash))
  )
)

;; title: audit-trail
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

