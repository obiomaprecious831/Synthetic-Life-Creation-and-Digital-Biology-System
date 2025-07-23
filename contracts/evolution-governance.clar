;; Evolutionary Simulation Governance Contract
;; Oversees accelerated evolution experiments in controlled environments

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u500))
(define-constant ERR-EXPERIMENT-NOT-FOUND (err u501))
(define-constant ERR-INVALID-PARAMETERS (err u502))
(define-constant ERR-EXPERIMENT-RUNNING (err u503))
(define-constant ERR-INSUFFICIENT-APPROVAL (err u504))
(define-constant ERR-COOLING-PERIOD-ACTIVE (err u505))

;; Data Variables
(define-data-var next-experiment-id uint u1)
(define-data-var total-experiments uint u0)
(define-data-var cooling-period-blocks uint u1440) ;; ~24 hours
(define-data-var required-approvals uint u3)

;; Data Maps
(define-map evolution-experiments
  { experiment-id: uint }
  {
    researcher: principal,
    life-form-id: uint,
    experiment-type: (string-ascii 50),
    generation-target: uint,
    mutation-rate: uint,
    selection-pressure: uint,
    environment-hash: (buff 32),
    status: (string-ascii 20),
    start-block: uint,
    end-block: uint,
    current-generation: uint,
    approval-count: uint
  }
)

(define-map experiment-approvals
  { experiment-id: uint, approver: principal }
  {
    approved: bool,
    approval-timestamp: uint,
    risk-assessment: uint,
    conditions: (string-ascii 100)
  }
)

(define-map simulation-environments
  { environment-id: uint }
  {
    name: (string-ascii 50),
    environment-type: (string-ascii 30),
    resource-availability: uint,
    predation-level: uint,
    mutation-factors: (list 10 uint),
    stability-rating: uint,
    max-population: uint,
    active: bool
  }
)

(define-map generation-data
  { experiment-id: uint, generation: uint }
  {
    population-size: uint,
    fitness-average: uint,
    mutation-count: uint,
    survival-rate: uint,
    dominant-traits: (list 5 uint),
    timestamp: uint
  }
)

(define-map researcher-permissions
  { researcher: principal }
  {
    clearance-level: uint,
    max-mutation-rate: uint,
    max-generations: uint,
    approved-environments: (list 20 uint),
    experiment-count: uint,
    last-experiment: uint
  }
)

;; Public Functions

;; Propose evolution experiment
(define-public (propose-experiment (life-form-id uint) (experiment-type (string-ascii 50)) (generation-target uint) (mutation-rate uint) (selection-pressure uint) (environment-id uint))
  (let
    (
      (experiment-id (var-get next-experiment-id))
      (researcher-perms (unwrap! (map-get? researcher-permissions { researcher: tx-sender }) ERR-NOT-AUTHORIZED))
    )
    (asserts! (>= (get clearance-level researcher-perms) u2) ERR-NOT-AUTHORIZED)
    (asserts! (<= mutation-rate (get max-mutation-rate researcher-perms)) ERR-INVALID-PARAMETERS)
    (asserts! (<= generation-target (get max-generations researcher-perms)) ERR-INVALID-PARAMETERS)
    (asserts! (<= selection-pressure u100) ERR-INVALID-PARAMETERS)
    (asserts! (>= (- block-height (get last-experiment researcher-perms)) (var-get cooling-period-blocks)) ERR-COOLING-PERIOD-ACTIVE)

    (map-set evolution-experiments
      { experiment-id: experiment-id }
      {
        researcher: tx-sender,
        life-form-id: life-form-id,
        experiment-type: experiment-type,
        generation-target: generation-target,
        mutation-rate: mutation-rate,
        selection-pressure: selection-pressure,
        environment-hash: (unwrap-panic (get-environment-hash environment-id)),
        status: "proposed",
        start-block: u0,
        end-block: u0,
        current-generation: u0,
        approval-count: u0
      }
    )

    (var-set next-experiment-id (+ experiment-id u1))
    (var-set total-experiments (+ (var-get total-experiments) u1))

    (ok experiment-id)
  )
)

;; Approve experiment
(define-public (approve-experiment (experiment-id uint) (risk-assessment uint) (conditions (string-ascii 100)))
  (let
    (
      (experiment (unwrap! (map-get? evolution-experiments { experiment-id: experiment-id }) ERR-EXPERIMENT-NOT-FOUND))
      (researcher-perms (unwrap! (map-get? researcher-permissions { researcher: tx-sender }) ERR-NOT-AUTHORIZED))
    )
    (asserts! (>= (get clearance-level researcher-perms) u3) ERR-NOT-AUTHORIZED)
    (asserts! (is-eq (get status experiment) "proposed") ERR-EXPERIMENT-RUNNING)
    (asserts! (<= risk-assessment u10) ERR-INVALID-PARAMETERS)

    (map-set experiment-approvals
      { experiment-id: experiment-id, approver: tx-sender }
      {
        approved: true,
        approval-timestamp: block-height,
        risk-assessment: risk-assessment,
        conditions: conditions
      }
    )

    (map-set evolution-experiments
      { experiment-id: experiment-id }
      (merge experiment { approval-count: (+ (get approval-count experiment) u1) })
    )

    (ok true)
  )
)

