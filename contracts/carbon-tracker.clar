;; Carbon Tracker - Transparent Carbon Credit Trading Platform
;; This contract manages carbon credit tokenization, trading, and environmental impact tracking

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-CREDIT-NOT-FOUND (err u101))
(define-constant ERR-INSUFFICIENT-BALANCE (err u102))
(define-constant ERR-CREDIT-ALREADY-RETIRED (err u103))
(define-constant ERR-INVALID-AMOUNT (err u104))
(define-constant ERR-PROJECT-NOT-VERIFIED (err u105))
(define-constant ERR-TRANSFER-FAILED (err u106))
(define-constant ERR-INVALID-PROJECT (err u107))
(define-constant ERR-PRICE-TOO_LOW (err u108))

;; Carbon credit types
(define-constant REFORESTATION u1)
(define-constant RENEWABLE-ENERGY u2)
(define-constant METHANE-REDUCTION u3)
(define-constant CONSERVATION u4)
(define-constant DIRECT-AIR-CAPTURE u5)

;; Data Variables
(define-data-var credit-counter uint u0)
(define-data-var project-counter uint u0)
(define-data-var trade-counter uint u0)
(define-data-var total-credits-issued uint u0)
(define-data-var total-credits-retired uint u0)
(define-data-var platform-fee-rate uint u250) ;; 2.5% in basis points

;; Carbon Credit Structure
(define-map carbon-credits
  { credit-id: uint }
  {
    project-id: uint,
    owner: principal,
    amount: uint, ;; Amount in tons CO2e
    credit-type: uint,
    vintage-year: uint,
    verification-standard: (string-ascii 20),
    issued-date: uint,
    is-retired: bool,
    retirement-date: uint,
    retirement-reason: (string-ascii 100)
  }
)

;; Carbon Project Registry
(define-map carbon-projects
  { project-id: uint }
  {
    name: (string-ascii 100),
    developer: principal,
    location: (string-ascii 50),
    project-type: uint,
    total-capacity: uint, ;; Total CO2e capacity in tons
    credits-issued: uint,
    verification-body: (string-ascii 50),
    certification-date: uint,
    is-verified: bool,
    methodology: (string-ascii 50)
  }
)

;; Trading Orders
(define-map trading-orders
  { order-id: uint }
  {
    seller: principal,
    credit-id: uint,
    amount: uint,
    price-per-ton: uint, ;; Price in microSTX
    order-type: (string-ascii 10), ;; "sell" or "buy"
    is-active: bool,
    created-date: uint,
    expiry-date: uint
  }
)

;; User Balances
(define-map user-balances
  { user: principal, credit-id: uint }
  { balance: uint }
)

;; Impact Tracking
(define-map environmental-impact
  { project-id: uint }
  {
    co2-sequestered: uint, ;; Total CO2 sequestered in tons
    trees-planted: uint,
    renewable-energy-generated: uint, ;; MWh
    area-conserved: uint, ;; Hectares
    last-updated: uint,
    monitoring-data: (string-ascii 200)
  }
)

;; Trade History
(define-map trade-history
  { trade-id: uint }
  {
    buyer: principal,
    seller: principal,
    credit-id: uint,
    amount: uint,
    price-per-ton: uint,
    total-price: uint,
    trade-date: uint,
    fee-paid: uint
  }
)

;; Price History for Market Analytics
(define-map price-history
  { credit-type: uint, date: uint }
  {
    average-price: uint,
    volume-traded: uint,
    number-of-trades: uint
  }
)

;; Public Functions

