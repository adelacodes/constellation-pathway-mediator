;; Constellation Pathway Mediator

;; Main Database Structure
(define-map LinkTransactions
  { transaction-reference: uint }
  {
    origin-party: principal,
    target-party: principal,
    item-type: uint,
    transfer-amount: uint,
    transaction-status: (string-ascii 10),
    created-at-block: uint,
    expiration-block: uint
  }
)

;; -------------------------------------------------------------
;; Core Validation Functions
;; -------------------------------------------------------------

;; Check Party Separation
(define-private (check-party-separation (party principal))
  (and 
    (not (is-eq party tx-sender))
    (not (is-eq party (as-contract tx-sender)))
  )
)



;; Transaction Counter
(define-data-var next-transaction-id uint u0)

;; Administrative Settings and Response Codes
(define-constant ADMIN_CONTROLLER tx-sender)
(define-constant ERROR_ACCESS_DENIED (err u100))
(define-constant ERROR_NO_MATCHING_ENTRY (err u101))
(define-constant ERROR_ENTRY_PROCESSED (err u102))
(define-constant ERROR_ACTION_UNSUCCESSFUL (err u103))
(define-constant ERROR_INVALID_REFERENCE (err u104))
(define-constant ERROR_BAD_INPUT (err u105))
(define-constant ERROR_UNAUTHORIZED_PARTICIPANT (err u106))
(define-constant ERROR_PERIOD_LAPSED (err u107))
(define-constant TIMEFRAME_BLOCKS u1008)

;; Validate Transaction Reference
(define-private (validate-transaction-reference (transaction-reference uint))
  (<= transaction-reference (var-get next-transaction-id))
)

;; Reclaim Resources From Expired Transaction
(define-public (reclaim-expired-resources (transaction-reference uint))
  (begin
    (asserts! (validate-transaction-reference transaction-reference) ERROR_INVALID_REFERENCE)
    (let
      (
        (transaction-data (unwrap! (map-get? LinkTransactions { transaction-reference: transaction-reference }) ERROR_NO_MATCHING_ENTRY))
        (origin (get origin-party transaction-data))
        (amount (get transfer-amount transaction-data))
        (end-block (get expiration-block transaction-data))
      )
      (asserts! (or (is-eq tx-sender origin) (is-eq tx-sender ADMIN_CONTROLLER)) ERROR_ACCESS_DENIED)
      (asserts! (or (is-eq (get transaction-status transaction-data) "pending") (is-eq (get transaction-status transaction-data) "accepted")) ERROR_ENTRY_PROCESSED)
      (asserts! (> block-height end-block) (err u108)) ;; Must be expired
      (match (as-contract (stx-transfer? amount tx-sender origin))
        success
          (begin
            (map-set LinkTransactions
              { transaction-reference: transaction-reference }
              (merge transaction-data { transaction-status: "expired" })
            )
            (print {event: "resources_reclaimed", transaction-reference: transaction-reference, origin: origin, amount: amount})
            (ok true)
          )
        error ERROR_ACTION_UNSUCCESSFUL
      )
    )
  )
)

;; Initiate Conflict Resolution
(define-public (initiate-conflict-resolution (transaction-reference uint) (resolution-reason (string-ascii 50)))
  (begin
    (asserts! (validate-transaction-reference transaction-reference) ERROR_INVALID_REFERENCE)
    (let
      (
        (transaction-data (unwrap! (map-get? LinkTransactions { transaction-reference: transaction-reference }) ERROR_NO_MATCHING_ENTRY))
        (origin (get origin-party transaction-data))
        (target (get target-party transaction-data))
      )
      (asserts! (or (is-eq tx-sender origin) (is-eq tx-sender target)) ERROR_ACCESS_DENIED)
      (asserts! (or (is-eq (get transaction-status transaction-data) "pending") (is-eq (get transaction-status transaction-data) "accepted")) ERROR_ENTRY_PROCESSED)
      (asserts! (<= block-height (get expiration-block transaction-data)) ERROR_PERIOD_LAPSED)
      (map-set LinkTransactions
        { transaction-reference: transaction-reference }
        (merge transaction-data { transaction-status: "disputed" })
      )
      (print {event: "conflict_initiated", transaction-reference: transaction-reference, starter: tx-sender, reason: resolution-reason})
      (ok true)
    )
  )
)

;; Adjudicate Disputed Transaction
(define-public (adjudicate-transaction (transaction-reference uint) (allocation-ratio uint))
  (begin
    (asserts! (validate-transaction-reference transaction-reference) ERROR_INVALID_REFERENCE)
    (asserts! (is-eq tx-sender ADMIN_CONTROLLER) ERROR_ACCESS_DENIED)
    (asserts! (<= allocation-ratio u100) ERROR_BAD_INPUT) ;; Ratio must be 0-100
    (let
      (
        (transaction-data (unwrap! (map-get? LinkTransactions { transaction-reference: transaction-reference }) ERROR_NO_MATCHING_ENTRY))
        (origin (get origin-party transaction-data))
        (target (get target-party transaction-data))
        (amount (get transfer-amount transaction-data))
        (target-share (/ (* amount allocation-ratio) u100))
        (origin-share (- amount target-share))
      )
      (asserts! (is-eq (get transaction-status transaction-data) "disputed") (err u112)) ;; Must be disputed
      (asserts! (<= block-height (get expiration-block transaction-data)) ERROR_PERIOD_LAPSED)

      ;; Transfer target share
      (unwrap! (as-contract (stx-transfer? target-share tx-sender target)) ERROR_ACTION_UNSUCCESSFUL)

      ;; Transfer origin share
      (unwrap! (as-contract (stx-transfer? origin-share tx-sender origin)) ERROR_ACTION_UNSUCCESSFUL)
      (print {event: "transaction_adjudicated", transaction-reference: transaction-reference, origin: origin, target: target, 
              target-share: target-share, origin-share: origin-share, allocation-ratio: allocation-ratio})
      (ok true)
    )
  )
)

