;; Decentralized Insurance Protocol (DIP)

;; Define error constants with more specific messages
(define-constant ERR_INVALID_AMOUNT (err u100))
(define-constant ERR_INSUFFICIENT_FUNDS (err u101))
(define-constant ERR_CLAIM_NOT_FOUND (err u102))
(define-constant ERR_UNAUTHORIZED (err u103))
(define-constant ERR_ALREADY_INSURED (err u104))
(define-constant ERR_INVALID_PRINCIPAL (err u105))
(define-constant ERR_NOT_INSURED (err u106))
(define-constant ERR_ZERO_AMOUNT (err u107))
(define-constant ERR_CLAIM_ALREADY_PROCESSED (err u108))
(define-constant ERR_POOL_EMPTY (err u109))
(define-constant ERR_CLAIM_NOT_EXPIRED (err u110))
(define-constant ERR_CLAIM_EXCEEDS_COVERAGE (err u111))
(define-constant ERR_CONTRACT_PAUSED (err u112))
(define-constant ERR_PREMIUM_CALCULATION_FAILED (err u113))
(define-constant ERR_COVERAGE_PERIOD_EXPIRED (err u114))
(define-constant ERR_MINIMUM_COVERAGE_NOT_MET (err u115))

;; Define the contract
(define-data-var insurance-pool uint u0)
(define-data-var contract-owner principal tx-sender)
(define-data-var contract-paused bool false)
(define-data-var minimum-coverage-amount uint u1000000) ;; Minimum coverage amount in microSTX
(define-map insured-entities principal { coverage-amount: uint, expiry: uint })
(define-map insurance-claims { claimant: principal, amount: uint } { status: (string-ascii 20), timestamp: uint, paid-amount: uint, evidence-hash: (optional (buff 32)) })

;; Define the claim expiration period (e.g., 30 days in blocks, assuming 10-minute block times)
(define-constant CLAIM_EXPIRATION_PERIOD u4320)

;; Define standard coverage period (90 days in blocks)
(define-constant STANDARD_COVERAGE_PERIOD u12960)

;; Define guard for paused contract
(define-private (contract-not-paused)
  (not (var-get contract-paused)))

;; Helper function to calculate payout amount
(define-private (calculate-payout-amount (claim-amount uint) (pool-balance uint))
  (if (>= pool-balance claim-amount)
      claim-amount
      pool-balance))

;; Helper function to check if coverage is still valid
(define-private (is-coverage-valid (expiry uint))
  (<= block-height expiry))

;; Function to purchase insurance coverage
(define-public (purchase-coverage (amount uint) (period uint))
  (begin
    (asserts! (contract-not-paused) ERR_CONTRACT_PAUSED)
    (let (
      (caller tx-sender)
      (min-amount (var-get minimum-coverage-amount))
      (coverage-period (if (> period u0) period STANDARD_COVERAGE_PERIOD))
      (premium (unwrap! (calculate-premium amount coverage-period) ERR_PREMIUM_CALCULATION_FAILED))
    )
      (asserts! (>= amount min-amount) ERR_MINIMUM_COVERAGE_NOT_MET)
      (asserts! (> amount u0) ERR_ZERO_AMOUNT)
      (asserts! (is-none (map-get? insured-entities caller)) ERR_ALREADY_INSURED)
      (match (stx-transfer? premium caller (as-contract tx-sender))
        success (begin
          (var-set insurance-pool (+ (var-get insurance-pool) premium))
          (map-set insured-entities caller { coverage-amount: amount, expiry: (+ block-height coverage-period) })
          (print { event: "coverage-purchased", coverage-amount: amount, premium: premium, expiry: (+ block-height coverage-period), buyer: caller })
          (ok true))
        error (err error)))))

