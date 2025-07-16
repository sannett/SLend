;; Contract owner
(define-constant contract-owner tx-sender)

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

;; Constants
(define-constant base-interest-rate u1000) ;; 10% in basis points

;; Data maps and variables
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

;; Deposit functions
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

;; Withdrawal functions
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

;; Admin functions
(define-public (set-interest-tier (threshold uint) (rate uint))
    (begin
        (asserts! (is-eq tx-sender contract-owner) ERR-UNAUTHORIZED)
        (asserts! (<= rate u10000) ERR-INVALID-RATE) ;; max 100% (10000 basis points)
        (asserts! (> threshold u0) ERR-INVALID-THRESHOLD)
        (ok (map-set interest-tiers threshold rate))))

(define-public (set-withdrawal-limit (new-limit uint))
    (begin
        (asserts! (is-eq tx-sender contract-owner) ERR-UNAUTHORIZED)
        (asserts! (> new-limit u0) ERR-INVALID-LIMIT)
        (asserts! (<= new-limit u1000000000000) ERR-LIMIT-TOO-HIGH)
        (var-set daily-withdrawal-limit new-limit)
        (ok true)))

;; Read-only functions
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
    (let ((applicable-rate (get-interest-rate-for-amount amount)))
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