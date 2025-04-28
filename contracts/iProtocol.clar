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