;; Function to increase existing coverage amount
(define-public (increase-coverage (additional-amount uint))
  (begin
    (asserts! (contract-not-paused) ERR_CONTRACT_PAUSED)
    (let (
      (caller tx-sender)
      (current-coverage (unwrap! (map-get? insured-entities caller) ERR_NOT_INSURED))
      (current-amount (get coverage-amount current-coverage))
      (current-expiry (get expiry current-coverage))
      (remaining-blocks (- current-expiry block-height))
      (premium (unwrap! (calculate-premium additional-amount remaining-blocks) ERR_PREMIUM_CALCULATION_FAILED))
    )
      (asserts! (> additional-amount u0) ERR_ZERO_AMOUNT)
      (asserts! (is-coverage-valid current-expiry) ERR_COVERAGE_PERIOD_EXPIRED)
      (match (stx-transfer? premium caller (as-contract tx-sender))
        success (begin
          (var-set insurance-pool (+ (var-get insurance-pool) premium))
          (map-set insured-entities caller { coverage-amount: (+ current-amount additional-amount), expiry: current-expiry })
          (print { event: "coverage-increased", additional-amount: additional-amount, new-total: (+ current-amount additional-amount), premium: premium, buyer: caller })
          (ok true))
        error (err error)))))

;; Function to extend coverage period
(define-public (extend-coverage-period (additional-period uint))
  (begin
    (asserts! (contract-not-paused) ERR_CONTRACT_PAUSED)
    (let (
      (caller tx-sender)
      (current-coverage (unwrap! (map-get? insured-entities caller) ERR_NOT_INSURED))
      (current-amount (get coverage-amount current-coverage))
      (current-expiry (get expiry current-coverage))
      (premium (unwrap! (calculate-premium current-amount additional-period) ERR_PREMIUM_CALCULATION_FAILED))
    )
      (asserts! (> additional-period u0) ERR_ZERO_AMOUNT)
      (asserts! (is-coverage-valid current-expiry) ERR_COVERAGE_PERIOD_EXPIRED)
      (match (stx-transfer? premium caller (as-contract tx-sender))
        success (begin
          (var-set insurance-pool (+ (var-get insurance-pool) premium))
          (map-set insured-entities caller { coverage-amount: current-amount, expiry: (+ current-expiry additional-period) })
          (print { event: "coverage-extended", amount: current-amount, new-expiry: (+ current-expiry additional-period), premium: premium, buyer: caller })
          (ok true))
        error (err error)))))

;; Function to cancel coverage and receive partial refund based on remaining time
(define-public (cancel-coverage)
  (begin
    (asserts! (contract-not-paused) ERR_CONTRACT_PAUSED)
    (let (
      (caller tx-sender)
      (current-coverage (unwrap! (map-get? insured-entities caller) ERR_NOT_INSURED))
      (current-amount (get coverage-amount current-coverage))
      (current-expiry (get expiry current-coverage))
      (remaining-blocks (- current-expiry block-height))
      (total-period STANDARD_COVERAGE_PERIOD)
      (refund-rate (/ (* remaining-blocks u100) total-period)) ;; Calculate percentage of time remaining
      (premium (unwrap! (calculate-premium current-amount total-period) ERR_PREMIUM_CALCULATION_FAILED))
      (refund-amount (/ (* premium refund-rate) u100))
    )
      (asserts! (is-coverage-valid current-expiry) ERR_COVERAGE_PERIOD_EXPIRED)
      ;; Check for any pending claims
      (asserts! (is-none (map-get? insurance-claims { claimant: caller, amount: current-amount })) ERR_CLAIM_ALREADY_PROCESSED)
      (match (as-contract (stx-transfer? refund-amount tx-sender caller))
        success (begin
          (var-set insurance-pool (- (var-get insurance-pool) refund-amount))
          (map-delete insured-entities caller)
          (print { event: "coverage-cancelled", coverage-amount: current-amount, refund-amount: refund-amount, owner: caller })
          (ok refund-amount))
        error (err error)))))

