;; Verification Registry - Carbon Project Verification and Compliance System
;; This contract manages the verification process for carbon offset projects

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u200))
(define-constant ERR-VERIFIER-NOT-FOUND (err u201))
(define-constant ERR-INVALID-STATUS (err u202))
(define-constant ERR-PROJECT-NOT-FOUND (err u203))
(define-constant ERR-ALREADY-VERIFIED (err u204))
(define-constant ERR-INVALID-METHODOLOGY (err u205))
(define-constant ERR-INSUFFICIENT-EVIDENCE (err u206))

;; Verification status constants
(define-constant STATUS-PENDING u1)
(define-constant STATUS-IN-REVIEW u2)
(define-constant STATUS-VERIFIED u3)
(define-constant STATUS-REJECTED u4)
(define-constant STATUS-SUSPENDED u5)

;; Verification standards
(define-constant VCS-STANDARD u1)      ;; Verified Carbon Standard
(define-constant GOLD-STANDARD u2)     ;; Gold Standard
(define-constant CAR-STANDARD u3)      ;; Climate Action Reserve
(define-constant CDM-STANDARD u4)      ;; Clean Development Mechanism
(define-constant CUSTOM-STANDARD u5)   ;; Custom verification

;; Data Variables
(define-data-var verifier-counter uint u0)
(define-data-var verification-counter uint u0)
(define-data-var methodology-counter uint u0)

;; Authorized Verifiers
(define-map authorized-verifiers
  { verifier-id: uint }
  {
    verifier-address: principal,
    organization-name: (string-ascii 100),
    accreditation-body: (string-ascii 50),
    specialization: (list 5 uint), ;; List of standards they can verify
    is-active: bool,
    verification-count: uint,
    registration-date: uint,
    contact-info: (string-ascii 200)
  }
)

;; Verification Applications
(define-map verification-applications
  { application-id: uint }
  {
    project-id: uint,
    applicant: principal,
    methodology-id: uint,
    verification-standard: uint,
    assigned-verifier: uint,
    status: uint,
    application-date: uint,
    review-deadline: uint,
    verification-fee: uint,
    evidence-hash: (string-ascii 64), ;; IPFS hash or similar
    comments: (string-ascii 500)
  }
)

;; Verification Methodologies
(define-map verification-methodologies
  { methodology-id: uint }
  {
    name: (string-ascii 100),
    version: (string-ascii 20),
    applicable-standards: (list 5 uint),
    project-types: (list 10 uint),
    requirements: (string-ascii 500),
    monitoring-frequency: uint, ;; In blocks
    validity-period: uint, ;; In blocks
    created-by: principal,
    approval-date: uint,
    is-active: bool
  }
)

;; Verification History
(define-map verification-history
  { project-id: uint, verification-id: uint }
  {
    verifier-id: uint,
    verification-date: uint,
    expiry-date: uint,
    standard-used: uint,
    methodology-used: uint,
    credits-verified: uint,
    verification-report: (string-ascii 200), ;; IPFS hash
    is-current: bool
  }
)

;; Monitoring Requirements
(define-map monitoring-schedules
  { project-id: uint }
  {
    next-monitoring-date: uint,
    monitoring-frequency: uint,
    last-report-date: uint,
    compliance-status: uint,
    assigned-monitor: uint,
    monitoring-requirements: (string-ascii 300)
  }
)

;; Compliance Violations
(define-map compliance-violations
  { violation-id: uint }
  {
    project-id: uint,
    violation-type: (string-ascii 50),
    severity-level: uint, ;; 1=minor, 2=major, 3=critical
    reported-date: uint,
    reported-by: principal,
    description: (string-ascii 500),
    resolution-status: uint,
    resolution-date: uint,
    corrective-actions: (string-ascii 300)
  }
)

;; Public Functions

;; Register as an authorized verifier
(define-public (register-verifier
  (organization-name (string-ascii 100))
  (accreditation-body (string-ascii 50))
  (specialization (list 5 uint))
  (contact-info (string-ascii 200)))
  (let
    (
      (verifier-id (+ (var-get verifier-counter) u1))
    )
    ;; Validate specialization standards
    (asserts! (> (len specialization) u0) ERR-INVALID-STATUS)
    
    (map-set authorized-verifiers
      { verifier-id: verifier-id }
      {
        verifier-address: tx-sender,
        organization-name: organization-name,
        accreditation-body: accreditation-body,
        specialization: specialization,
        is-active: false, ;; Requires admin approval
        verification-count: u0,
        registration-date: stacks-block-height,
        contact-info: contact-info
      }
    )
    
    (var-set verifier-counter verifier-id)
    
    (ok verifier-id)
  )
)

