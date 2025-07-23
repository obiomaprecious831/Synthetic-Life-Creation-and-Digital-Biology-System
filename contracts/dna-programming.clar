;; Digital DNA Programming Contract
;; Manages genetic code design for engineered organisms

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u200))
(define-constant ERR-DNA-EXISTS (err u201))
(define-constant ERR-DNA-NOT-FOUND (err u202))
(define-constant ERR-INVALID-SAFETY-RATING (err u203))
(define-constant ERR-INVALID-BASE-PAIRS (err u204))
(define-constant ERR-SEQUENCE-TOO-DANGEROUS (err u205))

;; Data Variables
(define-data-var next-sequence-id uint u1)
(define-data-var total-sequences uint u0)
(define-data-var max-safety-rating uint u10)

;; Data Maps
(define-map dna-sequences
  { sequence-id: uint }
  {
    sequence-hash: (buff 32),
    creator: principal,
    creation-block: uint,
    base-pair-count: uint,
    safety-rating: uint,
    validation-status: (string-ascii 20),
    modification-count: uint,
    last-modified: uint
  }
)

(define-map sequence-modifications
  { sequence-id: uint, modification-id: uint }
  {
    modifier: principal,
    modification-type: (string-ascii 50),
    target-region: uint,
    modification-data: (buff 64),
    timestamp: uint,
    approved: bool
  }
)

(define-map genetic-templates
  { template-id: uint }
  {
    name: (string-ascii 50),
    base-sequence: (buff 32),
    safety-level: uint,
    usage-count: uint,
    creator: principal
  }
)

(define-map sequence-compatibility
  { sequence-a: uint, sequence-b: uint }
  {
    compatibility-score: uint,
    interaction-type: (string-ascii 30),
    risk-level: uint,
    tested: bool
  }
)

;; Public Functions

;; Store a new DNA sequence
(define-public (store-dna-sequence (sequence-hash (buff 32)) (base-pair-count uint) (safety-rating uint))
  (let
    (
      (sequence-id (var-get next-sequence-id))
    )
    (asserts! (and (>= safety-rating u1) (<= safety-rating (var-get max-safety-rating))) ERR-INVALID-SAFETY-RATING)
    (asserts! (> base-pair-count u0) ERR-INVALID-BASE-PAIRS)
    (asserts! (>= safety-rating u3) ERR-SEQUENCE-TOO-DANGEROUS)

    (map-set dna-sequences
      { sequence-id: sequence-id }
      {
        sequence-hash: sequence-hash,
        creator: tx-sender,
        creation-block: block-height,
        base-pair-count: base-pair-count,
        safety-rating: safety-rating,
        validation-status: "pending",
        modification-count: u0,
        last-modified: block-height
      }
    )

    (var-set next-sequence-id (+ sequence-id u1))
    (var-set total-sequences (+ (var-get total-sequences) u1))

    (ok sequence-id)
  )
)

;; Validate DNA sequence
(define-public (validate-sequence (sequence-id uint) (validation-status (string-ascii 20)))
  (let
    (
      (sequence (unwrap! (map-get? dna-sequences { sequence-id: sequence-id }) ERR-DNA-NOT-FOUND))
    )
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)

    (map-set dna-sequences
      { sequence-id: sequence-id }
      (merge sequence { validation-status: validation-status, last-modified: block-height })
    )

    (ok true)
  )
)

;; Add genetic modification
(define-public (add-modification (sequence-id uint) (modification-type (string-ascii 50)) (target-region uint) (modification-data (buff 64)))
  (let
    (
      (sequence (unwrap! (map-get? dna-sequences { sequence-id: sequence-id }) ERR-DNA-NOT-FOUND))
      (modification-id (get modification-count sequence))
    )
    (asserts! (or (is-eq tx-sender (get creator sequence)) (is-eq tx-sender CONTRACT-OWNER)) ERR-NOT-AUTHORIZED)
    (asserts! (>= (get safety-rating sequence) u5) ERR-SEQUENCE-TOO-DANGEROUS)

    (map-set sequence-modifications
      { sequence-id: sequence-id, modification-id: modification-id }
      {
        modifier: tx-sender,
        modification-type: modification-type,
        target-region: target-region,
        modification-data: modification-data,
        timestamp: block-height,
        approved: false
      }
    )

    (map-set dna-sequences
      { sequence-id: sequence-id }
      (merge sequence {
        modification-count: (+ modification-id u1),
        last-modified: block-height
      })
    )

    (ok modification-id)
  )
)

;; Approve genetic modification
(define-public (approve-modification (sequence-id uint) (modification-id uint))
  (let
    (
      (modification (unwrap! (map-get? sequence-modifications { sequence-id: sequence-id, modification-id: modification-id }) ERR-DNA-NOT-FOUND))
    )
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)

    (map-set sequence-modifications
      { sequence-id: sequence-id, modification-id: modification-id }
      (merge modification { approved: true })
    )

    (ok true)
  )
)

;; Create genetic template
(define-public (create-template (name (string-ascii 50)) (base-sequence (buff 32)) (safety-level uint))
  (let
    (
      (template-id (var-get next-sequence-id))
    )
    (asserts! (and (>= safety-level u1) (<= safety-level u10)) ERR-INVALID-SAFETY-RATING)

    (map-set genetic-templates
      { template-id: template-id }
      {
        name: name,
        base-sequence: base-sequence,
        safety-level: safety-level,
        usage-count: u0,
        creator: tx-sender
      }
    )

    (ok template-id)
  )
)

;; Test sequence compatibility
(define-public (test-compatibility (sequence-a uint) (sequence-b uint) (compatibility-score uint) (interaction-type (string-ascii 30)) (risk-level uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (asserts! (<= risk-level u10) ERR-INVALID-SAFETY-RATING)

    (map-set sequence-compatibility
      { sequence-a: sequence-a, sequence-b: sequence-b }
      {
        compatibility-score: compatibility-score,
        interaction-type: interaction-type,
        risk-level: risk-level,
        tested: true
      }
    )

    (ok true)
  )
)

;; Read-only Functions

;; Get DNA sequence
(define-read-only (get-dna-sequence (sequence-id uint))
  (map-get? dna-sequences { sequence-id: sequence-id })
)

;; Get sequence modification
(define-read-only (get-modification (sequence-id uint) (modification-id uint))
  (map-get? sequence-modifications { sequence-id: sequence-id, modification-id: modification-id })
)

;; Get genetic template
(define-read-only (get-template (template-id uint))
  (map-get? genetic-templates { template-id: template-id })
)

;; Get sequence compatibility
(define-read-only (get-compatibility (sequence-a uint) (sequence-b uint))
  (map-get? sequence-compatibility { sequence-a: sequence-a, sequence-b: sequence-b })
)

;; Get total sequences
(define-read-only (get-total-sequences)
  (var-get total-sequences)
)

;; Check if sequence is safe for modification
(define-read-only (is-safe-for-modification (sequence-id uint))
  (match (map-get? dna-sequences { sequence-id: sequence-id })
    sequence (>= (get safety-rating sequence) u5)
    false
  )
)