;; Function to file an insurance claim with optional evidence hash
(define-public (file-claim (claim-amount uint) (evidence-hash (optional (buff 32))))
  (begin
    (asserts! (contract-not-paused) ERR_CONTRACT_PAUSED)
    (let (
      (caller tx-sender)
      (coverage-data (unwrap! (map-get? insured-entities caller) ERR_NOT_INSURED))
      (coverage-amount (get coverage-amount coverage-data))
      (coverage-expiry (get expiry coverage-data))
    )
      (asserts! (> claim-amount u0) ERR_ZERO_AMOUNT)
      (asserts! (is-coverage-valid coverage-expiry) ERR_COVERAGE_PERIOD_EXPIRED)
      (asserts! (<= claim-amount coverage-amount) ERR_CLAIM_EXCEEDS_COVERAGE)
      (asserts! (is-none (map-get? insurance-claims { claimant: caller, amount: claim-amount })) ERR_CLAIM_ALREADY_PROCESSED)
      (map-set insurance-claims { claimant: caller, amount: claim-amount } { status: "pending", timestamp: block-height, paid-amount: u0, evidence-hash: evidence-hash })
      (print { event: "claim-filed", claimant: caller, claim-amount: claim-amount, timestamp: block-height, evidence-hash: evidence-hash })
      (ok true))))

;; Function to approve and pay out a claim
(define-public (approve-claim (claimant principal) (claim-amount uint))
  (begin
    (asserts! (contract-not-paused) ERR_CONTRACT_PAUSED)
    (let (
      (claim-key { claimant: claimant, amount: claim-amount })
      (claim-data (unwrap! (map-get? insurance-claims claim-key) ERR_CLAIM_NOT_FOUND))
      (pool-balance (var-get insurance-pool))
      (coverage-data (unwrap! (map-get? insured-entities claimant) ERR_NOT_INSURED))
      (coverage-amount (get coverage-amount coverage-data))
    )
      (asserts! (is-eq tx-sender (var-get contract-owner)) ERR_UNAUTHORIZED)
      (asserts! (is-eq (get status claim-data) "pending") ERR_CLAIM_ALREADY_PROCESSED)
      (asserts! (> pool-balance u0) ERR_POOL_EMPTY)
      (asserts! (<= claim-amount coverage-amount) ERR_CLAIM_EXCEEDS_COVERAGE)
      (asserts! (< (- block-height (get timestamp claim-data)) CLAIM_EXPIRATION_PERIOD) ERR_CLAIM_NOT_EXPIRED)
      (let ((payout-amount (calculate-payout-amount claim-amount pool-balance)))
        (match (as-contract (stx-transfer? payout-amount tx-sender claimant))
          success (begin
            (var-set insurance-pool (- pool-balance payout-amount))
            (if (< payout-amount claim-amount)
                (map-set insurance-claims claim-key { 
                  status: "partially-paid", 
                  timestamp: block-height, 
                  paid-amount: payout-amount, 
                  evidence-hash: (get evidence-hash claim-data) 
                })
                (begin
                  (map-delete insurance-claims claim-key)
                  (map-delete insured-entities claimant)))
            (print { event: "claim-approved", claimant: claimant, claim-amount: claim-amount, payout-amount: payout-amount })
            (ok payout-amount))
          error (err error))))))

;; Function to reject a claim
(define-public (reject-claim (claimant principal) (claim-amount uint) (reason (string-ascii 100)))
  (begin
    (asserts! (contract-not-paused) ERR_CONTRACT_PAUSED)
    (let (
      (claim-key { claimant: claimant, amount: claim-amount })
      (claim-data (unwrap! (map-get? insurance-claims claim-key) ERR_CLAIM_NOT_FOUND))
    )
      (asserts! (is-eq tx-sender (var-get contract-owner)) ERR_UNAUTHORIZED)
      (asserts! (is-eq (get status claim-data) "pending") ERR_CLAIM_ALREADY_PROCESSED)
      (asserts! (< (- block-height (get timestamp claim-data)) CLAIM_EXPIRATION_PERIOD) ERR_CLAIM_NOT_EXPIRED)
      (map-set insurance-claims claim-key { 
        status: "rejected", 
        timestamp: (get timestamp claim-data), 
        paid-amount: u0, 
        evidence-hash: (get evidence-hash claim-data) 
      })
      (print { event: "claim-rejected", claimant: claimant, claim-amount: claim-amount, reason: reason })
      (ok true))))

