(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u100))
(define-constant ERR_INVALID_PROPOSAL (err u101))
(define-constant ERR_PROPOSAL_NOT_FOUND (err u102))
(define-constant ERR_VOTING_ENDED (err u103))
(define-constant ERR_VOTING_NOT_ENDED (err u104))
(define-constant ERR_ALREADY_VOTED (err u105))
(define-constant ERR_INSUFFICIENT_FUNDS (err u106))
(define-constant ERR_PROPOSAL_ALREADY_EXECUTED (err u107))
(define-constant ERR_INVALID_AMOUNT (err u108))
(define-constant ERR_INVALID_DURATION (err u109))
(define-constant ERR_NOT_MEMBER (err u110))
(define-constant ERR_REPORT_NOT_FOUND (err u111))
(define-constant ERR_ALREADY_REPORTED (err u112))
(define-constant ERR_INVALID_IMPACT_SCORE (err u113))
(define-constant ERR_REPORT_PERIOD_ENDED (err u114))
(define-constant ERR_NOT_GRANT_RECIPIENT (err u115))
(define-constant ERR_INVALID_VERIFICATION (err u116))

(define-data-var total-proposals uint u0)
(define-data-var treasury-balance uint u0)
(define-data-var min-voting-power uint u1000000)
(define-data-var voting-duration uint u144)
(define-data-var quorum-threshold uint u51)
(define-data-var total-impact-reports uint u0)
(define-data-var report-submission-period uint u1008)

(define-map dao-members principal uint)
(define-map proposals uint {
    id: uint,
    proposer: principal,
    title: (string-ascii 100),
    description: (string-ascii 500),
    recipient: principal,
    amount: uint,
    category: (string-ascii 50),
    created-at: uint,
    voting-ends-at: uint,
    votes-for: uint,
    votes-against: uint,
    executed: bool,
    passed: bool
})
(define-map votes {proposal-id: uint, voter: principal} {vote: bool, power: uint})
(define-map member-voting-power principal uint)
(define-map impact-reports uint {
    report-id: uint,
    proposal-id: uint,
    recipient: principal,
    submitted-at: uint,
    impact-score: uint,
    evidence-hash: (string-ascii 64),
    verified: bool,
    verifier: (optional principal),
    carbon-offset: uint,
    beneficiaries-count: uint,
    project-status: (string-ascii 20)
})
(define-map recipient-reputation principal {
    total-grants: uint,
    completed-projects: uint,
    total-impact-score: uint,
    average-impact: uint,
    reliability-score: uint,
    last-updated: uint
})
(define-map grant-tracking {proposal-id: uint} {
    report-deadline: uint,
    report-submitted: bool,
    final-impact-score: uint
})

(define-private (is-dao-member (user principal))
    (is-some (map-get? dao-members user))
)

(define-private (get-voting-power (user principal))
    (default-to u0 (map-get? member-voting-power user))
)

(define-private (has-voted (proposal-id uint) (voter principal))
    (is-some (map-get? votes {proposal-id: proposal-id, voter: voter}))
)

(define-private (calculate-total-votes (proposal-id uint))
    (let ((proposal (unwrap-panic (map-get? proposals proposal-id))))
        (+ (get votes-for proposal) (get votes-against proposal))
    )
)

(define-private (meets-quorum (proposal-id uint))
    (let (
        (total-votes (calculate-total-votes proposal-id))
        ;; (total-supply (fold + (map values member-voting-power) u0))
        (quorum-needed (/ (* u1 (var-get quorum-threshold)) u100))
    )
        (>= total-votes quorum-needed)
    )
)

(define-private (voting-ended (proposal-id uint))
    (let ((proposal (unwrap-panic (map-get? proposals proposal-id))))
        (> stacks-block-height (get voting-ends-at proposal))
    )
)

(define-private (proposal-passed (proposal-id uint))
    (let ((proposal (unwrap-panic (map-get? proposals proposal-id))))
        (and
            (meets-quorum proposal-id)
            (> (get votes-for proposal) (get votes-against proposal))
        )
    )
)

(define-private (is-report-period-active (proposal-id uint))
    (let (
        (tracking (map-get? grant-tracking {proposal-id: proposal-id}))
    )
        (match tracking
            some-tracking (< stacks-block-height (get report-deadline some-tracking))
            false
        )
    )
)

