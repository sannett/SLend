;; Enhanced SLend Protocol with Multi-Sig Governance and Oracle Integration

;; Contract owner (legacy - will be replaced by multi-sig)
(define-constant contract-owner tx-sender)

;; Multi-sig governance constants
(define-constant MIN-OWNERS u3)
(define-constant MAX-OWNERS u10)
(define-constant PROPOSAL-DURATION u1440) ;; ~10 days in blocks

;; Error constants
(define-constant ERR-INVALID-AMOUNT (err u1))
(define-constant ERR-LOCK-TOO-LONG (err u2))
(define-constant ERR-UNAUTHORIZED (err u403))
(define-constant ERR-INVALID-RATE (err u4))
(define-constant ERR-INVALID-THRESHOLD (err u5))
(define-constant ERR-SELF-REFERRAL (err u6))
(define-constant ERR-INVALID-REFERRER (err u7))
(define-constant ERR-INVALID-LIMIT (err u8))
(define-constant ERR-LIMIT-TOO-HIGH (err u9))
(define-constant ERR-INSUFFICIENT-BALANCE (err u10))
(define-constant ERR-FUNDS-LOCKED (err u11))
(define-constant ERR-DAILY-LIMIT-EXCEEDED (err u12))
;; New error constants
(define-constant ERR-NOT-OWNER (err u13))
(define-constant ERR-ALREADY-OWNER (err u14))
(define-constant ERR-INVALID-OWNER-COUNT (err u15))
(define-constant ERR-PROPOSAL-NOT-FOUND (err u16))
(define-constant ERR-PROPOSAL-EXPIRED (err u17))
(define-constant ERR-ALREADY-VOTED (err u18))
(define-constant ERR-ORACLE-ERROR (err u19))
(define-constant ERR-STALE-PRICE (err u20))

;; Constants
(define-constant base-interest-rate u1000) ;; 10% in basis points
(define-constant BLOCKS-PER-DAY u144) ;; Approximate blocks per day
(define-constant PRICE-STALENESS-THRESHOLD u1440) ;; 10 days in blocks

;; Multi-sig governance data
(define-data-var owners (list 10 principal) (list contract-owner))
(define-data-var required-confirmations uint u1)
(define-data-var proposal-counter uint u0)
(define-data-var owner-to-remove-temp principal tx-sender) ;; Temporary storage for filtering

;; Oracle data
(define-data-var oracle-address (optional principal) none)
(define-data-var stx-usd-price uint u100000) ;; Price in cents (e.g., $1.00 = 100000)
(define-data-var last-price-update uint u0)
(define-data-var use-dynamic-rates bool false)

;; Proposal structure
(define-map proposals uint 
  (tuple 
    (proposer principal)
    (action (string-ascii 50))
    (target principal)
    (amount uint)
    (created-at uint)
    (executed bool)
    (confirmations uint)))

(define-map proposal-confirmations 
  (tuple (proposal-id uint) (owner principal))
  bool)

;; Data maps and variables (existing)
(define-map deposits principal (tuple (amount uint) (deposit-height uint)))
(define-map lock-periods principal uint)
(define-map interest-tiers uint uint) ;; deposit amount threshold, interest rate (basis points)
(define-map referrals 
    principal  ;; referred user
    principal) ;; referrer
(define-data-var daily-withdrawal-limit uint u1000000000) ;; in microSTX
(define-map daily-withdrawals 
    principal 
    (tuple (amount uint) (last-withdrawal uint)))

;; Initialize default interest tiers
(map-set interest-tiers u0 u1000)        ;; 0-1M: 10%
(map-set interest-tiers u1000000 u1500)  ;; 1M+: 15%

;; Helper functions for max/min operations
(define-private (uint-max (a uint) (b uint))
  (if (> a b) a b))

(define-private (uint-min (a uint) (b uint))
  (if (< a b) a b))

;; Helper function for filtering owners - uses temp variable
(define-private (is-not-target-owner (owner principal))
  (not (is-eq owner (var-get owner-to-remove-temp))))

;; Multi-sig governance functions
(define-private (is-owner (user principal))
  (is-some (index-of (var-get owners) user)))