;; Approve verifier (admin only)
(define-public (approve-verifier (verifier-id uint))
  (let
    (
      (verifier (unwrap! (map-get? authorized-verifiers { verifier-id: verifier-id }) ERR-VERIFIER-NOT-FOUND))
    )
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    
    (map-set authorized-verifiers
      { verifier-id: verifier-id }
      (merge verifier { is-active: true })
    )
    
    (ok true)
  )
)

;; Submit project for verification
(define-public (submit-for-verification
  (project-id uint)
  (methodology-id uint)
  (verification-standard uint)
  (evidence-hash (string-ascii 64))
  (verification-fee uint))
  (let
    (
      (application-id (+ (var-get verification-counter) u1))
      (methodology (unwrap! (map-get? verification-methodologies { methodology-id: methodology-id }) ERR-INVALID-METHODOLOGY))
    )
    (asserts! (get is-active methodology) ERR-INVALID-METHODOLOGY)
    (asserts! (> verification-fee u0) ERR-INSUFFICIENT-EVIDENCE)
    
    ;; Transfer verification fee to contract
    (try! (stx-transfer? verification-fee tx-sender (as-contract tx-sender)))
    
    (map-set verification-applications
      { application-id: application-id }
      {
        project-id: project-id,
        applicant: tx-sender,
        methodology-id: methodology-id,
        verification-standard: verification-standard,
        assigned-verifier: u0, ;; Will be assigned later
        status: STATUS-PENDING,
        application-date: stacks-block-height,
        review-deadline: (+ stacks-block-height u2160), ;; 15 days
        verification-fee: verification-fee,
        evidence-hash: evidence-hash,
        comments: ""
      }
    )
    
    (var-set verification-counter application-id)
    
    (ok application-id)
  )
)

;; Assign verifier to application (admin only)
(define-public (assign-verifier (application-id uint) (verifier-id uint))
  (let
    (
      (application (unwrap! (map-get? verification-applications { application-id: application-id }) ERR-PROJECT-NOT-FOUND))
      (verifier (unwrap! (map-get? authorized-verifiers { verifier-id: verifier-id }) ERR-VERIFIER-NOT-FOUND))
    )
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (asserts! (get is-active verifier) ERR-VERIFIER-NOT-FOUND)
    (asserts! (is-eq (get status application) STATUS-PENDING) ERR-INVALID-STATUS)
    
    (map-set verification-applications
      { application-id: application-id }
      (merge application {
        assigned-verifier: verifier-id,
        status: STATUS-IN-REVIEW
      })
    )
    
    (ok true)
  )
)

;; Complete verification process (verifier only)
(define-public (complete-verification
  (application-id uint)
  (verification-result uint)
  (credits-verified uint)
  (verification-report (string-ascii 200))
  (comments (string-ascii 500)))
  (let
    (
      (application (unwrap! (map-get? verification-applications { application-id: application-id }) ERR-PROJECT-NOT-FOUND))
      (verifier-id (get assigned-verifier application))
      (verifier (unwrap! (map-get? authorized-verifiers { verifier-id: verifier-id }) ERR-VERIFIER-NOT-FOUND))
      (methodology (unwrap! (map-get? verification-methodologies { methodology-id: (get methodology-id application) }) ERR-INVALID-METHODOLOGY))
      (verification-id (+ (var-get verification-counter) u1))
    )
    (asserts! (is-eq tx-sender (get verifier-address verifier)) ERR-NOT-AUTHORIZED)
    (asserts! (is-eq (get status application) STATUS-IN-REVIEW) ERR-INVALID-STATUS)
    (asserts! (or (is-eq verification-result STATUS-VERIFIED) (is-eq verification-result STATUS-REJECTED)) ERR-INVALID-STATUS)
    
    ;; Update application status
    (map-set verification-applications
      { application-id: application-id }
      (merge application {
        status: verification-result,
        comments: comments
      })
    )
    
    ;; If verified, record verification history
    (if (is-eq verification-result STATUS-VERIFIED)
      (begin
        (map-set verification-history
          { project-id: (get project-id application), verification-id: verification-id }
          {
            verifier-id: verifier-id,
            verification-date: stacks-block-height,
            expiry-date: (+ stacks-block-height (get validity-period methodology)),
            standard-used: (get verification-standard application),
            methodology-used: (get methodology-id application),
            credits-verified: credits-verified,
            verification-report: verification-report,
            is-current: true
          }
        )
        
        ;; Set up monitoring schedule
        (map-set monitoring-schedules
          { project-id: (get project-id application) }
          {
            next-monitoring-date: (+ stacks-block-height (get monitoring-frequency methodology)),
            monitoring-frequency: (get monitoring-frequency methodology),
            last-report-date: stacks-block-height,
            compliance-status: u1, ;; Compliant
            assigned-monitor: verifier-id,
            monitoring-requirements: ""
          }
        )
        
        ;; Update verifier stats
        (map-set authorized-verifiers
          { verifier-id: verifier-id }
          (merge verifier { verification-count: (+ (get verification-count verifier) u1) })
        )
        
        ;; Pay verifier (80% of fee)
        (let ((verifier-payment (/ (* (get verification-fee application) u8) u10)))
          (try! (as-contract (stx-transfer? verifier-payment tx-sender (get verifier-address verifier))))
        )
      )
      ;; If rejected, refund 50% of fee
      (let ((refund-amount (/ (get verification-fee application) u2)))
        (try! (as-contract (stx-transfer? refund-amount tx-sender (get applicant application))))
      )
    )
    
    (var-set verification-counter verification-id)
    
    (ok verification-result)
  )
)

