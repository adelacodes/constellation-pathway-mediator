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
