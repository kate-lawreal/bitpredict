
;; Title: BitPredict - Decentralized Bitcoin Price Prediction Market
;; Summary: A trustless prediction market enabling users to stake STX on Bitcoin price movements
;; Description: BitPredict leverages Stacks Layer 2 to create transparent, oracle-driven 
;; prediction markets where users can stake STX tokens on Bitcoin price 
;; direction (up/down). Winners share the total pool proportionally to their 
;; stake, minus platform fees. Built for Bitcoin DeFi with automated 
;; resolution and fair reward distribution.

;; CONSTANTS & ERROR CODES

;; Administrative Constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))

;; Error Definitions
(define-constant err-not-found (err u101))
(define-constant err-invalid-prediction (err u102))
(define-constant err-market-closed (err u103))
(define-constant err-already-claimed (err u104))
(define-constant err-insufficient-balance (err u105))
(define-constant err-invalid-parameter (err u106))

;; STATE VARIABLES

;; Platform Configuration
(define-data-var oracle-address principal 'ST1PQHQKV0RJXZFY1DGX8MNSNYVE3VGZJSRTPGZGM)
(define-data-var minimum-stake uint u1000000) ;; 1 STX minimum stake
(define-data-var fee-percentage uint u2)      ;; 2% platform fee
(define-data-var market-counter uint u0)      ;; Global market ID counter

;; DATA STRUCTURES

;; Market Information Storage
(define-map markets
    uint
    {
        start-price: uint,        ;; Initial Bitcoin price (in satoshis)
        end-price: uint,          ;; Final Bitcoin price (in satoshis)
        total-up-stake: uint,     ;; Total STX staked on price going up
        total-down-stake: uint,   ;; Total STX staked on price going down
        start-block: uint,        ;; Block when predictions open
        end-block: uint,          ;; Block when predictions close
        resolved: bool            ;; Market resolution status
    }
)

;; User Prediction Tracking
(define-map user-predictions
    {market-id: uint, user: principal}
    {
        prediction: (string-ascii 4), ;; "up" or "down"
        stake: uint,                  ;; Amount of STX staked
        claimed: bool                 ;; Reward claim status
    }
)

;; PUBLIC FUNCTIONS - MARKET MANAGEMENT

;; Create New Prediction Market
;; Creates a new Bitcoin price prediction market with specified parameters
(define-public (create-market (start-price uint) (start-block uint) (end-block uint))
    (let
        (
            (market-id (var-get market-counter))
        )
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (asserts! (> end-block start-block) err-invalid-parameter)
        (asserts! (> start-price u0) err-invalid-parameter)
        
        (map-set markets market-id
            {
                start-price: start-price,
                end-price: u0,
                total-up-stake: u0,
                total-down-stake: u0,
                start-block: start-block,
                end-block: end-block,
                resolved: false
            }
        )
        (var-set market-counter (+ market-id u1))
        (ok market-id)
    )
)

;; Resolve Market with Final Price
;; Oracle function to resolve market with final Bitcoin price
(define-public (resolve-market (market-id uint) (end-price uint))
    (let
        (
            (market (unwrap! (map-get? markets market-id) err-not-found))
        )
        (asserts! (is-eq tx-sender (var-get oracle-address)) err-owner-only)
        (asserts! (>= stacks-block-height (get end-block market)) err-market-closed)
        (asserts! (not (get resolved market)) err-market-closed)
        (asserts! (> end-price u0) err-invalid-parameter)

        (map-set markets market-id
            (merge market
                {
                    end-price: end-price,
                    resolved: true
                }
            )
        )
        (ok true)
    )
)

;; PUBLIC FUNCTIONS - USER INTERACTIONS

;; Make Price Prediction
;; Allows users to stake STX on Bitcoin price direction
(define-public (make-prediction (market-id uint) (prediction (string-ascii 4)) (stake uint))
    (let
        (
            (market (unwrap! (map-get? markets market-id) err-not-found))
            (current-block stacks-block-height)
        )
        (asserts! (and (>= current-block (get start-block market)) 
                      (< current-block (get end-block market))) 
                 err-market-closed)
        (asserts! (or (is-eq prediction "up") (is-eq prediction "down")) 
                 err-invalid-prediction)
        (asserts! (>= stake (var-get minimum-stake)) 
                 err-invalid-prediction)
        (asserts! (<= stake (stx-get-balance tx-sender)) 
                 err-insufficient-balance)

        ;; Transfer stake to contract
        (try! (stx-transfer? stake tx-sender (as-contract tx-sender)))

        ;; Record user prediction
        (map-set user-predictions 
            {market-id: market-id, user: tx-sender}
            {prediction: prediction, stake: stake, claimed: false}
        )

        ;; Update market stake totals
        (map-set markets market-id
            (merge market
                {
                    total-up-stake: (if (is-eq prediction "up")
                                    (+ (get total-up-stake market) stake)
                                    (get total-up-stake market)),
                    total-down-stake: (if (is-eq prediction "down")
                                      (+ (get total-down-stake market) stake)
                                      (get total-down-stake market))
                }
            )
        )
        (ok true)
    )
)

;; Claim Prediction Winnings
;; Allows winners to claim their proportional share of the prize pool
(define-public (claim-winnings (market-id uint))
    (let
        (
            (market (unwrap! (map-get? markets market-id) err-not-found))
            (prediction (unwrap! (map-get? user-predictions {market-id: market-id, user: tx-sender}) err-not-found))
        )
        (asserts! (get resolved market) err-market-closed)
        (asserts! (not (get claimed prediction)) err-already-claimed)

        (let
            (
                (winning-prediction (if (> (get end-price market) (get start-price market)) "up" "down"))
                (total-stake (+ (get total-up-stake market) (get total-down-stake market)))
                (winning-stake (if (is-eq winning-prediction "up") 
                               (get total-up-stake market) 
                               (get total-down-stake market)))
            )
            (asserts! (is-eq (get prediction prediction) winning-prediction) err-invalid-prediction)
            
            (let
                (
                    (winnings (/ (* (get stake prediction) total-stake) winning-stake))
                    (fee (/ (* winnings (var-get fee-percentage)) u100))
                    (payout (- winnings fee))
                )
                ;; Transfer winnings to user
                (try! (as-contract (stx-transfer? payout (as-contract tx-sender) tx-sender)))
                ;; Transfer fees to contract owner
                (try! (as-contract (stx-transfer? fee (as-contract tx-sender) contract-owner)))
                
                ;; Mark as claimed
                (map-set user-predictions 
                    {market-id: market-id, user: tx-sender}
                    (merge prediction {claimed: true})
                )
                (ok payout)
            )
        )
    )
)

;; READ-ONLY FUNCTIONS

;; Get Market Information
;; Returns complete market data for given market ID
(define-read-only (get-market (market-id uint))
    (map-get? markets market-id)
)

;; Get User Prediction Details
;; Returns user's prediction data for specific market
(define-read-only (get-user-prediction (market-id uint) (user principal))
    (map-get? user-predictions {market-id: market-id, user: user})
)

;; Get Contract STX Balance
;; Returns total STX held by the contract
(define-read-only (get-contract-balance)
    (stx-get-balance (as-contract tx-sender))
)

;; ADMINISTRATIVE FUNCTIONS

;; Update Oracle Address
;; Changes the oracle address authorized to resolve markets
(define-public (set-oracle-address (new-address principal))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (asserts! (is-eq new-address new-address) err-invalid-parameter)
        (ok (var-set oracle-address new-address))
    )
)

;; Update Minimum Stake Requirement
;; Adjusts the minimum STX required for predictions
(define-public (set-minimum-stake (new-minimum uint))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (asserts! (> new-minimum u0) err-invalid-parameter)
        (ok (var-set minimum-stake new-minimum))
    )
)

;; Update Platform Fee Percentage
;; Modifies the platform fee taken from winnings
(define-public (set-fee-percentage (new-fee uint))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (asserts! (<= new-fee u100) err-invalid-parameter)
        (ok (var-set fee-percentage new-fee))
    )
)

;; Withdraw Platform Fees
;; Allows contract owner to withdraw accumulated fees
(define-public (withdraw-fees (amount uint))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (asserts! (<= amount (stx-get-balance (as-contract tx-sender))) err-insufficient-balance)
        (try! (as-contract (stx-transfer? amount (as-contract tx-sender) contract-owner)))
        (ok amount)
    )
)