;; Register a new carbon project
(define-public (register-project
  (name (string-ascii 100))
  (location (string-ascii 50))
  (project-type uint)
  (total-capacity uint)
  (methodology (string-ascii 50)))
  (let
    (
      (project-id (+ (var-get project-counter) u1))
    )
    (asserts! (> total-capacity u0) ERR-INVALID-AMOUNT)
    (asserts! (and (>= project-type u1) (<= project-type u5)) ERR-INVALID-PROJECT)
    
    ;; Register the project
    (map-set carbon-projects
      { project-id: project-id }
      {
        name: name,
        developer: tx-sender,
        location: location,
        project-type: project-type,
        total-capacity: total-capacity,
        credits-issued: u0,
        verification-body: "",
        certification-date: u0,
        is-verified: false,
        methodology: methodology
      }
    )
    
    ;; Initialize impact tracking
    (map-set environmental-impact
      { project-id: project-id }
      {
        co2-sequestered: u0,
        trees-planted: u0,
        renewable-energy-generated: u0,
        area-conserved: u0,
        last-updated: stacks-block-height,
        monitoring-data: ""
      }
    )
    
    ;; Update counter
    (var-set project-counter project-id)
    
    (ok project-id)
  )
)

;; Verify a carbon project (restricted to contract owner)
(define-public (verify-project
  (project-id uint)
  (verification-body (string-ascii 50)))
  (let
    (
      (project (unwrap! (map-get? carbon-projects { project-id: project-id }) ERR-INVALID-PROJECT))
    )
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    
    (map-set carbon-projects
      { project-id: project-id }
      (merge project {
        verification-body: verification-body,
        certification-date: stacks-block-height,
        is-verified: true
      })
    )
    
    (ok true)
  )
)

;; Issue carbon credits for verified projects
(define-public (issue-credits
  (project-id uint)
  (amount uint)
  (vintage-year uint)
  (verification-standard (string-ascii 20)))
  (let
    (
      (project (unwrap! (map-get? carbon-projects { project-id: project-id }) ERR-INVALID-PROJECT))
      (credit-id (+ (var-get credit-counter) u1))
      (new-total-issued (+ (get credits-issued project) amount))
    )
    (asserts! (get is-verified project) ERR-PROJECT-NOT-VERIFIED)
    (asserts! (is-eq tx-sender (get developer project)) ERR-NOT-AUTHORIZED)
    (asserts! (> amount u0) ERR-INVALID-AMOUNT)
    (asserts! (<= new-total-issued (get total-capacity project)) ERR-INVALID-AMOUNT)
    
    ;; Create carbon credit
    (map-set carbon-credits
      { credit-id: credit-id }
      {
        project-id: project-id,
        owner: tx-sender,
        amount: amount,
        credit-type: (get project-type project),
        vintage-year: vintage-year,
        verification-standard: verification-standard,
        issued-date: stacks-block-height,
        is-retired: false,
        retirement-date: u0,
        retirement-reason: ""
      }
    )
    
    ;; Update user balance
    (map-set user-balances
      { user: tx-sender, credit-id: credit-id }
      { balance: amount }
    )
    
    ;; Update project credits issued
    (map-set carbon-projects
      { project-id: project-id }
      (merge project { credits-issued: new-total-issued })
    )
    
    ;; Update counters
    (var-set credit-counter credit-id)
    (var-set total-credits-issued (+ (var-get total-credits-issued) amount))
    
    (ok credit-id)
  )
)

;; Create a sell order for carbon credits
(define-public (create-sell-order
  (credit-id uint)
  (amount uint)
  (price-per-ton uint)
  (expiry-blocks uint))
  (let
    (
      (credit (unwrap! (map-get? carbon-credits { credit-id: credit-id }) ERR-CREDIT-NOT-FOUND))
      (user-balance (default-to u0 (get balance (map-get? user-balances { user: tx-sender, credit-id: credit-id }))))
      (order-id (+ (var-get trade-counter) u1))
    )
    (asserts! (not (get is-retired credit)) ERR-CREDIT-ALREADY-RETIRED)
    (asserts! (>= user-balance amount) ERR-INSUFFICIENT-BALANCE)
    (asserts! (> amount u0) ERR-INVALID-AMOUNT)
    (asserts! (> price-per-ton u0) ERR-PRICE-TOO_LOW)
    
    ;; Create sell order
    (map-set trading-orders
      { order-id: order-id }
      {
        seller: tx-sender,
        credit-id: credit-id,
        amount: amount,
        price-per-ton: price-per-ton,
        order-type: "sell",
        is-active: true,
        created-date: stacks-block-height,
        expiry-date: (+ stacks-block-height expiry-blocks)
      }
    )
    
    ;; Update counter
    (var-set trade-counter order-id)
    
    (ok order-id)
  )
)