(define-private (calculate-reliability-score (recipient principal))
    (let (
        (reputation (default-to {
            total-grants: u0,
            completed-projects: u0,
            total-impact-score: u0,
            average-impact: u0,
            reliability-score: u0,
            last-updated: u0
        } (map-get? recipient-reputation recipient)))
        (total-grants (get total-grants reputation))
        (completed-projects (get completed-projects reputation))
    )
        (if (> total-grants u0)
            (/ (* completed-projects u100) total-grants)
            u0
        )
    )
)

(define-private (update-recipient-reputation 
    (recipient principal) 
    (impact-score uint) 
    (project-completed bool)
)
    (let (
        (current-reputation (default-to {
            total-grants: u0,
            completed-projects: u0,
            total-impact-score: u0,
            average-impact: u0,
            reliability-score: u0,
            last-updated: u0
        } (map-get? recipient-reputation recipient)))
        (new-total-grants (+ (get total-grants current-reputation) u1))
        (new-completed (if project-completed 
            (+ (get completed-projects current-reputation) u1)
            (get completed-projects current-reputation)
        ))
        (new-total-impact (+ (get total-impact-score current-reputation) impact-score))
        (new-average-impact (if (> new-total-grants u0) 
            (/ new-total-impact new-total-grants) 
            u0
        ))
        (new-reliability (calculate-reliability-score recipient))
    )
        (map-set recipient-reputation recipient {
            total-grants: new-total-grants,
            completed-projects: new-completed,
            total-impact-score: new-total-impact,
            average-impact: new-average-impact,
            reliability-score: new-reliability,
            last-updated: stacks-block-height
        })
    )
)

(define-public (join-dao (voting-power uint))
    (begin
        (asserts! (>= voting-power (var-get min-voting-power)) ERR_INVALID_AMOUNT)
        (try! (stx-transfer? voting-power tx-sender (as-contract tx-sender)))
        (map-set dao-members tx-sender voting-power)
        (map-set member-voting-power tx-sender voting-power)
        (var-set treasury-balance (+ (var-get treasury-balance) voting-power))
        (ok true)
    )
)

(define-public (leave-dao)
    (let (
        (member-power (unwrap! (map-get? member-voting-power tx-sender) ERR_NOT_MEMBER))
        (treasury (var-get treasury-balance))
    )
        (asserts! (>= treasury member-power) ERR_INSUFFICIENT_FUNDS)
        (try! (as-contract (stx-transfer? member-power tx-sender tx-sender)))
        (map-delete dao-members tx-sender)
        (map-delete member-voting-power tx-sender)
        (var-set treasury-balance (- treasury member-power))
        (ok true)
    )
)

(define-public (create-proposal 
    (title (string-ascii 100))
    (description (string-ascii 500))
    (recipient principal)
    (amount uint)
    (category (string-ascii 50))
)
    (let (
        (proposal-id (+ (var-get total-proposals) u1))
        (voting-ends (+ stacks-block-height (var-get voting-duration)))
    )
        (asserts! (is-dao-member tx-sender) ERR_NOT_MEMBER)
        (asserts! (> amount u0) ERR_INVALID_AMOUNT)
        (asserts! (<= amount (var-get treasury-balance)) ERR_INSUFFICIENT_FUNDS)
        
        (map-set proposals proposal-id {
            id: proposal-id,
            proposer: tx-sender,
            title: title,
            description: description,
            recipient: recipient,
            amount: amount,
            category: category,
            created-at: stacks-block-height,
            voting-ends-at: voting-ends,
            votes-for: u0,
            votes-against: u0,
            executed: false,
            passed: false
        })
        
        (var-set total-proposals proposal-id)
        (ok proposal-id)
    )
)

