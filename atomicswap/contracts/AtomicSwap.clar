;; Atomic Swap - Trustless Cross-Chain Exchange Protocol

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-unauthorized (err u100))
(define-constant err-invalid-swap (err u101))
(define-constant err-swap-exists (err u102))
(define-constant err-swap-not-found (err u103))
(define-constant err-invalid-secret (err u104))
(define-constant err-expired (err u105))
(define-constant err-not-expired (err u106))
(define-constant err-already-executed (err u107))
(define-constant err-invalid-amount (err u108))
(define-constant err-invalid-timelock (err u109))
(define-constant err-insufficient-balance (err u110))
(define-constant err-invalid-hash (err u111))
(define-constant err-paused (err u112))
(define-constant err-invalid-participant (err u113))

;; Data Variables
(define-data-var swap-counter uint u0)
(define-data-var min-timelock uint u144) ;; ~24 minutes minimum
(define-data-var max-timelock uint u10080) ;; ~7 days maximum
(define-data-var protocol-fee uint u10) ;; 0.1% = 10 basis points
(define-data-var total-volume uint u0)
(define-data-var total-swaps uint u0)
(define-data-var fees-collected uint u0)
(define-data-var emergency-pause bool false)

;; Data Maps
(define-map swaps
    uint
    {
        initiator: principal,
        participant: principal,
        initiator-amount: uint,
        participant-amount: uint,
        secret-hash: (buff 32),
        timelock: uint,
        status: (string-ascii 20),
        secret: (optional (buff 32)),
        created-at: uint,
        executed-at: uint
    }
)

(define-map swap-participants
    {swap-id: uint, role: (string-ascii 20)}
    {
        address: principal,
        amount: uint,
        claimed: bool,
        refunded: bool
    }
)

(define-map user-swaps
    principal
    {
        initiated: (list 100 uint),
        participated: (list 100 uint),
        total-volume: uint,
        successful-swaps: uint
    }
)

(define-map secret-hashes
    (buff 32)
    {
        used: bool,
        swap-id: uint,
        revealed-at: uint
    }
)

(define-map swap-routes
    {from: principal, to: principal}
    {
        total-swaps: uint,
        total-volume: uint,
        avg-completion-time: uint,
        success-rate: uint
    }
)

;; Private Functions
(define-private (hash-secret (secret (buff 32)))
    (sha256 secret)
)

(define-private (verify-secret (secret (buff 32)) (hash (buff 32)))
    (is-eq (hash-secret secret) hash)
)

(define-private (calculate-fee (amount uint))
    (/ (* amount (var-get protocol-fee)) u10000)
)

(define-private (is-expired (timelock uint))
    (>= stacks-block-height timelock)
)

(define-private (add-swap-to-user (user principal) (swap-id uint) (is-initiator bool))
    (let ((user-data (default-to {initiated: (list), participated: (list), 
                                  total-volume: u0, successful-swaps: u0}
                                 (map-get? user-swaps user))))
        (if is-initiator
            (match (as-max-len? (append (get initiated user-data) swap-id) u100)
                new-list
                (map-set user-swaps user
                    (merge user-data {initiated: new-list}))
                false)
            (match (as-max-len? (append (get participated user-data) swap-id) u100)
                new-list
                (map-set user-swaps user
                    (merge user-data {participated: new-list}))
                false)
        )
    )
)

(define-private (update-user-stats (user principal) (amount uint) (success bool))
    (let ((user-data (default-to {initiated: (list), participated: (list), 
                                  total-volume: u0, successful-swaps: u0}
                                 (map-get? user-swaps user))))
        (map-set user-swaps user
            (merge user-data {
                total-volume: (+ (get total-volume user-data) amount),
                successful-swaps: (if success 
                                     (+ (get successful-swaps user-data) u1)
                                     (get successful-swaps user-data))
            }))
    )
)

(define-private (update-route-stats (from principal) (to principal) (amount uint) (success bool))
    (let ((route-data (default-to {total-swaps: u0, total-volume: u0, 
                                   avg-completion-time: u0, success-rate: u0}
                                  (map-get? swap-routes {from: from, to: to}))))
        (map-set swap-routes {from: from, to: to}
            (merge route-data {
                total-swaps: (+ (get total-swaps route-data) u1),
                total-volume: (+ (get total-volume route-data) amount),
                success-rate: (if success
                                (/ (* (+ (get success-rate route-data) u100) u100)
                                   (+ (get total-swaps route-data) u1))
                                (/ (* (get success-rate route-data) u100)
                                   (+ (get total-swaps route-data) u1)))
            }))
    )
)

