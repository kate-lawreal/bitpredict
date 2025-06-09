
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