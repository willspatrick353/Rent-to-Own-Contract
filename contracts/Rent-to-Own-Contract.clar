;; ========================================
;; RENT-TO-OWN CONTRACT WITH MAINTENANCE TRACKING
;; ========================================

;; Contract constants
(define-constant contract-owner tx-sender)
(define-constant payment-deadline u30)
(define-constant late-fee-percentage u5)
(define-constant grace-period-blocks u144)
(define-constant late-fee-rate u10)

;; Error constants - Core functionality
(define-constant ERR-UNAUTHORIZED u1)
(define-constant ERR-INVALID-AMOUNT u2)
(define-constant ERR-INVALID-MONTHLY-PAYMENT u3)
(define-constant ERR-INVALID-TOTAL-AMOUNT u4)
(define-constant ERR-PROPERTY-NOT-FOUND u10)
(define-constant ERR-CONTRACT-INACTIVE u11)
(define-constant ERR-UNAUTHORIZED-TENANT u12)
(define-constant ERR-ESCROW-NOT-FOUND u13)
(define-constant ERR-TRANSFER-FAILED u20)
(define-constant ERR-ESCROW-RELEASE-FAILED u21)
(define-constant ERR-PAYMENT-STATUS-ERROR u30)
(define-constant ERR-CANCELLATION-UNAUTHORIZED u41)
(define-constant ERR-CANCELLATION-INVALID-STATUS u42)
(define-constant ERR-LATE-FEE-ASSESSMENT u50)
(define-constant ERR-LATE-FEE-INVALID-STATUS u51)
(define-constant ERR-LATE-FEE-TOO-EARLY u52)
(define-constant ERR-LATE-FEE-PAYMENT-INVALID u60)
(define-constant ERR-LATE-FEE-AMOUNT-ZERO u61)
(define-constant ERR-LATE-FEE-UNAUTHORIZED u62)
(define-constant ERR-TERMINATION-PROPERTY-NOT-FOUND u70)
(define-constant ERR-TERMINATION-ESCROW-NOT-FOUND u71)
(define-constant ERR-TERMINATION-INVALID-STATUS u72)
(define-constant ERR-TERMINATION-UNAUTHORIZED u73)
(define-constant ERR-REFUND-CALCULATION-ERROR u80)
(define-constant ERR-REFUND-ESCROW-ERROR u81)

;; Maintenance request error constants  
(define-constant ERR-INVALID-REQUEST u90)
(define-constant ERR-REQUEST-NOT-FOUND u91)
(define-constant ERR-UNAUTHORIZED-UPDATE u92)
(define-constant ERR-INVALID-PRIORITY u93)
(define-constant ERR-INVALID-CATEGORY u94)
(define-constant ERR-INVALID-STATUS-TRANSITION u95)
(define-constant ERR-MAINTENANCE-ESCROW-NOT-FOUND u96)
(define-constant ERR-MAINTENANCE-ESCROW-INVALID-AMOUNT u97)
(define-constant ERR-MAINTENANCE-ESCROW-UNAUTHORIZED u98)

;; Data variables
(define-data-var contract-active bool false)
(define-data-var property-price uint u0)
(define-data-var monthly-payment uint u0)
(define-data-var total-payments uint u0)
(define-data-var payments-made uint u0)
(define-data-var last-payment-height uint u0)
(define-data-var maintenance-request-counter uint u0)

;; Data maps - Core functionality
(define-map properties
    principal
    {
        owner: principal,
        tenant: principal,
        property-id: uint,
        start-height: uint,
        total-amount: uint,
        monthly-amount: uint,
        payments-completed: uint,
        status: (string-ascii 20),
        next-payment-due: uint,
        late-fees-owed: uint,
    }
)

(define-map escrow-balances
    principal
    {
        total-escrowed: uint,
        owner-portion: uint,
        tenant-portion: uint,
        release-height: uint,
        escrow-status: (string-ascii 20),
    }
)

(define-map payment-history
    uint
    {
        payment-height: uint,
        amount: uint,
        payer: principal,
        status: (string-ascii 20),
    }
)

;; Data maps - Maintenance System
(define-map maintenance-requests
    uint
    {
        property-owner: principal,
        requester: principal,
        request-height: uint,
        category: (string-utf8 50),
        description: (string-utf8 500),
        priority: (string-ascii 10),
        status: (string-ascii 20),
        estimated-cost: uint,
        completion-height: (optional uint),
        assigned-to: (optional principal),
    }
)