;; Public Functions
(define-public (initiate-swap (participant principal) (initiator-amount uint) 
                              (participant-amount uint) (secret-hash (buff 32)) (timelock uint))
    (let ((swap-id (+ (var-get swap-counter) u1))
          (fee (calculate-fee initiator-amount)))
        
        (asserts! (not (var-get emergency-pause)) err-paused)
        (asserts! (not (is-eq tx-sender participant)) err-invalid-participant)
        (asserts! (> initiator-amount u0) err-invalid-amount)
        (asserts! (> participant-amount u0) err-invalid-amount)
        (asserts! (>= timelock (+ stacks-block-height (var-get min-timelock))) err-invalid-timelock)
        (asserts! (<= timelock (+ stacks-block-height (var-get max-timelock))) err-invalid-timelock)
        (asserts! (>= (stx-get-balance tx-sender) (+ initiator-amount fee)) err-insufficient-balance)
        
        (match (map-get? secret-hashes secret-hash)
            existing (asserts! false err-invalid-hash)
            true
        )
        
        (try! (stx-transfer? (+ initiator-amount fee) tx-sender (as-contract tx-sender)))
        
        (map-set swaps swap-id {
            initiator: tx-sender,
            participant: participant,
            initiator-amount: initiator-amount,
            participant-amount: participant-amount,
            secret-hash: secret-hash,
            timelock: timelock,
            status: "pending",
            secret: none,
            created-at: stacks-block-height,
            executed-at: u0
        })
        
        (map-set swap-participants {swap-id: swap-id, role: "initiator"} {
            address: tx-sender,
            amount: initiator-amount,
            claimed: false,
            refunded: false
        })
        
        (map-set swap-participants {swap-id: swap-id, role: "participant"} {
            address: participant,
            amount: participant-amount,
            claimed: false,
            refunded: false
        })
        
        (map-set secret-hashes secret-hash {
            used: true,
            swap-id: swap-id,
            revealed-at: u0
        })
        
        (add-swap-to-user tx-sender swap-id true)
        (add-swap-to-user participant swap-id false)
        
        (var-set swap-counter swap-id)
        (var-set total-swaps (+ (var-get total-swaps) u1))
        (var-set fees-collected (+ (var-get fees-collected) fee))
        
        (ok swap-id)
    )
)

(define-public (participate (swap-id uint))
    (let ((swap (unwrap! (map-get? swaps swap-id) err-swap-not-found))
          (participant-info (unwrap! (map-get? swap-participants 
                                              {swap-id: swap-id, role: "participant"})
                                    err-swap-not-found)))
        
        (asserts! (not (var-get emergency-pause)) err-paused)
        (asserts! (is-eq tx-sender (get participant swap)) err-unauthorized)
        (asserts! (is-eq (get status swap) "pending") err-invalid-swap)
        (asserts! (not (is-expired (get timelock swap))) err-expired)
        (asserts! (>= (stx-get-balance tx-sender) (get participant-amount swap)) err-insufficient-balance)
        
        (try! (stx-transfer? (get participant-amount swap) tx-sender (as-contract tx-sender)))
        
        (map-set swaps swap-id
            (merge swap {status: "active"}))
        
        (var-set total-volume (+ (var-get total-volume) (get participant-amount swap)))
        
        (ok true)
    )
)

(define-public (claim-with-secret (swap-id uint) (secret (buff 32)))
    (let ((swap (unwrap! (map-get? swaps swap-id) err-swap-not-found))
          (participant-info (unwrap! (map-get? swap-participants 
                                              {swap-id: swap-id, role: "participant"})
                                    err-swap-not-found)))
        
        (asserts! (is-eq tx-sender (get participant swap)) err-unauthorized)
        (asserts! (is-eq (get status swap) "active") err-invalid-swap)
        (asserts! (not (is-expired (get timelock swap))) err-expired)
        (asserts! (verify-secret secret (get secret-hash swap)) err-invalid-secret)
        (asserts! (not (get claimed participant-info)) err-already-executed)
        
        (try! (as-contract (stx-transfer? (get initiator-amount swap) tx-sender (get participant swap))))
        
        (map-set swaps swap-id
            (merge swap {
                status: "completed",
                secret: (some secret),
                executed-at: stacks-block-height
            }))
        
        (map-set swap-participants {swap-id: swap-id, role: "participant"}
            (merge participant-info {claimed: true}))
        
        (map-set secret-hashes (get secret-hash swap)
            {
                used: true,
                swap-id: swap-id,
                revealed-at: stacks-block-height
            })
        
        (update-user-stats (get participant swap) (get initiator-amount swap) true)
        (update-route-stats (get initiator swap) (get participant swap) 
                           (get initiator-amount swap) true)
        
        (ok true)
    )
)

(define-public (claim-initiator (swap-id uint))
    (let ((swap (unwrap! (map-get? swaps swap-id) err-swap-not-found))
          (initiator-info (unwrap! (map-get? swap-participants 
                                            {swap-id: swap-id, role: "initiator"})
                                  err-swap-not-found)))
        
        (asserts! (is-eq tx-sender (get initiator swap)) err-unauthorized)
        (asserts! (is-eq (get status swap) "completed") err-invalid-swap)
        (asserts! (is-some (get secret swap)) err-invalid-secret)
        (asserts! (not (get claimed initiator-info)) err-already-executed)
        
        (try! (as-contract (stx-transfer? (get participant-amount swap) tx-sender (get initiator swap))))
        
        (map-set swap-participants {swap-id: swap-id, role: "initiator"}
            (merge initiator-info {claimed: true}))
        
        (update-user-stats (get initiator swap) (get participant-amount swap) true)
        
        (ok true)
    )
)