;; Function to check and expire a single claim
(define-public (check-and-expire-claim (claimant principal) (claim-amount uint))
  (let (
    (claim-key { claimant: claimant, amount: claim-amount })
    (claim-data (unwrap! (map-get? insurance-claims claim-key) ERR_CLAIM_NOT_FOUND))
  )
    (if (and (is-eq (get status claim-data) "pending")
             (>= (- block-height (get timestamp claim-data)) CLAIM_EXPIRATION_PERIOD))
        (begin
          (map-set insurance-claims claim-key { 
            status: "expired", 
            timestamp: (get timestamp claim-data), 
            paid-amount: u0, 
            evidence-hash: (get evidence-hash claim-data) 
          })
          (print { event: "claim-expired", claimant: claimant, claim-amount: claim-amount })
          (ok true))
        (ok false))))

;; Function to change the contract owner
(define-public (change-contract-owner (new-owner principal))
  (begin
    (asserts! (contract-not-paused) ERR_CONTRACT_PAUSED)
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR_UNAUTHORIZED)
    (asserts! (not (is-eq new-owner 'SP000000000000000000002Q6VF78)) ERR_INVALID_PRINCIPAL)
    (print { event: "contract-owner-changed", old-owner: (var-get contract-owner), new-owner: new-owner })
    (ok (var-set contract-owner new-owner))))

;; Function to pause contract in emergency
(define-public (set-contract-pause (paused bool))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR_UNAUTHORIZED)
    (ok (var-set contract-paused paused))))

;; Function to set minimum coverage amount
(define-public (set-minimum-coverage (amount uint))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR_UNAUTHORIZED)
    (asserts! (> amount u0) ERR_ZERO_AMOUNT)
    (print { event: "minimum-coverage-changed", old-minimum: (var-get minimum-coverage-amount), new-minimum: amount })
    (ok (var-set minimum-coverage-amount amount))))

;; Function to calculate insurance premium based on amount and duration
(define-read-only (calculate-premium (amount uint) (duration uint))
  (let (
    (base-premium-rate u2) ;; 0.2% base premium rate (2/1000)
    (duration-multiplier (/ duration u144)) ;; Normalize duration to days (assuming 144 blocks per day)
    (risk-adjustment-factor u12) ;; Risk adjustment factor (1.2 represented as 12/10)
  )
    (ok (/ (* amount (* base-premium-rate duration-multiplier risk-adjustment-factor)) u10000))))

;; Read-only functions

;; Function to get the current insurance pool balance
(define-read-only (get-pool-balance)
  (ok (var-get insurance-pool)))

;; Function to check if an entity is insured
(define-read-only (is-insured (entity principal))
  (is-some (map-get? insured-entities entity)))

;; Function to get the coverage details for an entity
(define-read-only (get-coverage-details (entity principal))
  (match (map-get? insured-entities entity)
    coverage (ok { 
      coverage-amount: (get coverage-amount coverage), 
      expiry: (get expiry coverage),
      is-valid: (is-coverage-valid (get expiry coverage)),
      remaining-blocks: (- (get expiry coverage) block-height)
    })
    ERR_NOT_INSURED))

;; Function to get the claim status
(define-read-only (get-claim-status (claimant principal) (claim-amount uint))
  (match (map-get? insurance-claims { claimant: claimant, amount: claim-amount })
    claim-data (ok { 
      status: (get status claim-data), 
      timestamp: (get timestamp claim-data), 
      paid-amount: (get paid-amount claim-data),
      evidence-hash: (get evidence-hash claim-data)
    })
    ERR_CLAIM_NOT_FOUND))

;; Function to get all pending claims for an entity
(define-read-only (get-pending-claims (entity principal))
  (ok {
    entity: entity,
    coverage: (map-get? insured-entities entity),
    has-coverage: (is-some (map-get? insured-entities entity)),
    pending-claim: (map-get? insurance-claims { 
      claimant: entity, 
      amount: (get coverage-amount (default-to { coverage-amount: u0, expiry: u0 } (map-get? insured-entities entity))) 
    })
  }))

;; Function to get contract statistics
(define-read-only (get-contract-stats)
  (ok {
    pool-balance: (var-get insurance-pool),
    is-paused: (var-get contract-paused),
    owner: (var-get contract-owner),
    minimum-coverage: (var-get minimum-coverage-amount),
    claim-expiration-period: CLAIM_EXPIRATION_PERIOD,
    standard-coverage-period: STANDARD_COVERAGE_PERIOD
  }))