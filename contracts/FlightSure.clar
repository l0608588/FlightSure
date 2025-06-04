(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-found (err u101))
(define-constant err-already-exists (err u102))
(define-constant err-insufficient-funds (err u103))
(define-constant err-invalid-amount (err u104))
(define-constant err-policy-expired (err u105))
(define-constant err-already-claimed (err u106))
(define-constant err-flight-not-delayed (err u107))
(define-constant err-unauthorized (err u108))

(define-data-var next-policy-id uint u1)
(define-data-var oracle-address principal tx-sender)
(define-data-var min-premium uint u1000000)
(define-data-var max-coverage uint u100000000)
(define-data-var delay-threshold uint u120)

(define-map policies
  { policy-id: uint }
  {
    holder: principal,
    flight-number: (string-ascii 10),
    departure-date: uint,
    premium-paid: uint,
    coverage-amount: uint,
    is-active: bool,
    is-claimed: bool,
    created-at: uint
  }
)

(define-map flight-delays
  { flight-number: (string-ascii 10), date: uint }
  { delay-minutes: uint, verified: bool, timestamp: uint }
)

(define-map user-policies
  { user: principal }
  { policy-ids: (list 50 uint) }
)

(define-public (set-oracle (new-oracle principal))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (ok (var-set oracle-address new-oracle))
  )
)

(define-public (set-min-premium (amount uint))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (asserts! (> amount u0) err-invalid-amount)
    (ok (var-set min-premium amount))
  )
)

(define-public (set-max-coverage (amount uint))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (asserts! (> amount u0) err-invalid-amount)
    (ok (var-set max-coverage amount))
  )
)

(define-public (set-delay-threshold (minutes uint))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (ok (var-set delay-threshold minutes))
  )
)

(define-public (purchase-policy (flight-number (string-ascii 10)) (departure-date uint) (coverage-amount uint))
  (let
    (
      (policy-id (var-get next-policy-id))
      (premium (calculate-premium coverage-amount))
      (current-policies (default-to { policy-ids: (list) } (map-get? user-policies { user: tx-sender })))
    )
    (asserts! (>= coverage-amount (var-get min-premium)) err-invalid-amount)
    (asserts! (<= coverage-amount (var-get max-coverage)) err-invalid-amount)
    (asserts! (> departure-date stacks-block-height) err-policy-expired)
    (try! (stx-transfer? premium tx-sender (as-contract tx-sender)))
    (map-set policies
      { policy-id: policy-id }
      {
        holder: tx-sender,
        flight-number: flight-number,
        departure-date: departure-date,
        premium-paid: premium,
        coverage-amount: coverage-amount,
        is-active: true,
        is-claimed: false,
        created-at: stacks-block-height
      }
    )
    (map-set user-policies
      { user: tx-sender }
      { policy-ids: (unwrap! (as-max-len? (append (get policy-ids current-policies) policy-id) u50) err-invalid-amount) }
    )
    (var-set next-policy-id (+ policy-id u1))
    (ok policy-id)
  )
)

(define-public (report-flight-delay (flight-number (string-ascii 10)) (date uint) (delay-minutes uint))
  (begin
    (asserts! (is-eq tx-sender (var-get oracle-address)) err-unauthorized)
    (map-set flight-delays
      { flight-number: flight-number, date: date }
      { delay-minutes: delay-minutes, verified: true, timestamp: stacks-block-height }
    )
    (ok true)
  )
)

(define-public (claim-insurance (policy-id uint))
  (let
    (
      (policy (unwrap! (map-get? policies { policy-id: policy-id }) err-not-found))
      (flight-delay (map-get? flight-delays { flight-number: (get flight-number policy), date: (get departure-date policy) }))
    )
    (asserts! (is-eq tx-sender (get holder policy)) err-unauthorized)
    (asserts! (get is-active policy) err-not-found)
    (asserts! (not (get is-claimed policy)) err-already-claimed)
    (asserts! (is-some flight-delay) err-flight-not-delayed)
    (asserts! (>= (get delay-minutes (unwrap-panic flight-delay)) (var-get delay-threshold)) err-flight-not-delayed)
    (asserts! (get verified (unwrap-panic flight-delay)) err-flight-not-delayed)
    (try! (as-contract (stx-transfer? (get coverage-amount policy) tx-sender (get holder policy))))
    (map-set policies
      { policy-id: policy-id }
      (merge policy { is-claimed: true, is-active: false })
    )
    (ok (get coverage-amount policy))
  )
)

(define-public (cancel-policy (policy-id uint))
  (let
    (
      (policy (unwrap! (map-get? policies { policy-id: policy-id }) err-not-found))
      (refund-amount (/ (get premium-paid policy) u2))
    )
    (asserts! (is-eq tx-sender (get holder policy)) err-unauthorized)
    (asserts! (get is-active policy) err-not-found)
    (asserts! (not (get is-claimed policy)) err-already-claimed)
    (asserts! (> (get departure-date policy) stacks-block-height) err-policy-expired)
    (try! (as-contract (stx-transfer? refund-amount tx-sender (get holder policy))))
    (map-set policies
      { policy-id: policy-id }
      (merge policy { is-active: false })
    )
    (ok refund-amount)
  )
)

(define-public (withdraw-funds (amount uint))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (asserts! (<= amount (stx-get-balance (as-contract tx-sender))) err-insufficient-funds)
    (as-contract (stx-transfer? amount tx-sender contract-owner))
  )
)

(define-read-only (get-policy (policy-id uint))
  (map-get? policies { policy-id: policy-id })
)

(define-read-only (get-flight-delay (flight-number (string-ascii 10)) (date uint))
  (map-get? flight-delays { flight-number: flight-number, date: date })
)

(define-read-only (get-user-policies (user principal))
  (map-get? user-policies { user: user })
)

(define-read-only (calculate-premium (coverage-amount uint))
  (/ coverage-amount u20)
)

(define-read-only (get-contract-balance)
  (stx-get-balance (as-contract tx-sender))
)

(define-read-only (get-next-policy-id)
  (var-get next-policy-id)
)

(define-read-only (get-oracle-address)
  (var-get oracle-address)
)

(define-read-only (get-min-premium)
  (var-get min-premium)
)

(define-read-only (get-max-coverage)
  (var-get max-coverage)
)

(define-read-only (get-delay-threshold)
  (var-get delay-threshold)
)

(define-read-only (is-policy-claimable (policy-id uint))
  (let
    (
      (policy (map-get? policies { policy-id: policy-id }))
      (flight-delay (match policy
        some-policy (map-get? flight-delays { flight-number: (get flight-number some-policy), date: (get departure-date some-policy) })
        none
      ))
    )
    (match policy
      some-policy
        (and
          (get is-active some-policy)
          (not (get is-claimed some-policy))
          (match flight-delay
            some-delay (and (get verified some-delay) (>= (get delay-minutes some-delay) (var-get delay-threshold)))
            false
          )
        )
      false
    )
  )
)