(define-map maintenance-history
    uint
    {
        request-id: uint,
        action: (string-utf8 100),
        action-height: uint,
        actor: principal,
        notes: (optional (string-utf8 200)),
    }
)

(define-map maintenance-escrow-balances
    principal
    {
        balance: uint,
        last-deposit-height: uint,
        last-withdrawal-height: uint,
    }
)

;; ========================================
;; CORE RENT-TO-OWN FUNCTIONALITY
;; ========================================

(define-public (initialize-contract
        (property-id uint)
        (tenant principal)
        (total-amount uint)
        (monthly-amount uint)
    )
    (begin
        (asserts! (is-eq tx-sender contract-owner) (err ERR-UNAUTHORIZED))
        (asserts! (> total-amount u0) (err ERR-INVALID-AMOUNT))
        (asserts! (> monthly-amount u0) (err ERR-INVALID-MONTHLY-PAYMENT))
        (asserts! (>= total-amount monthly-amount) (err ERR-INVALID-TOTAL-AMOUNT))
        (map-set properties tx-sender {
            owner: tx-sender,
            tenant: tenant,
            property-id: property-id,
            start-height: stacks-block-height,
            total-amount: total-amount,
            monthly-amount: monthly-amount,
            payments-completed: u0,
            status: "ACTIVE",
            next-payment-due: (+ stacks-block-height payment-deadline),
            late-fees-owed: u0,
        })
        (map-set escrow-balances tx-sender {
            total-escrowed: u0,
            owner-portion: u0,
            tenant-portion: u0,
            release-height: u0,
            escrow-status: "ACTIVE",
        })
        (ok true)
    )
)

(define-public (make-payment (property-id uint))
    (let (
            (property (unwrap! (map-get? properties tx-sender) (err ERR-PROPERTY-NOT-FOUND)))
            (escrow (unwrap! (map-get? escrow-balances tx-sender)
                (err ERR-ESCROW-NOT-FOUND)
            ))
            (payment-id (+ (var-get payments-made) u1))
            (current-height stacks-block-height)
            (payment-amount (get monthly-amount property))
            (owner-share (/ (* payment-amount u70) u100))
            (tenant-share (- payment-amount owner-share))
        )
        (asserts! (is-eq (get status property) "ACTIVE")
            (err ERR-CONTRACT-INACTIVE)
        )
        (asserts! (is-eq tx-sender (get tenant property))
            (err ERR-UNAUTHORIZED-TENANT)
        )
        (try! (stx-transfer? payment-amount tx-sender (as-contract tx-sender)))
        (map-set payment-history payment-id {
            payment-height: current-height,
            amount: payment-amount,
            payer: tx-sender,
            status: "ESCROWED",
        })
        (map-set escrow-balances tx-sender
            (merge escrow {
                total-escrowed: (+ (get total-escrowed escrow) payment-amount),
                owner-portion: (+ (get owner-portion escrow) owner-share),
                tenant-portion: (+ (get tenant-portion escrow) tenant-share),
            })
        )
        (map-set properties tx-sender
            (merge property {
                payments-completed: (+ (get payments-completed property) u1),
                next-payment-due: (+ current-height payment-deadline),
            })
        )
        (var-set payments-made payment-id)
        (var-set last-payment-height current-height)
        (if (>= (+ (get payments-completed property) u1)
                (/ (get total-amount property) (get monthly-amount property))
            )
            (transfer-ownership property-id)
            (ok true)
        )
    )
)

(define-private (transfer-ownership (property-id uint))
    (let (
            (property (unwrap! (map-get? properties tx-sender) (err ERR-TRANSFER-FAILED)))
            (escrow (unwrap! (map-get? escrow-balances tx-sender)
                (err ERR-ESCROW-RELEASE-FAILED)
            ))
        )
        (try! (as-contract (stx-transfer? (get owner-portion escrow) tx-sender (get owner property))))
        (try! (as-contract (stx-transfer? (get tenant-portion escrow) tx-sender
            (get tenant property)
        )))
        (map-set properties tx-sender
            (merge property {
                owner: (get tenant property),
                status: "COMPLETED",
            })
        )
        (map-set escrow-balances tx-sender
            (merge escrow {
                escrow-status: "RELEASED",
                release-height: stacks-block-height,
            })
        )
        (ok true)
    )
)