(define-public (add-owner (new-owner principal))
  (let ((current-owners (var-get owners)))
    (begin
      (asserts! (is-owner tx-sender) ERR-NOT-OWNER)
      (asserts! (not (is-owner new-owner)) ERR-ALREADY-OWNER)
      (asserts! (< (len current-owners) MAX-OWNERS) ERR-INVALID-OWNER-COUNT)
      (var-set owners (unwrap! (as-max-len? (append current-owners new-owner) u10) ERR-INVALID-OWNER-COUNT))
      (ok true))))

(define-public (remove-owner (owner-to-remove principal))
  (let ((current-owners (var-get owners)))
    (begin
      (asserts! (is-owner tx-sender) ERR-NOT-OWNER)
      (asserts! (is-owner owner-to-remove) ERR-NOT-OWNER)
      (asserts! (> (len current-owners) MIN-OWNERS) ERR-INVALID-OWNER-COUNT)
      ;; Set temp variable for filtering
      (var-set owner-to-remove-temp owner-to-remove)
      ;; Filter out the owner
      (var-set owners (filter is-not-target-owner current-owners))
      (ok true))))

(define-public (create-proposal (action (string-ascii 50)) (target principal) (amount uint))
  (let ((proposal-id (+ (var-get proposal-counter) u1)))
    (begin
      (asserts! (is-owner tx-sender) ERR-NOT-OWNER)
      (map-set proposals proposal-id
        (tuple 
          (proposer tx-sender)
          (action action)
          (target target)
          (amount amount)
          (created-at stacks-block-height)
          (executed false)
          (confirmations u1)))
      (map-set proposal-confirmations (tuple (proposal-id proposal-id) (owner tx-sender)) true)
      (var-set proposal-counter proposal-id)
      (ok proposal-id))))

(define-public (confirm-proposal (proposal-id uint))
  (let ((proposal (unwrap! (map-get? proposals proposal-id) ERR-PROPOSAL-NOT-FOUND)))
    (begin
      (asserts! (is-owner tx-sender) ERR-NOT-OWNER)
      (asserts! (not (get executed proposal)) ERR-PROPOSAL-EXPIRED)
      (asserts! (< (+ (get created-at proposal) PROPOSAL-DURATION) stacks-block-height) ERR-PROPOSAL-EXPIRED)
      (asserts! (is-none (map-get? proposal-confirmations (tuple (proposal-id proposal-id) (owner tx-sender)))) ERR-ALREADY-VOTED)
      
      (map-set proposal-confirmations (tuple (proposal-id proposal-id) (owner tx-sender)) true)
      (map-set proposals proposal-id (merge proposal (tuple (confirmations (+ (get confirmations proposal) u1)))))
      
      ;; Auto-execute if enough confirmations
      (if (>= (+ (get confirmations proposal) u1) (var-get required-confirmations))
          (execute-proposal proposal-id)
          (ok true)))))

(define-private (execute-proposal (proposal-id uint))
  (let ((proposal (unwrap! (map-get? proposals proposal-id) ERR-PROPOSAL-NOT-FOUND)))
    (begin
      (map-set proposals proposal-id (merge proposal (tuple (executed true))))
      ;; Here you would implement actual execution logic based on action type
      (ok true))))

;; Oracle integration functions
(define-public (set-oracle (oracle principal))
  (begin
    (asserts! (is-owner tx-sender) ERR-NOT-OWNER)
    (var-set oracle-address (some oracle))
    (ok true)))

(define-public (update-stx-price (new-price uint))
  (begin
    (asserts! (is-eq tx-sender (unwrap! (var-get oracle-address) ERR-ORACLE-ERROR)) ERR-UNAUTHORIZED)
    (asserts! (> new-price u0) ERR-INVALID-AMOUNT)
    (var-set stx-usd-price new-price)
    (var-set last-price-update stacks-block-height)
    (ok true)))

(define-public (toggle-dynamic-rates)
  (begin
    (asserts! (is-owner tx-sender) ERR-NOT-OWNER)
    (var-set use-dynamic-rates (not (var-get use-dynamic-rates)))
    (ok (var-get use-dynamic-rates))))

(define-private (is-price-fresh)
  (< (- stacks-block-height (var-get last-price-update)) PRICE-STALENESS-THRESHOLD))

