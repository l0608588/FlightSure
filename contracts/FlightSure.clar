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
(define-constant err-group-not-found (err u109))
(define-constant err-not-group-member (err u110))
(define-constant err-group-full (err u111))
(define-constant err-insufficient-balance (err u112))
(define-constant err-invalid-member (err u113))

(define-data-var next-policy-id uint u1)
(define-data-var oracle-address principal tx-sender)
(define-data-var min-premium uint u1000000)
(define-data-var max-coverage uint u100000000)
(define-data-var delay-threshold uint u120)
(define-data-var next-group-id uint u1)
(define-data-var group-discount-rate uint u10)

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

(define-map group-policies
  { group-id: uint }
  {
    owner: principal,
    name: (string-ascii 50),
    members: (list 100 principal),
    balance: uint,
    policy-ids: (list 200 uint),
    is-active: bool,
    created-at: uint,
    member-count: uint
  }
)

(define-map group-memberships
  { user: principal }
  { group-ids: (list 20 uint) }
)

(define-map group-member-balances
  { group-id: uint, member: principal }
  { balance: uint, allocated-at: uint }
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

(define-public (set-group-discount-rate (rate uint))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (asserts! (<= rate u50) err-invalid-amount)
    (ok (var-set group-discount-rate rate))
  )
)

(define-public (create-group (name (string-ascii 50)) (initial-balance uint))
  (let
    (
      (group-id (var-get next-group-id))
    )
    (asserts! (> initial-balance u0) err-invalid-amount)
    (try! (stx-transfer? initial-balance tx-sender (as-contract tx-sender)))
    (map-set group-policies
      { group-id: group-id }
      {
        owner: tx-sender,
        name: name,
        members: (list tx-sender),
        balance: initial-balance,
        policy-ids: (list),
        is-active: true,
        created-at: stacks-block-height,
        member-count: u1
      }
    )
    (map-set group-memberships
      { user: tx-sender }
      { group-ids: (list group-id) }
    )
    (var-set next-group-id (+ group-id u1))
    (ok group-id)
  )
)

(define-public (join-group (group-id uint))
  (let
    (
      (group (unwrap! (map-get? group-policies { group-id: group-id }) err-group-not-found))
      (current-memberships (default-to { group-ids: (list) } (map-get? group-memberships { user: tx-sender })))
      (current-members (get members group))
      (member-count (get member-count group))
    )
    (asserts! (get is-active group) err-group-not-found)
    (asserts! (< member-count u100) err-group-full)
    (asserts! (is-none (index-of current-members tx-sender)) err-already-exists)
    (map-set group-policies
      { group-id: group-id }
      (merge group {
        members: (unwrap! (as-max-len? (append current-members tx-sender) u100) err-group-full),
        member-count: (+ member-count u1)
      })
    )
    (map-set group-memberships
      { user: tx-sender }
      { group-ids: (unwrap! (as-max-len? (append (get group-ids current-memberships) group-id) u20) err-group-full) }
    )
    (ok true)
  )
)

(define-public (leave-group (group-id uint))
  (let
    (
      (group (unwrap! (map-get? group-policies { group-id: group-id }) err-group-not-found))
      (current-memberships (unwrap! (map-get? group-memberships { user: tx-sender }) err-not-group-member))
      (current-members (get members group))
      (member-balance (default-to { balance: u0, allocated-at: u0 } (map-get? group-member-balances { group-id: group-id, member: tx-sender })))
    )
    (asserts! (is-some (index-of current-members tx-sender)) err-not-group-member)
    (asserts! (not (is-eq tx-sender (get owner group))) err-unauthorized)
    (let
      (
        (updated-members (filter is-not-leaving-member current-members))
        (refund-amount (get balance member-balance))
      )
      (if (> refund-amount u0)
        (begin
          (try! (as-contract (stx-transfer? refund-amount tx-sender tx-sender)))
          (map-delete group-member-balances { group-id: group-id, member: tx-sender })
          (map-set group-policies
            { group-id: group-id }
            (merge group {
              members: updated-members,
              member-count: (- (get member-count group) u1),
              balance: (- (get balance group) refund-amount)
            })
          )
        )
        (map-set group-policies
          { group-id: group-id }
          (merge group {
            members: updated-members,
            member-count: (- (get member-count group) u1)
          })
        )
      )
      (map-set group-memberships
        { user: tx-sender }
        { group-ids: (filter is-not-leaving-group (get group-ids current-memberships)) }
      )
      (ok true)
    )
  )
)