(define-public (refund-timeout (swap-id uint))
    (let ((swap (unwrap! (map-get? swaps swap-id) err-swap-not-found))
          (initiator-info (unwrap! (map-get? swap-participants 
                                            {swap-id: swap-id, role: "initiator"})
                                  err-swap-not-found)))
        
        (asserts! (is-eq tx-sender (get initiator swap)) err-unauthorized)
        (asserts! (or (is-eq (get status swap) "pending") 
                     (is-eq (get status swap) "active")) err-invalid-swap)
        (asserts! (is-expired (get timelock swap)) err-not-expired)
        (asserts! (not (get refunded initiator-info)) err-already-executed)
        
        (try! (as-contract (stx-transfer? (get initiator-amount swap) tx-sender (get initiator swap))))
        
        (if (is-eq (get status swap) "active")
            (try! (as-contract (stx-transfer? (get participant-amount swap) tx-sender (get participant swap))))
            true
        )
        
        (map-set swaps swap-id
            (merge swap {status: "refunded"}))
        
        (map-set swap-participants {swap-id: swap-id, role: "initiator"}
            (merge initiator-info {refunded: true}))
        
        (if (is-eq (get status swap) "active")
            (map-set swap-participants {swap-id: swap-id, role: "participant"}
                {address: (get participant swap), amount: (get participant-amount swap), 
                 claimed: false, refunded: true})
            true
        )
        
        (update-route-stats (get initiator swap) (get participant swap) u0 false)
        
        (ok true)
    )
)

(define-public (cancel-swap (swap-id uint))
    (let ((swap (unwrap! (map-get? swaps swap-id) err-swap-not-found)))
        
        (asserts! (is-eq tx-sender (get initiator swap)) err-unauthorized)
        (asserts! (is-eq (get status swap) "pending") err-invalid-swap)
        (asserts! (< stacks-block-height (- (get timelock swap) (var-get min-timelock))) err-invalid-timelock)
        
        (try! (as-contract (stx-transfer? (get initiator-amount swap) tx-sender (get initiator swap))))
        
        (map-set swaps swap-id
            (merge swap {status: "cancelled"}))
        
        (ok true)
    )
)

;; Admin Functions
(define-public (set-timelock-bounds (min uint) (max uint))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-unauthorized)
        (asserts! (< min max) err-invalid-timelock)
        (asserts! (>= min u10) err-invalid-timelock)
        (var-set min-timelock min)
        (var-set max-timelock max)
        (ok true)
    )
)

(define-public (set-protocol-fee (new-fee uint))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-unauthorized)
        (asserts! (<= new-fee u100) err-invalid-amount) ;; Max 1%
        (var-set protocol-fee new-fee)
        (ok true)
    )
)

(define-public (toggle-emergency-pause)
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-unauthorized)
        (var-set emergency-pause (not (var-get emergency-pause)))
        (ok (var-get emergency-pause))
    )
)

(define-public (withdraw-fees)
    (let ((fees (var-get fees-collected)))
        (asserts! (is-eq tx-sender contract-owner) err-unauthorized)
        (asserts! (> fees u0) err-invalid-amount)
        
        (try! (as-contract (stx-transfer? fees tx-sender contract-owner)))
        (var-set fees-collected u0)
        (ok fees)
    )
)

;; Read-only Functions
(define-read-only (get-swap (swap-id uint))
    (map-get? swaps swap-id)
)

(define-read-only (get-swap-participant (swap-id uint) (role (string-ascii 20)))
    (map-get? swap-participants {swap-id: swap-id, role: role})
)

(define-read-only (get-user-swaps (user principal))
    (default-to {initiated: (list), participated: (list), 
                total-volume: u0, successful-swaps: u0}
        (map-get? user-swaps user))
)

(define-read-only (get-secret-hash-info (hash (buff 32)))
    (map-get? secret-hashes hash)
)

(define-read-only (get-route-stats (from principal) (to principal))
    (map-get? swap-routes {from: from, to: to})
)

(define-read-only (verify-secret-hash (secret (buff 32)) (hash (buff 32)))
    (verify-secret secret hash)
)

(define-read-only (is-swap-expired (swap-id uint))
    (match (map-get? swaps swap-id)
        swap (is-expired (get timelock swap))
        true
    )
)

(define-read-only (get-protocol-stats)
    {
        total-swaps: (var-get total-swaps),
        total-volume: (var-get total-volume),
        fees-collected: (var-get fees-collected),
        protocol-fee: (var-get protocol-fee),
        min-timelock: (var-get min-timelock),
        max-timelock: (var-get max-timelock),
        emergency-pause: (var-get emergency-pause)
    }
)