(define-public (check-payment-status (property-id uint))
    (let (
            (property (unwrap! (map-get? properties tx-sender)
                (err ERR-PAYMENT-STATUS-ERROR)
            ))
            (current-height stacks-block-height)
        )
        (ok {
            payments-made: (get payments-completed property),
            total-payments: (/ (get total-amount property) (get monthly-amount property)),
            last-payment: (var-get last-payment-height),
            status: (get status property),
        })
    )
)

(define-public (cancel-contract (property-id uint))
    (let ((property (unwrap! (map-get? properties tx-sender) (err ERR-PROPERTY-NOT-FOUND))))
        (asserts!
            (or (is-eq tx-sender contract-owner) (is-eq tx-sender (get owner property)))
            (err ERR-CANCELLATION-UNAUTHORIZED)
        )
        (asserts! (is-eq (get status property) "ACTIVE")
            (err ERR-CANCELLATION-INVALID-STATUS)
        )
        (map-set properties tx-sender (merge property { status: "CANCELLED" }))
        (ok true)
    )
)

;; Late fee functionality
(define-private (calculate-late-fee (property {
    owner: principal,
    tenant: principal,
    property-id: uint,
    start-height: uint,
    total-amount: uint,
    monthly-amount: uint,
    payments-completed: uint,
    status: (string-ascii 20),
    next-payment-due: uint,
    late-fees-owed: uint,
}))
    (let (
            (current-height stacks-block-height)
            (payment-due (get next-payment-due property))
            (grace-period-end (+ payment-due grace-period-blocks))
        )
        (if (> current-height grace-period-end)
            (/ (* (get monthly-amount property) late-fee-rate) u100)
            u0
        )
    )
)

(define-public (assess-late-fees (property-id uint))
    (let (
            (property (unwrap! (map-get? properties tx-sender)
                (err ERR-LATE-FEE-ASSESSMENT)
            ))
            (current-height stacks-block-height)
            (payment-due (get next-payment-due property))
            (grace-period-end (+ payment-due grace-period-blocks))
        )
        (asserts! (is-eq (get status property) "ACTIVE")
            (err ERR-LATE-FEE-INVALID-STATUS)
        )
        (asserts! (> current-height grace-period-end)
            (err ERR-LATE-FEE-TOO-EARLY)
        )
        (let ((late-fee (calculate-late-fee property)))
            (map-set properties tx-sender
                (merge property { late-fees-owed: (+ (get late-fees-owed property) late-fee) })
            )
            (ok late-fee)
        )
    )
)

(define-public (pay-late-fees (property-id uint))
    (let (
            (property (unwrap! (map-get? properties tx-sender)
                (err ERR-LATE-FEE-PAYMENT-INVALID)
            ))
            (late-fees (get late-fees-owed property))
        )
        (asserts! (> late-fees u0) (err ERR-LATE-FEE-AMOUNT-ZERO))
        (asserts! (is-eq tx-sender (get tenant property))
            (err ERR-LATE-FEE-UNAUTHORIZED)
        )
        (try! (stx-transfer? late-fees tx-sender (get owner property)))
        (map-set properties tx-sender (merge property { late-fees-owed: u0 }))
        (ok true)
    )
)

(define-public (request-early-termination (property-id uint))
    (let (
            (property (unwrap! (map-get? properties tx-sender)
                (err ERR-TERMINATION-PROPERTY-NOT-FOUND)
            ))
            (escrow (unwrap! (map-get? escrow-balances tx-sender)
                (err ERR-TERMINATION-ESCROW-NOT-FOUND)
            ))
            (total-payments-required (/ (get total-amount property) (get monthly-amount property)))
            (payments-completed (get payments-completed property))
            (completion-ratio (/ (* payments-completed u100) total-payments-required))
            (owner-refund (if (> completion-ratio u50)
                (/ (* (get owner-portion escrow) completion-ratio) u100)
                (get owner-portion escrow)
            ))
            (tenant-refund (- (get total-escrowed escrow) owner-refund))
        )
        (asserts! (is-eq (get status property) "ACTIVE")
            (err ERR-TERMINATION-INVALID-STATUS)
        )
        (asserts!
            (or
                (is-eq tx-sender (get owner property))
                (is-eq tx-sender (get tenant property))
            )
            (err ERR-TERMINATION-UNAUTHORIZED)
        )
        (try! (as-contract (stx-transfer? owner-refund tx-sender (get owner property))))
        (try! (as-contract (stx-transfer? tenant-refund tx-sender (get tenant property))))
        (map-set properties tx-sender (merge property { status: "TERMINATED" }))
        (map-set escrow-balances tx-sender
            (merge escrow {
                escrow-status: "REFUNDED",
                release-height: stacks-block-height,
            })
        )
        (ok {
            owner-refund: owner-refund,
            tenant-refund: tenant-refund,
        })
    )
)