(define-public (fund-group (group-id uint) (amount uint))
  (let
    (
      (group (unwrap! (map-get? group-policies { group-id: group-id }) err-group-not-found))
      (current-members (get members group))
    )
    (asserts! (is-some (index-of current-members tx-sender)) err-not-group-member)
    (asserts! (> amount u0) err-invalid-amount)
    (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
    (map-set group-policies
      { group-id: group-id }
      (merge group { balance: (+ (get balance group) amount) })
    )
    (ok true)
  )
)

(define-public (allocate-member-balance (group-id uint) (member principal) (amount uint))
  (let
    (
      (group (unwrap! (map-get? group-policies { group-id: group-id }) err-group-not-found))
      (current-members (get members group))
      (current-balance (default-to { balance: u0, allocated-at: u0 } (map-get? group-member-balances { group-id: group-id, member: member })))
    )
    (asserts! (is-eq tx-sender (get owner group)) err-unauthorized)
    (asserts! (is-some (index-of current-members member)) err-not-group-member)
    (asserts! (> amount u0) err-invalid-amount)
    (asserts! (>= (get balance group) amount) err-insufficient-balance)
    (map-set group-member-balances
      { group-id: group-id, member: member }
      { balance: (+ (get balance current-balance) amount), allocated-at: stacks-block-height }
    )
    (map-set group-policies
      { group-id: group-id }
      (merge group { balance: (- (get balance group) amount) })
    )
    (ok true)
  )
)

(define-public (purchase-group-policy (group-id uint) (flight-number (string-ascii 10)) (departure-date uint) (coverage-amount uint))
  (let
    (
      (group (unwrap! (map-get? group-policies { group-id: group-id }) err-group-not-found))
      (current-members (get members group))
      (member-balance (unwrap! (map-get? group-member-balances { group-id: group-id, member: tx-sender }) err-insufficient-balance))
      (base-premium (calculate-premium coverage-amount))
      (discounted-premium (- base-premium (/ (* base-premium (var-get group-discount-rate)) u100)))
      (policy-id (var-get next-policy-id))
      (current-user-policies (default-to { policy-ids: (list) } (map-get? user-policies { user: tx-sender })))
      (current-group-policies (get policy-ids group))
    )
    (asserts! (is-some (index-of current-members tx-sender)) err-not-group-member)
    (asserts! (>= coverage-amount (var-get min-premium)) err-invalid-amount)
    (asserts! (<= coverage-amount (var-get max-coverage)) err-invalid-amount)
    (asserts! (> departure-date stacks-block-height) err-policy-expired)
    (asserts! (>= (get balance member-balance) discounted-premium) err-insufficient-balance)
    (map-set policies
      { policy-id: policy-id }
      {
        holder: tx-sender,
        flight-number: flight-number,
        departure-date: departure-date,
        premium-paid: discounted-premium,
        coverage-amount: coverage-amount,
        is-active: true,
        is-claimed: false,
        created-at: stacks-block-height
      }
    )
    (map-set user-policies
      { user: tx-sender }
      { policy-ids: (unwrap! (as-max-len? (append (get policy-ids current-user-policies) policy-id) u50) err-invalid-amount) }
    )
    (map-set group-policies
      { group-id: group-id }
      (merge group { policy-ids: (unwrap! (as-max-len? (append current-group-policies policy-id) u200) err-invalid-amount) })
    )
    (map-set group-member-balances
      { group-id: group-id, member: tx-sender }
      (merge member-balance { balance: (- (get balance member-balance) discounted-premium) })
    )
    (var-set next-policy-id (+ policy-id u1))
    (ok policy-id)
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

(define-private (is-not-leaving-member (member principal))
  (not (is-eq member tx-sender))
)

(define-private (is-not-leaving-group (group-id uint))
  (not (is-eq group-id group-id))
)

(define-read-only (get-group (group-id uint))
  (map-get? group-policies { group-id: group-id })
)

(define-read-only (get-group-memberships (user principal))
  (map-get? group-memberships { user: user })
)

(define-read-only (get-member-balance (group-id uint) (member principal))
  (map-get? group-member-balances { group-id: group-id, member: member })
)

(define-read-only (get-next-group-id)
  (var-get next-group-id)
)

(define-read-only (get-group-discount-rate)
  (var-get group-discount-rate)
)

(define-read-only (calculate-group-premium (coverage-amount uint))
  (let
    (
      (base-premium (calculate-premium coverage-amount))
      (discount (/ (* base-premium (var-get group-discount-rate)) u100))
    )
    (- base-premium discount)
  )
)

(define-read-only (get-group-policy-count (group-id uint))
  (match (map-get? group-policies { group-id: group-id })
    some-group (len (get policy-ids some-group))
    u0
  )
)

(define-read-only (is-group-member (group-id uint) (user principal))
  (match (map-get? group-policies { group-id: group-id })
    some-group (is-some (index-of (get members some-group) user))
    false
  )
)