(define-private (get-dynamic-interest-rate (amount uint))
  (if (and (var-get use-dynamic-rates) (is-price-fresh))
    (let ((stx-price (var-get stx-usd-price))
          (base-rate (get-interest-rate-for-amount amount)))
      ;; Adjust rate based on STX price (higher price = lower rate)
      (if (> stx-price u150000) ;; If STX > $1.50
          (uint-max (- base-rate u200) u500) ;; Reduce rate by 2%, min 5%
          (uint-min (+ base-rate u200) u2000))) ;; Increase rate by 2%, max 20%
    (get-interest-rate-for-amount amount)))

;; Deposit functions (existing with oracle integration)
(define-public (deposit (amount uint))
  (begin 
    (asserts! (> amount u0) ERR-INVALID-AMOUNT)
    (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
    (map-set deposits tx-sender (tuple (amount amount) (deposit-height stacks-block-height)))
    (ok "Deposited")))

(define-public (deposit-with-lock (amount uint) (lock-blocks uint))
    (let ((unlock-height (+ stacks-block-height lock-blocks)))
        (begin
            (asserts! (> amount u0) ERR-INVALID-AMOUNT)
            (asserts! (< lock-blocks u52560) ERR-LOCK-TOO-LONG) ;; max 1 year
            (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
            (map-set deposits tx-sender (tuple (amount amount) (deposit-height stacks-block-height)))
            (map-set lock-periods tx-sender unlock-height)
            (ok "Time-locked deposit created"))))

(define-public (deposit-with-referral (amount uint) (referrer principal))
    (begin
        (asserts! (> amount u0) ERR-INVALID-AMOUNT)
        (asserts! (not (is-eq tx-sender referrer)) ERR-SELF-REFERRAL)
        (asserts! (> (get-balance referrer) u0) ERR-INVALID-REFERRER)
        (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
        (map-set deposits tx-sender (tuple (amount amount) (deposit-height stacks-block-height)))
        (map-set referrals tx-sender referrer)
        (ok "Deposited with referral")))

;; Withdrawal functions (existing)
(define-public (withdraw (amount uint))
    (let (
        (user-balance (get-balance tx-sender))
        (unlock-height (get-unlock-height tx-sender))
        (current-daily (get-daily-withdrawal tx-sender))
        (daily-limit (var-get daily-withdrawal-limit))
    )
    (begin
        (asserts! (> amount u0) ERR-INVALID-AMOUNT)
        (asserts! (>= user-balance amount) ERR-INSUFFICIENT-BALANCE)
        
        ;; Check if funds are locked
        (asserts! (or (is-eq unlock-height u0) 
                     (>= stacks-block-height unlock-height)) ERR-FUNDS-LOCKED)
        
        ;; Check daily withdrawal limit
        (asserts! (<= (+ current-daily amount) daily-limit) ERR-DAILY-LIMIT-EXCEEDED)
        
        ;; Update daily withdrawal tracking
        (map-set daily-withdrawals tx-sender 
            (tuple (amount (+ current-daily amount)) (last-withdrawal stacks-block-height)))
        
        ;; Update user balance
        (if (is-eq user-balance amount)
            ;; Full withdrawal - remove from maps
            (begin
                (map-delete deposits tx-sender)
                (map-delete lock-periods tx-sender))
            ;; Partial withdrawal - update balance
            (map-set deposits tx-sender 
                (tuple (amount (- user-balance amount)) (deposit-height stacks-block-height))))
        
        ;; Transfer STX back to user
        (try! (as-contract (stx-transfer? amount tx-sender tx-sender)))
        (ok "Withdrawal successful"))))

(define-public (emergency-withdraw (amount uint))
    (let (
        (user-balance (get-balance tx-sender))
        (unlock-height (get-unlock-height tx-sender))
        (penalty-rate u500) ;; 5% penalty
        (penalty-amount (/ (* amount penalty-rate) u10000))
        (net-amount (- amount penalty-amount))
    )
    (begin
        (asserts! (> amount u0) ERR-INVALID-AMOUNT)
        (asserts! (>= user-balance amount) ERR-INSUFFICIENT-BALANCE)
        
        ;; Update user balance
        (if (is-eq user-balance amount)
            (begin
                (map-delete deposits tx-sender)
                (map-delete lock-periods tx-sender))
            (map-set deposits tx-sender 
                (tuple (amount (- user-balance amount)) (deposit-height stacks-block-height))))
        
        ;; Transfer net amount (after penalty) back to user
        (try! (as-contract (stx-transfer? net-amount tx-sender tx-sender)))
        (ok "Emergency withdrawal completed with penalty"))))

;; Admin functions (enhanced with multi-sig)
(define-public (set-interest-tier (threshold uint) (rate uint))
    (begin
        (asserts! (or (is-eq tx-sender contract-owner) (is-owner tx-sender)) ERR-UNAUTHORIZED)
        (asserts! (<= rate u10000) ERR-INVALID-RATE) ;; max 100% (10000 basis points)
        (asserts! (> threshold u0) ERR-INVALID-THRESHOLD)
        (ok (map-set interest-tiers threshold rate))))

(define-public (set-withdrawal-limit (new-limit uint))
    (begin
        (asserts! (or (is-eq tx-sender contract-owner) (is-owner tx-sender)) ERR-UNAUTHORIZED)
        (asserts! (> new-limit u0) ERR-INVALID-LIMIT)
        (asserts! (<= new-limit u1000000000000) ERR-LIMIT-TOO-HIGH)
        (var-set daily-withdrawal-limit new-limit)
        (ok true)))

(define-public (set-required-confirmations (confirmations uint))
    (begin
        (asserts! (is-owner tx-sender) ERR-NOT-OWNER)
        (asserts! (> confirmations u0) ERR-INVALID-AMOUNT)
        (asserts! (<= confirmations (len (var-get owners))) ERR-INVALID-OWNER-COUNT)
        (var-set required-confirmations confirmations)
        (ok true)))

;; Read-only functions (existing)
(define-read-only (get-balance (user principal))
    (default-to u0 (get amount (map-get? deposits user))))

(define-read-only (get-deposit-info (user principal))
    (map-get? deposits user))

(define-read-only (get-unlock-height (user principal))
    (default-to u0 (map-get? lock-periods user)))

(define-read-only (get-daily-withdrawal (user principal))
    (let ((withdrawal-data (map-get? daily-withdrawals user)))
        (match withdrawal-data
            data (if (is-eq (get last-withdrawal data) stacks-block-height)
                    (get amount data)
                    u0) ;; Reset if it's a new day (block)
            u0)))

(define-read-only (calculate-interest (amount uint))
    (let ((applicable-rate (get-dynamic-interest-rate amount)))
        (/ (* amount applicable-rate) u10000))) ;; Convert basis points to percentage

(define-read-only (get-interest-rate-for-amount (amount uint))
    (if (>= amount u1000000) ;; 1M microSTX threshold
        (default-to base-interest-rate (map-get? interest-tiers u1000000))
        (default-to base-interest-rate (map-get? interest-tiers u0))))

(define-read-only (get-balance-with-interest (user principal))
    (let (
        (deposit-info (map-get? deposits user))
        (current-balance (get-balance user))
    )
    (match deposit-info
        info (let (
            (deposit-height (get deposit-height info))
            (blocks-elapsed (- stacks-block-height deposit-height))
            (interest (calculate-interest current-balance))
            ;; Simple interest calculation (could be enhanced to compound)
            (time-factor (/ blocks-elapsed u52560)) ;; Approximate blocks per year
        )
        (+ current-balance (/ (* interest time-factor) u1)))
        u0)))

(define-read-only (can-withdraw (user principal))
    (let ((unlock-height (get-unlock-height user)))
        (or (is-eq unlock-height u0) 
            (>= stacks-block-height unlock-height))))

(define-read-only (get-referrer (user principal))
    (map-get? referrals user))

(define-read-only (get-daily-limit)
    (var-get daily-withdrawal-limit))

;; New read-only functions for governance and oracle
(define-read-only (get-owners)
    (var-get owners))

(define-read-only (get-required-confirmations)
    (var-get required-confirmations))

(define-read-only (get-proposal (proposal-id uint))
    (map-get? proposals proposal-id))

(define-read-only (get-stx-price)
    (var-get stx-usd-price))

(define-read-only (get-oracle-address)
    (var-get oracle-address))

(define-read-only (is-dynamic-rates-enabled)
    (var-get use-dynamic-rates))

(define-read-only (get-usd-value (stx-amount uint))
    (/ (* stx-amount (var-get stx-usd-price)) u1000000)) ;; Convert to USD cents

(define-read-only (get-proposal-confirmations (proposal-id uint) (owner principal))
    (default-to false (map-get? proposal-confirmations (tuple (proposal-id proposal-id) (owner owner)))))