;; ========================================
;; MAINTENANCE REQUEST SYSTEM
;; ========================================

(define-public (submit-maintenance-request
        (property-owner principal)
        (category (string-utf8 50))
        (description (string-utf8 500))
        (priority (string-ascii 10))
        (estimated-cost uint)
    )
    (let (
            (request-id (+ (var-get maintenance-request-counter) u1))
            (property (map-get? properties property-owner))
        )
        (asserts! (is-some property) (err ERR-INVALID-REQUEST))
        (asserts! (> (len description) u0) (err ERR-INVALID-REQUEST))
        (asserts! (> (len category) u0) (err ERR-INVALID-REQUEST))
        (asserts!
            (or
                (is-eq priority "LOW")
                (is-eq priority "MEDIUM")
                (is-eq priority "HIGH")
                (is-eq priority "CRITICAL")
            )
            (err ERR-INVALID-PRIORITY)
        )
        (let ((property-data (unwrap! property (err ERR-INVALID-REQUEST))))
            (asserts!
                (or
                    (is-eq tx-sender (get tenant property-data))
                    (is-eq tx-sender property-owner)
                )
                (err ERR-UNAUTHORIZED-UPDATE)
            )
        )
        (map-set maintenance-requests request-id {
            property-owner: property-owner,
            requester: tx-sender,
            request-height: stacks-block-height,
            category: category,
            description: description,
            priority: priority,
            status: "PENDING",
            estimated-cost: estimated-cost,
            completion-height: none,
            assigned-to: none,
        })
        (map-set maintenance-history request-id {
            request-id: request-id,
            action: u"Request submitted",
            action-height: stacks-block-height,
            actor: tx-sender,
            notes: none,
        })
        (var-set maintenance-request-counter request-id)
        (ok request-id)
    )
)

(define-public (update-request-status
        (request-id uint)
        (new-status (string-ascii 20))
        (notes (optional (string-utf8 200)))
        (assigned-to (optional principal))
    )
    (let (
            (request (unwrap! (map-get? maintenance-requests request-id)
                (err ERR-REQUEST-NOT-FOUND)
            ))
            (history-id (+ request-id u1000))
        )
        (asserts!
            (or
                (is-eq tx-sender (get property-owner request))
                (is-eq tx-sender contract-owner)
            )
            (err ERR-UNAUTHORIZED-UPDATE)
        )
        (asserts!
            (or
                (is-eq new-status "PENDING")
                (is-eq new-status "APPROVED")
                (is-eq new-status "IN_PROGRESS")
                (is-eq new-status "COMPLETED")
                (is-eq new-status "REJECTED")
                (is-eq new-status "ON_HOLD")
            )
            (err ERR-INVALID-REQUEST)
        )
        (map-set maintenance-requests request-id
            (merge request {
                status: new-status,
                assigned-to: assigned-to,
                completion-height: (if (is-eq new-status "COMPLETED")
                    (some stacks-block-height)
                    (get completion-height request)
                ),
            })
        )
        (map-set maintenance-history history-id {
            request-id: request-id,
            ;; Simplified action message without dynamic string conversion
            action: u"Status updated",
            action-height: stacks-block-height,
            actor: tx-sender,
            notes: notes,
        })
        (ok true)
    )
)

(define-public (assign-maintenance-worker
        (request-id uint)
        (worker principal)
        (notes (optional (string-utf8 200)))
    )
    (let (
            (request (unwrap! (map-get? maintenance-requests request-id)
                (err ERR-REQUEST-NOT-FOUND)
            ))
            (history-id (+ request-id u2000))
        )
        (asserts!
            (or
                (is-eq tx-sender (get property-owner request))
                (is-eq tx-sender contract-owner)
            )
            (err ERR-UNAUTHORIZED-UPDATE)
        )
        (asserts! (is-eq (get status request) "APPROVED")
            (err ERR-INVALID-STATUS-TRANSITION)
        )
        (map-set maintenance-requests request-id
            (merge request {
                assigned-to: (some worker),
                status: "IN_PROGRESS",
            })
        )
        (map-set maintenance-history history-id {
            request-id: request-id,
            action: u"Worker assigned and status set to IN_PROGRESS",
            action-height: stacks-block-height,
            actor: tx-sender,
            notes: notes,
        })
        (ok true)
    )
)