;; Create new verification methodology (admin only)
(define-public (create-methodology
  (name (string-ascii 100))
  (version (string-ascii 20))
  (applicable-standards (list 5 uint))
  (project-types (list 10 uint))
  (requirements (string-ascii 500))
  (monitoring-frequency uint)
  (validity-period uint))
  (let
    (
      (methodology-id (+ (var-get methodology-counter) u1))
    )
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (asserts! (> monitoring-frequency u0) ERR-INVALID-METHODOLOGY)
    (asserts! (> validity-period u0) ERR-INVALID-METHODOLOGY)
    
    (map-set verification-methodologies
      { methodology-id: methodology-id }
      {
        name: name,
        version: version,
        applicable-standards: applicable-standards,
        project-types: project-types,
        requirements: requirements,
        monitoring-frequency: monitoring-frequency,
        validity-period: validity-period,
        created-by: tx-sender,
        approval-date: stacks-block-height,
        is-active: true
      }
    )
    
    (var-set methodology-counter methodology-id)
    
    (ok methodology-id)
  )
)

;; Report compliance violation
(define-public (report-violation
  (project-id uint)
  (violation-type (string-ascii 50))
  (severity-level uint)
  (description (string-ascii 500)))
  (let
    (
      (violation-id (+ (var-get verification-counter) u1))
    )
    (asserts! (and (>= severity-level u1) (<= severity-level u3)) ERR-INVALID-STATUS)
    
    (map-set compliance-violations
      { violation-id: violation-id }
      {
        project-id: project-id,
        violation-type: violation-type,
        severity-level: severity-level,
        reported-date: stacks-block-height,
        reported-by: tx-sender,
        description: description,
        resolution-status: u1, ;; Open
        resolution-date: u0,
        corrective-actions: ""
      }
    )
    
    ;; If critical violation, suspend project verification
    (if (is-eq severity-level u3)
      (suspend-project-verification project-id)
      (ok true)
    )
  )
)

;; Suspend project verification (internal function)
(define-private (suspend-project-verification (project-id uint))
  (begin
    ;; Update monitoring schedule
    (match (map-get? monitoring-schedules { project-id: project-id })
      schedule
      (map-set monitoring-schedules
        { project-id: project-id }
        (merge schedule { compliance-status: u3 }) ;; Non-compliant
      )
      true
    )
    (ok true)
  )
)

;; Read-only Functions

;; Get verifier information
(define-read-only (get-verifier (verifier-id uint))
  (map-get? authorized-verifiers { verifier-id: verifier-id })
)

;; Get verification application
(define-read-only (get-application (application-id uint))
  (map-get? verification-applications { application-id: application-id })
)

;; Get methodology details
(define-read-only (get-methodology (methodology-id uint))
  (map-get? verification-methodologies { methodology-id: methodology-id })
)

;; Get verification history for project
(define-read-only (get-verification-history (project-id uint) (verification-id uint))
  (map-get? verification-history { project-id: project-id, verification-id: verification-id })
)

;; Get monitoring schedule
(define-read-only (get-monitoring-schedule (project-id uint))
  (map-get? monitoring-schedules { project-id: project-id })
)

;; Get compliance violation
(define-read-only (get-violation (violation-id uint))
  (map-get? compliance-violations { violation-id: violation-id })
)

;; Check if project is currently verified
(define-read-only (is-project-verified (project-id uint))
  (match (map-get? monitoring-schedules { project-id: project-id })
    schedule (and (is-eq (get compliance-status schedule) u1) (<= stacks-block-height (get next-monitoring-date schedule)))
    false
  )
)

;; Get verification statistics
(define-read-only (get-verification-stats)
  {
    total-verifiers: (var-get verifier-counter),
    total-applications: (var-get verification-counter),
    total-methodologies: (var-get methodology-counter)
  }
)

;; title: verification-registry
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