;; Execute a trade (buy carbon credits)
(define-public (execute-trade (order-id uint) (amount uint))
  (let
    (
      (order (unwrap! (map-get? trading-orders { order-id: order-id }) ERR-CREDIT-NOT-FOUND))
      (credit-id (get credit-id order))
      (seller (get seller order))
      (price-per-ton (get price-per-ton order))
      (total-price (* amount price-per-ton))
      (platform-fee (/ (* total-price (var-get platform-fee-rate)) u10000))
      (seller-amount (- total-price platform-fee))
      (seller-balance (default-to u0 (get balance (map-get? user-balances { user: seller, credit-id: credit-id }))))
      (buyer-balance (default-to u0 (get balance (map-get? user-balances { user: tx-sender, credit-id: credit-id }))))
      (trade-id (+ (var-get trade-counter) u1))
    )
    (asserts! (get is-active order) ERR-CREDIT-NOT-FOUND)
    (asserts! (<= stacks-block-height (get expiry-date order)) ERR-CREDIT-NOT-FOUND)
    (asserts! (>= (get amount order) amount) ERR-INSUFFICIENT-BALANCE)
    (asserts! (>= seller-balance amount) ERR-INSUFFICIENT-BALANCE)
    (asserts! (> amount u0) ERR-INVALID-AMOUNT)
    
    ;; Transfer STX payment
    (try! (stx-transfer? seller-amount tx-sender seller))
    (try! (stx-transfer? platform-fee tx-sender CONTRACT-OWNER))
    
    ;; Update balances
    (map-set user-balances
      { user: seller, credit-id: credit-id }
      { balance: (- seller-balance amount) }
    )
    
    (map-set user-balances
      { user: tx-sender, credit-id: credit-id }
      { balance: (+ buyer-balance amount) }
    )
    
    ;; Update order
    (if (is-eq (get amount order) amount)
      ;; Order fully filled
      (map-set trading-orders
        { order-id: order-id }
        (merge order { is-active: false })
      )
      ;; Partial fill
      (map-set trading-orders
        { order-id: order-id }
        (merge order { amount: (- (get amount order) amount) })
      )
    )
    
    ;; Record trade
    (map-set trade-history
      { trade-id: trade-id }
      {
        buyer: tx-sender,
        seller: seller,
        credit-id: credit-id,
        amount: amount,
        price-per-ton: price-per-ton,
        total-price: total-price,
        trade-date: stacks-block-height,
        fee-paid: platform-fee
      }
    )
    
    ;; Update trade counter
    (var-set trade-counter trade-id)
    
    (ok trade-id)
  )
)

;; Retire carbon credits permanently
(define-public (retire-credits
  (credit-id uint)
  (amount uint)
  (retirement-reason (string-ascii 100)))
  (let
    (
      (credit (unwrap! (map-get? carbon-credits { credit-id: credit-id }) ERR-CREDIT-NOT-FOUND))
      (user-balance (default-to u0 (get balance (map-get? user-balances { user: tx-sender, credit-id: credit-id }))))
    )
    (asserts! (not (get is-retired credit)) ERR-CREDIT-ALREADY-RETIRED)
    (asserts! (>= user-balance amount) ERR-INSUFFICIENT-BALANCE)
    (asserts! (> amount u0) ERR-INVALID-AMOUNT)
    
    ;; Update user balance
    (map-set user-balances
      { user: tx-sender, credit-id: credit-id }
      { balance: (- user-balance amount) }
    )
    
    ;; If all credits retired, mark as retired
    (if (is-eq (get amount credit) amount)
      (map-set carbon-credits
        { credit-id: credit-id }
        (merge credit {
          is-retired: true,
          retirement-date: stacks-block-height,
          retirement-reason: retirement-reason
        })
      )
      ;; Create new retired credit entry
      (let ((retired-credit-id (+ (var-get credit-counter) u1)))
        (map-set carbon-credits
          { credit-id: retired-credit-id }
          (merge credit {
            amount: amount,
            owner: tx-sender,
            is-retired: true,
            retirement-date: stacks-block-height,
            retirement-reason: retirement-reason
          })
        )
        (var-set credit-counter retired-credit-id)
      )
    )
    
    ;; Update total retired
    (var-set total-credits-retired (+ (var-get total-credits-retired) amount))
    
    (ok true)
  )
)

