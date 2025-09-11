(define-constant contract-owner tx-sender)
(define-constant payment-deadline u30)
(define-constant late-fee-percentage u5)
(define-constant grace-period-blocks u144)
(define-constant late-fee-rate u10)

(define-data-var contract-active bool false)
(define-data-var property-price uint u0)
(define-data-var monthly-payment uint u0)
(define-data-var total-payments uint u0)
(define-data-var payments-made uint u0)
(define-data-var last-payment-height uint u0)

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

(define-public (initialize-contract
        (property-id uint)
        (tenant principal)
        (total-amount uint)
        (monthly-amount uint)
    )
    (begin
        (asserts! (is-eq tx-sender contract-owner) (err u1))
        (asserts! (> total-amount u0) (err u2))
        (asserts! (> monthly-amount u0) (err u3))
        (asserts! (>= total-amount monthly-amount) (err u4))
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
            (property (unwrap! (map-get? properties tx-sender) (err u10)))
            (escrow (unwrap! (map-get? escrow-balances tx-sender) (err u13)))
            (payment-id (+ (var-get payments-made) u1))
            (current-height stacks-block-height)
            (payment-amount (get monthly-amount property))
            (owner-share (/ (* payment-amount u70) u100))
            (tenant-share (- payment-amount owner-share))
        )
        (asserts! (is-eq (get status property) "ACTIVE") (err u11))
        (asserts! (is-eq tx-sender (get tenant property)) (err u12))
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
            (property (unwrap! (map-get? properties tx-sender) (err u20)))
            (escrow (unwrap! (map-get? escrow-balances tx-sender) (err u21)))
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
            (property (unwrap! (map-get? properties tx-sender) (err u30)))
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
    (let ((property (unwrap! (map-get? properties tx-sender) (err u40))))
        (asserts!
            (or (is-eq tx-sender contract-owner) (is-eq tx-sender (get owner property)))
            (err u41)
        )
        (asserts! (is-eq (get status property) "ACTIVE") (err u42))
        (map-set properties tx-sender (merge property { status: "CANCELLED" }))
        (ok true)
    )
)

(define-read-only (get-property-details (property-id uint))
    (map-get? properties tx-sender)
)

(define-read-only (get-payment-history (payment-id uint))
    (map-get? payment-history payment-id)
)

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
            (property (unwrap! (map-get? properties tx-sender) (err u50)))
            (current-height stacks-block-height)
            (payment-due (get next-payment-due property))
            (grace-period-end (+ payment-due grace-period-blocks))
        )
        (asserts! (is-eq (get status property) "ACTIVE") (err u51))
        (asserts! (> current-height grace-period-end) (err u52))
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
            (property (unwrap! (map-get? properties tx-sender) (err u60)))
            (late-fees (get late-fees-owed property))
        )
        (asserts! (> late-fees u0) (err u61))
        (asserts! (is-eq tx-sender (get tenant property)) (err u62))
        (try! (stx-transfer? late-fees tx-sender (get owner property)))
        (map-set properties tx-sender (merge property { late-fees-owed: u0 }))
        (ok true)
    )
)

(define-public (request-early-termination (property-id uint))
    (let (
            (property (unwrap! (map-get? properties tx-sender) (err u70)))
            (escrow (unwrap! (map-get? escrow-balances tx-sender) (err u71)))
            (total-payments-required (/ (get total-amount property) (get monthly-amount property)))
            (payments-completed (get payments-completed property))
            (completion-ratio (/ (* payments-completed u100) total-payments-required))
            (owner-refund (if (> completion-ratio u50)
                (/ (* (get owner-portion escrow) completion-ratio) u100)
                (get owner-portion escrow)
            ))
            (tenant-refund (- (get total-escrowed escrow) owner-refund))
        )
        (asserts! (is-eq (get status property) "ACTIVE") (err u72))
        (asserts!
            (or
                (is-eq tx-sender (get owner property))
                (is-eq tx-sender (get tenant property))
            )
            (err u73)
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

(define-read-only (get-escrow-balance (property-owner principal))
    (map-get? escrow-balances property-owner)
)

(define-read-only (calculate-refund-amounts (property-owner principal))
    (let (
            (property (unwrap! (map-get? properties property-owner) (err u80)))
            (escrow (unwrap! (map-get? escrow-balances property-owner) (err u81)))
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
