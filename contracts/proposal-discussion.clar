;; Proposal Discussion Board for Ecogrant DAO
;; This contract enables DAO members to discuss proposals before voting

;; Error constants
(define-constant ERR_NOT_MEMBER (err u200))
(define-constant ERR_PROPOSAL_NOT_FOUND (err u201))
(define-constant ERR_MESSAGE_TOO_LONG (err u202))
(define-constant ERR_MESSAGE_NOT_FOUND (err u203))
(define-constant ERR_EMPTY_MESSAGE (err u204))

;; Constants
(define-constant MAX_MESSAGE_LENGTH u256)
(define-constant CONTRACT_DEPLOYER tx-sender)

;; Import the main Ecogrant contract for member and proposal validation
(define-constant ECOGRANT_CONTRACT .Ecogrant)

;; Data variables
(define-data-var next-message-id uint u1)

;; Data maps
(define-map proposal-discussions 
    { proposal-id: uint, message-id: uint }
    {
        sender: principal,
        timestamp: uint,
        content: (string-ascii 256)
    }
)

;; Map to track message counts per proposal (for easier retrieval)
(define-map proposal-message-counts uint uint)

;; Private helper functions
(define-private (is-dao-member (user principal))
    (is-some (contract-call? ECOGRANT_CONTRACT get-member-info user))
)

(define-private (proposal-exists (proposal-id uint))
    (is-some (contract-call? ECOGRANT_CONTRACT get-proposal proposal-id))
)

(define-private (increment-message-count (proposal-id uint))
    (let ((current-count (default-to u0 (map-get? proposal-message-counts proposal-id))))
        (map-set proposal-message-counts proposal-id (+ current-count u1))
    )
)

;; Public functions

;; Post a discussion message for a proposal
(define-public (post-discussion-message (proposal-id uint) (message (string-ascii 256)))
    (let (
        (message-id (var-get next-message-id))
        (message-length (len message))
    )
        ;; Validate inputs
        (asserts! (is-dao-member tx-sender) ERR_NOT_MEMBER)
        (asserts! (proposal-exists proposal-id) ERR_PROPOSAL_NOT_FOUND)
        (asserts! (> message-length u0) ERR_EMPTY_MESSAGE)
        (asserts! (<= message-length MAX_MESSAGE_LENGTH) ERR_MESSAGE_TOO_LONG)
        
        ;; Store the message
        (map-set proposal-discussions 
            { proposal-id: proposal-id, message-id: message-id }
            {
                sender: tx-sender,
                timestamp: stacks-block-height,
                content: message
            }
        )
        
        ;; Update counters
        (var-set next-message-id (+ message-id u1))
        (increment-message-count proposal-id)
        
        (ok message-id)
    )
)

;; Read-only functions

;; Get a specific discussion message
(define-read-only (get-discussion-message (proposal-id uint) (message-id uint))
    (map-get? proposal-discussions { proposal-id: proposal-id, message-id: message-id })
)

;; Get the count of messages for a proposal
(define-read-only (get-message-count (proposal-id uint))
    (default-to u0 (map-get? proposal-message-counts proposal-id))
)

;; Get first discussion message for a proposal (simplified version)
(define-read-only (get-first-discussion-message (proposal-id uint))
    (map-get? proposal-discussions { proposal-id: proposal-id, message-id: u1 })
)

;; Get the total number of messages across all proposals
(define-read-only (get-total-messages)
    (- (var-get next-message-id) u1)
)

;; Get discussion statistics
(define-read-only (get-discussion-stats)
    {
        total-messages: (get-total-messages),
        next-message-id: (var-get next-message-id),
        max-message-length: MAX_MESSAGE_LENGTH
    }
)