(define-public (vote-on-proposal (proposal-id uint) (vote bool))
    (let (
        (proposal (unwrap! (map-get? proposals proposal-id) ERR_PROPOSAL_NOT_FOUND))
        (voter-power (get-voting-power tx-sender))
        (current-votes-for (get votes-for proposal))
        (current-votes-against (get votes-against proposal))
    )
        (asserts! (is-dao-member tx-sender) ERR_NOT_MEMBER)
        (asserts! (not (voting-ended proposal-id)) ERR_VOTING_ENDED)
        (asserts! (not (has-voted proposal-id tx-sender)) ERR_ALREADY_VOTED)
        
        (map-set votes {proposal-id: proposal-id, voter: tx-sender} {vote: vote, power: voter-power})
        
        (if vote
            (map-set proposals proposal-id (merge proposal {votes-for: (+ current-votes-for voter-power)}))
            (map-set proposals proposal-id (merge proposal {votes-against: (+ current-votes-against voter-power)}))
        )
        
        (ok true)
    )
)

(define-public (execute-proposal (proposal-id uint))
    (let (
        (proposal (unwrap! (map-get? proposals proposal-id) ERR_PROPOSAL_NOT_FOUND))
        (proposal-amount (get amount proposal))
        (proposal-recipient (get recipient proposal))
        (treasury (var-get treasury-balance))
    )
        (asserts! (voting-ended proposal-id) ERR_VOTING_NOT_ENDED)
        (asserts! (not (get executed proposal)) ERR_PROPOSAL_ALREADY_EXECUTED)
        (asserts! (>= treasury proposal-amount) ERR_INSUFFICIENT_FUNDS)
        
        (let ((passed (proposal-passed proposal-id)))
            (map-set proposals proposal-id (merge proposal {executed: true, passed: passed}))
            
            (if passed
                (begin
                    (try! (as-contract (stx-transfer? proposal-amount tx-sender proposal-recipient)))
                    (var-set treasury-balance (- treasury proposal-amount))
                    (map-set grant-tracking {proposal-id: proposal-id} {
                        report-deadline: (+ stacks-block-height (var-get report-submission-period)),
                        report-submitted: false,
                        final-impact-score: u0
                    })
                    (ok true)
                )
                (ok false)
            )
        )
    )
)

(define-public (update-voting-duration (new-duration uint))
    (begin
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
        (asserts! (> new-duration u0) ERR_INVALID_DURATION)
        (var-set voting-duration new-duration)
        (ok true)
    )
)

(define-public (update-quorum-threshold (new-threshold uint))
    (begin
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
        (asserts! (and (> new-threshold u0) (<= new-threshold u100)) ERR_INVALID_AMOUNT)
        (var-set quorum-threshold new-threshold)
        (ok true)
    )
)

(define-public (update-min-voting-power (new-min uint))
    (begin
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
        (asserts! (> new-min u0) ERR_INVALID_AMOUNT)
        (var-set min-voting-power new-min)
        (ok true)
    )
)

(define-public (emergency-withdraw (amount uint))
    (let ((treasury (var-get treasury-balance)))
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
        (asserts! (<= amount treasury) ERR_INSUFFICIENT_FUNDS)
        (try! (as-contract (stx-transfer? amount tx-sender CONTRACT_OWNER)))
        (var-set treasury-balance (- treasury amount))
        (ok true)
    )
)

(define-public (submit-impact-report 
    (proposal-id uint)
    (impact-score uint)
    (evidence-hash (string-ascii 64))
    (carbon-offset uint)
    (beneficiaries-count uint)
    (project-status (string-ascii 20))
)
    (let (
        (proposal (unwrap! (map-get? proposals proposal-id) ERR_PROPOSAL_NOT_FOUND))
        (tracking (unwrap! (map-get? grant-tracking {proposal-id: proposal-id}) ERR_PROPOSAL_NOT_FOUND))
        (report-id (+ (var-get total-impact-reports) u1))
        (recipient (get recipient proposal))
    )
        (asserts! (is-eq tx-sender recipient) ERR_NOT_GRANT_RECIPIENT)
        (asserts! (not (get report-submitted tracking)) ERR_ALREADY_REPORTED)
        (asserts! (is-report-period-active proposal-id) ERR_REPORT_PERIOD_ENDED)
        (asserts! (and (>= impact-score u0) (<= impact-score u100)) ERR_INVALID_IMPACT_SCORE)
        
        (map-set impact-reports report-id {
            report-id: report-id,
            proposal-id: proposal-id,
            recipient: recipient,
            submitted-at: stacks-block-height,
            impact-score: impact-score,
            evidence-hash: evidence-hash,
            verified: false,
            verifier: none,
            carbon-offset: carbon-offset,
            beneficiaries-count: beneficiaries-count,
            project-status: project-status
        })
        
        (map-set grant-tracking {proposal-id: proposal-id} (merge tracking {
            report-submitted: true,
            final-impact-score: impact-score
        }))
        
        (update-recipient-reputation recipient impact-score true)
        (var-set total-impact-reports report-id)
        (ok report-id)
    )
)