;; Update environmental impact data (project developers only)
(define-public (update-impact-data
  (project-id uint)
  (co2-sequestered uint)
  (trees-planted uint)
  (renewable-energy-generated uint)
  (area-conserved uint)
  (monitoring-data (string-ascii 200)))
  (let
    (
      (project (unwrap! (map-get? carbon-projects { project-id: project-id }) ERR-INVALID-PROJECT))
    )
    (asserts! (is-eq tx-sender (get developer project)) ERR-NOT-AUTHORIZED)
    
    (map-set environmental-impact
      { project-id: project-id }
      {
        co2-sequestered: co2-sequestered,
        trees-planted: trees-planted,
        renewable-energy-generated: renewable-energy-generated,
        area-conserved: area-conserved,
        last-updated: stacks-block-height,
        monitoring-data: monitoring-data
      }
    )
    
    (ok true)
  )
)

;; Cancel an active order
(define-public (cancel-order (order-id uint))
  (let
    (
      (order (unwrap! (map-get? trading-orders { order-id: order-id }) ERR-CREDIT-NOT-FOUND))
    )
    (asserts! (is-eq tx-sender (get seller order)) ERR-NOT-AUTHORIZED)
    (asserts! (get is-active order) ERR-CREDIT-NOT-FOUND)
    
    (map-set trading-orders
      { order-id: order-id }
      (merge order { is-active: false })
    )
    
    (ok true)
  )
)

;; Read-only Functions

;; Get carbon credit details
(define-read-only (get-credit (credit-id uint))
  (map-get? carbon-credits { credit-id: credit-id })
)

;; Get project details
(define-read-only (get-project (project-id uint))
  (map-get? carbon-projects { project-id: project-id })
)

;; Get trading order
(define-read-only (get-order (order-id uint))
  (map-get? trading-orders { order-id: order-id })
)

;; Get user balance for specific credit
(define-read-only (get-balance (user principal) (credit-id uint))
  (default-to u0 (get balance (map-get? user-balances { user: user, credit-id: credit-id })))
)

;; Get environmental impact data
(define-read-only (get-impact-data (project-id uint))
  (map-get? environmental-impact { project-id: project-id })
)

;; Get trade history
(define-read-only (get-trade (trade-id uint))
  (map-get? trade-history { trade-id: trade-id })
)

;; Get platform statistics
(define-read-only (get-platform-stats)
  {
    total-credits-issued: (var-get total-credits-issued),
    total-credits-retired: (var-get total-credits-retired),
    total-projects: (var-get project-counter),
    total-trades: (var-get trade-counter),
    platform-fee-rate: (var-get platform-fee-rate)
  }
)

;; Get current counters
(define-read-only (get-credit-counter)
  (var-get credit-counter)
)

(define-read-only (get-project-counter)
  (var-get project-counter)
)

(define-read-only (get-trade-counter)
  (var-get trade-counter)
)

;; Check if project is verified
(define-read-only (is-project-verified (project-id uint))
  (match (map-get? carbon-projects { project-id: project-id })
    project (get is-verified project)
    false
  )
)

;; title: carbon-tracker
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