;; Start experiment
(define-public (start-experiment (experiment-id uint))
  (let
    (
      (experiment (unwrap! (map-get? evolution-experiments { experiment-id: experiment-id }) ERR-EXPERIMENT-NOT-FOUND))
    )
    (asserts! (is-eq tx-sender (get researcher experiment)) ERR-NOT-AUTHORIZED)
    (asserts! (>= (get approval-count experiment) (var-get required-approvals)) ERR-INSUFFICIENT-APPROVAL)
    (asserts! (is-eq (get status experiment) "proposed") ERR-EXPERIMENT-RUNNING)

    (map-set evolution-experiments
      { experiment-id: experiment-id }
      (merge experiment {
        status: "running",
        start-block: block-height,
        current-generation: u1
      })
    )

    ;; Update researcher's last experiment timestamp
    (update-researcher-last-experiment tx-sender)

    (ok true)
  )
)

;; Record generation data
(define-public (record-generation (experiment-id uint) (generation uint) (population-size uint) (fitness-average uint) (mutation-count uint) (survival-rate uint) (dominant-traits (list 5 uint)))
  (let
    (
      (experiment (unwrap! (map-get? evolution-experiments { experiment-id: experiment-id }) ERR-EXPERIMENT-NOT-FOUND))
    )
    (asserts! (is-eq tx-sender (get researcher experiment)) ERR-NOT-AUTHORIZED)
    (asserts! (is-eq (get status experiment) "running") ERR-EXPERIMENT-RUNNING)
    (asserts! (<= survival-rate u100) ERR-INVALID-PARAMETERS)

    (map-set generation-data
      { experiment-id: experiment-id, generation: generation }
      {
        population-size: population-size,
        fitness-average: fitness-average,
        mutation-count: mutation-count,
        survival-rate: survival-rate,
        dominant-traits: dominant-traits,
        timestamp: block-height
      }
    )

    ;; Update current generation
    (map-set evolution-experiments
      { experiment-id: experiment-id }
      (merge experiment { current-generation: generation })
    )

    (ok true)
  )
)

;; Complete experiment
(define-public (complete-experiment (experiment-id uint))
  (let
    (
      (experiment (unwrap! (map-get? evolution-experiments { experiment-id: experiment-id }) ERR-EXPERIMENT-NOT-FOUND))
    )
    (asserts! (is-eq tx-sender (get researcher experiment)) ERR-NOT-AUTHORIZED)
    (asserts! (is-eq (get status experiment) "running") ERR-EXPERIMENT-RUNNING)

    (map-set evolution-experiments
      { experiment-id: experiment-id }
      (merge experiment {
        status: "completed",
        end-block: block-height
      })
    )

    (ok true)
  )
)

;; Create simulation environment
(define-public (create-environment (name (string-ascii 50)) (environment-type (string-ascii 30)) (resource-availability uint) (predation-level uint) (mutation-factors (list 10 uint)) (max-population uint))
  (let
    (
      (environment-id (var-get next-experiment-id))
    )
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (asserts! (<= resource-availability u100) ERR-INVALID-PARAMETERS)
    (asserts! (<= predation-level u100) ERR-INVALID-PARAMETERS)

    (map-set simulation-environments
      { environment-id: environment-id }
      {
        name: name,
        environment-type: environment-type,
        resource-availability: resource-availability,
        predation-level: predation-level,
        mutation-factors: mutation-factors,
        stability-rating: u5,
        max-population: max-population,
        active: true
      }
    )

    (ok environment-id)
  )
)

;; Grant researcher permissions
(define-public (grant-researcher-permissions (researcher principal) (clearance-level uint) (max-mutation-rate uint) (max-generations uint) (approved-environments (list 20 uint)))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (asserts! (<= clearance-level u5) ERR-INVALID-PARAMETERS)
    (asserts! (<= max-mutation-rate u100) ERR-INVALID-PARAMETERS)

    (map-set researcher-permissions
      { researcher: researcher }
      {
        clearance-level: clearance-level,
        max-mutation-rate: max-mutation-rate,
        max-generations: max-generations,
        approved-environments: approved-environments,
        experiment-count: u0,
        last-experiment: u0
      }
    )

    (ok true)
  )
)

;; Read-only Functions

;; Get experiment details
(define-read-only (get-experiment (experiment-id uint))
  (map-get? evolution-experiments { experiment-id: experiment-id })
)

;; Get experiment approval
(define-read-only (get-approval (experiment-id uint) (approver principal))
  (map-get? experiment-approvals { experiment-id: experiment-id, approver: approver })
)

;; Get simulation environment
(define-read-only (get-environment (environment-id uint))
  (map-get? simulation-environments { environment-id: environment-id })
)

;; Get generation data
(define-read-only (get-generation-data (experiment-id uint) (generation uint))
  (map-get? generation-data { experiment-id: experiment-id, generation: generation })
)

;; Get researcher permissions
(define-read-only (get-researcher-permissions (researcher principal))
  (map-get? researcher-permissions { researcher: researcher })
)

;; Get total experiments
(define-read-only (get-total-experiments)
  (var-get total-experiments)
)

;; Check if experiment can start
(define-read-only (can-start-experiment (experiment-id uint))
  (match (map-get? evolution-experiments { experiment-id: experiment-id })
    experiment (and
      (is-eq (get status experiment) "proposed")
      (>= (get approval-count experiment) (var-get required-approvals))
    )
    false
  )
)

;; Private Functions

;; Get environment hash
(define-private (get-environment-hash (environment-id uint))
  (match (map-get? simulation-environments { environment-id: environment-id })
    environment (some (sha256 (concat (unwrap-panic (to-consensus-buff? environment-id)) (unwrap-panic (to-consensus-buff? (get max-population environment))))))
    none
  )
)

;; Update researcher's last experiment timestamp
(define-private (update-researcher-last-experiment (researcher principal))
  (match (map-get? researcher-permissions { researcher: researcher })
    perms (map-set researcher-permissions
      { researcher: researcher }
      (merge perms {
        last-experiment: block-height,
        experiment-count: (+ (get experiment-count perms) u1)
      })
    )
    false
  )
)