(define-public (verify-impact-report (report-id uint) (verified bool))
    (let (
        (report (unwrap! (map-get? impact-reports report-id) ERR_REPORT_NOT_FOUND))
        (proposal-id (get proposal-id report))
    )
        (asserts! (is-dao-member tx-sender) ERR_NOT_MEMBER)
        (asserts! (not (get verified report)) ERR_INVALID_VERIFICATION)
        
        (map-set impact-reports report-id (merge report {
            verified: verified,
            verifier: (some tx-sender)
        }))
        
        (if verified
            (ok true)
            (begin
                (update-recipient-reputation (get recipient report) u0 false)
                (ok false)
            )
        )
    )
)

(define-public (update-report-submission-period (new-period uint))
    (begin
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
        (asserts! (> new-period u0) ERR_INVALID_DURATION)
        (var-set report-submission-period new-period)
        (ok true)
    )
)

(define-read-only (get-proposal (proposal-id uint))
    (map-get? proposals proposal-id)
)

(define-read-only (get-vote (proposal-id uint) (voter principal))
    (map-get? votes {proposal-id: proposal-id, voter: voter})
)

(define-read-only (get-treasury-balance)
    (var-get treasury-balance)
)

(define-read-only (get-total-proposals)
    (var-get total-proposals)
)

(define-read-only (get-member-info (member principal))
    (map-get? dao-members member)
)

(define-read-only (get-voting-power-info (member principal))
    (map-get? member-voting-power member)
)

(define-read-only (get-dao-settings)
    {
        min-voting-power: (var-get min-voting-power),
        voting-duration: (var-get voting-duration),
        quorum-threshold: (var-get quorum-threshold)
    }
)

(define-read-only (is-proposal-active (proposal-id uint))
    (let ((proposal (map-get? proposals proposal-id)))
        (match proposal
            some-proposal (not (voting-ended proposal-id))
            false
        )
    )
)

(define-read-only (get-proposal-status (proposal-id uint))
    (match (map-get? proposals proposal-id)
        proposal
            (ok
                (if (get executed proposal)
                    (if (get passed proposal) "executed-passed" "executed-failed")
                    (if (voting-ended proposal-id)
                        (if (proposal-passed proposal-id) "voting-ended-passed" "voting-ended-failed")
                        "voting-active"
                    )
                )
            )
        (err "not-found")
    )
)

(define-read-only (get-impact-report (report-id uint))
    (map-get? impact-reports report-id)
)

(define-read-only (get-recipient-reputation (recipient principal))
    (map-get? recipient-reputation recipient)
)

(define-read-only (get-grant-tracking (proposal-id uint))
    (map-get? grant-tracking {proposal-id: proposal-id})
)

(define-read-only (get-total-impact-reports)
    (var-get total-impact-reports)
)

(define-read-only (get-report-submission-period)
    (var-get report-submission-period)
)

(define-read-only (is-report-deadline-active (proposal-id uint))
    (is-report-period-active proposal-id)
)

(define-read-only (calculate-recipient-reliability (recipient principal))
    (calculate-reliability-score recipient)
)

(define-read-only (get-recipient-impact-summary (recipient principal))
    (let (
        (reputation (map-get? recipient-reputation recipient))
    )
        (match reputation
            some-rep {
                total-grants: (get total-grants some-rep),
                completed-projects: (get completed-projects some-rep),
                average-impact: (get average-impact some-rep),
                reliability-percentage: (calculate-reliability-score recipient),
                last-updated: (get last-updated some-rep)
            }
            {
                total-grants: u0,
                completed-projects: u0,
                average-impact: u0,
                reliability-percentage: u0,
                last-updated: u0
            }
        )
    )
)