(define-public (fund-maintenance-escrow
        (property-owner principal)
        (amount uint)
    )
    (let (
            (property (unwrap! (map-get? properties property-owner)
                (err ERR-PROPERTY-NOT-FOUND)
            ))
            (existing (map-get? maintenance-escrow-balances property-owner))
            (current-balance (match existing
                existing-escrow (get balance existing-escrow)
                u0
            ))
            (last-withdrawal (match existing
                existing-escrow (get last-withdrawal-height existing-escrow)
                u0
            ))
        )
        (asserts! (> amount u0) (err ERR-MAINTENANCE-ESCROW-INVALID-AMOUNT))
        (asserts!
            (or
                (is-eq tx-sender (get owner property))
                (is-eq tx-sender (get tenant property))
            )
            (err ERR-MAINTENANCE-ESCROW-UNAUTHORIZED)
        )
        (map-set maintenance-escrow-balances property-owner {
            balance: (+ current-balance amount),
            last-deposit-height: stacks-block-height,
            last-withdrawal-height: last-withdrawal,
        })
        (ok (+ current-balance amount))
    )
)

(define-public (withdraw-maintenance-escrow
        (property-owner principal)
        (amount uint)
    )
    (let (
            (property (unwrap! (map-get? properties property-owner)
                (err ERR-PROPERTY-NOT-FOUND)
            ))
            (escrow (unwrap! (map-get? maintenance-escrow-balances property-owner)
                (err ERR-MAINTENANCE-ESCROW-NOT-FOUND)
            ))
            (balance (get balance escrow))
        )
        (asserts! (> amount u0) (err ERR-MAINTENANCE-ESCROW-INVALID-AMOUNT))
        (asserts! (<= amount balance) (err ERR-MAINTENANCE-ESCROW-INVALID-AMOUNT))
        (asserts!
            (or
                (is-eq tx-sender (get owner property))
                (is-eq tx-sender contract-owner)
            )
            (err ERR-MAINTENANCE-ESCROW-UNAUTHORIZED)
        )
        (map-set maintenance-escrow-balances property-owner {
            balance: (- balance amount),
            last-deposit-height: (get last-deposit-height escrow),
            last-withdrawal-height: stacks-block-height,
        })
        (ok (- balance amount))
    )
)

;; ========================================
;; READ-ONLY FUNCTIONS
;; ========================================

;; Core contract read-only functions
(define-read-only (get-property-details (property-owner principal))
    (map-get? properties property-owner)
)

(define-read-only (get-payment-history (payment-id uint))
    (map-get? payment-history payment-id)
)

(define-read-only (get-escrow-balance (property-owner principal))
    (map-get? escrow-balances property-owner)
)

(define-read-only (calculate-refund-amounts (property-owner principal))
    (let (
            (property (unwrap! (map-get? properties property-owner)
                (err ERR-REFUND-CALCULATION-ERROR)
            ))
            (escrow (unwrap! (map-get? escrow-balances property-owner)
                (err ERR-REFUND-ESCROW-ERROR)
            ))
            (total-payments-required (/ (get total-amount property) (get monthly-amount property)))
            (payments-completed (get payments-completed property))
            (completion-ratio (/ (* payments-completed u100) total-payments-required))
            (owner-refund (if (> completion-ratio u50)
                (/ (* (get owner-portion escrow) completion-ratio) u100)
                (get owner-portion escrow)
            ))
            (tenant-refund (- (get total-escrowed escrow) owner-refund))
        )
        (ok {
            owner-refund: owner-refund,
            tenant-refund: tenant-refund,
            completion-ratio: completion-ratio,
            total-escrowed: (get total-escrowed escrow),
        })
    )
)

;; Maintenance system read-only functions
(define-read-only (get-maintenance-request (request-id uint))
    (map-get? maintenance-requests request-id)
)

(define-read-only (get-maintenance-history (history-id uint))
    (map-get? maintenance-history history-id)
)

(define-read-only (get-request-counter)
    (var-get maintenance-request-counter)
)

(define-read-only (get-property-maintenance-summary (property-owner principal))
    (let (
            (counter (var-get maintenance-request-counter))
            (property (map-get? properties property-owner))
        )
        (match property
            some-property (ok {
                total-requests: counter,
                property-status: (get status some-property),
                last-payment-height: (var-get last-payment-height),
            })
            (err ERR-INVALID-REQUEST)
        )
    )
)
