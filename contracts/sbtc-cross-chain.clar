
;; Title: sBTC Cross-Chain Bridge

;; Summary
;; This smart contract implements a secure cross-chain bridge for sBTC (Stacks Bitcoin),
;; enabling trustless token transfers between blockchains. The system employs
;; multi-signature security and implements the SIP-010 fungible token standard.

;; Constants and Definitions

;; SIP-010 Trait Definition
(define-trait sip-010-trait
    (
        (transfer (uint principal principal (optional (buff 34))) (response bool uint))
        (get-balance (principal) (response uint uint))
        (get-total-supply () (response uint uint))
        (get-decimals () (response uint uint))
        (get-name () (response (string-ascii 32) uint))
        (get-symbol () (response (string-ascii 32) uint))
        (get-token-uri () (response (optional (string-utf8 256)) uint))
    )
)

;; Error Codes
(define-constant ERR-NOT-AUTHORIZED (err u1000))
(define-constant ERR-INVALID-AMOUNT (err u1001))
(define-constant ERR-INSUFFICIENT-BALANCE (err u1002))
(define-constant ERR-BRIDGE-PAUSED (err u1003))
(define-constant ERR-INVALID-TOKEN (err u1004))
(define-constant ERR-INVALID-DESTINATION (err u1005))
(define-constant ERR-SWAP-NOT-FOUND (err u1006))
(define-constant ERR-SWAP-ALREADY-COMPLETED (err u1007))
(define-constant ERR-SWAP-EXPIRED (err u1008))
(define-constant ERR-INVALID-SIGNATURE (err u1009))

;; Configuration Constants
(define-constant BASIS-POINTS u10000)

;; State Variables
(define-data-var contract-owner principal tx-sender)
(define-data-var paused bool false)
(define-data-var bridge-fee uint u100) ;; 1% (100 basis points)
(define-data-var minimum-amount uint u1000000) ;; Minimum amount in satoshis
(define-data-var nonce uint u0)

;; Data Maps
(define-map authorized-signers principal bool)
(define-map supported-tokens principal bool)
(define-map bridge-balances {token: principal, owner: principal} uint)
(define-map pending-swaps
    uint
    {
        initiator: principal,
        token: principal,
        amount: uint,
        destination-chain: (string-ascii 32),
        destination-address: (buff 42),
        timeout: uint,
        completed: bool,
        signatures: (list 10 principal)
    }
)

;; Helper Functions
(define-private (calculate-fee (amount uint))
    (/ (* amount (var-get bridge-fee)) BASIS-POINTS))

;; Administrative Functions
(define-public (set-contract-owner (new-owner principal))
    (begin
        (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
        (ok (var-set contract-owner new-owner))))

(define-public (set-bridge-fee (new-fee uint))
    (begin
        (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
        (asserts! (<= new-fee u1000) ERR-INVALID-AMOUNT) ;; Max 10%
        (ok (var-set bridge-fee new-fee))))

(define-public (set-minimum-amount (amount uint))
    (begin
        (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
        (ok (var-set minimum-amount amount))))

(define-public (toggle-pause)
    (begin
        (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
        (ok (var-set paused (not (var-get paused))))))

(define-public (add-authorized-signer (signer principal))
    (begin
        (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
        (ok (map-set authorized-signers signer true))))

(define-public (remove-authorized-signer (signer principal))
    (begin
        (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
        (ok (map-set authorized-signers signer false))))

(define-public (add-supported-token (token principal))
    (begin
        (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
        (ok (map-set supported-tokens token true))))

(define-public (remove-supported-token (token principal))
    (begin
        (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
        (ok (map-set supported-tokens token false))))

;; Core Bridge Functions

;; Bridge Transfer Initiation
(define-public (initiate-bridge-transfer 
    (token-contract <sip-010-trait>)
    (amount uint)
    (destination-chain (string-ascii 32))
    (destination-address (buff 42)))
    (let
        ((token (contract-of token-contract))
         (current-nonce (var-get nonce))
         (fee-amount (calculate-fee amount)))
        (asserts! (not (var-get paused)) ERR-BRIDGE-PAUSED)
        (asserts! (default-to false (map-get? supported-tokens token)) ERR-INVALID-TOKEN)
        (asserts! (>= amount (var-get minimum-amount)) ERR-INVALID-AMOUNT)
        (try! (contract-call? token-contract transfer amount tx-sender (as-contract tx-sender) none))
        (map-set pending-swaps
            current-nonce
            {
                initiator: tx-sender,
                token: token,
                amount: (- amount fee-amount),
                destination-chain: destination-chain,
                destination-address: destination-address,
                timeout: (+ block-height u144), ;; 24 hours in blocks
                completed: false,
                signatures: (list)
            })
        (var-set nonce (+ current-nonce u1))
        (ok current-nonce)))

;; Bridge Transfer Signing
(define-public (sign-bridge-transfer (swap-id uint))
    (let ((swap (unwrap! (map-get? pending-swaps swap-id) ERR-SWAP-NOT-FOUND))
          (signatures (get signatures swap)))
        (asserts! (not (var-get paused)) ERR-BRIDGE-PAUSED)
        (asserts! (default-to false (map-get? authorized-signers tx-sender)) ERR-NOT-AUTHORIZED)
        (asserts! (not (get completed swap)) ERR-SWAP-ALREADY-COMPLETED)
        (asserts! (< block-height (get timeout swap)) ERR-SWAP-EXPIRED)
        (asserts! (not (is-some (index-of signatures tx-sender))) ERR-INVALID-SIGNATURE)
        (ok (map-set pending-swaps
            swap-id
            (merge swap {signatures: (unwrap! (as-max-len? (append signatures tx-sender) u10) ERR-INVALID-SIGNATURE)})))))

;; Bridge Transfer Completion
(define-public (complete-bridge-transfer (swap-id uint) (token-contract <sip-010-trait>))
    (let 
        ((swap (unwrap! (map-get? pending-swaps swap-id) ERR-SWAP-NOT-FOUND))
         (signatures (get signatures swap))
         (token (contract-of token-contract)))
        (asserts! (not (var-get paused)) ERR-BRIDGE-PAUSED)
        (asserts! (not (get completed swap)) ERR-SWAP-ALREADY-COMPLETED)
        (asserts! (>= (len signatures) u3) ERR-INVALID-SIGNATURE) ;; Minimum 3 signatures required
        (asserts! (< block-height (get timeout swap)) ERR-SWAP-EXPIRED)
        (asserts! (is-eq token (get token swap)) ERR-INVALID-TOKEN)
        (try! (as-contract 
            (contract-call? 
                token-contract
                transfer 
                (get amount swap) 
                (as-contract tx-sender) 
                (get initiator swap) 
                none)))
        (ok (map-set pending-swaps swap-id (merge swap {completed: true})))))

;; Expired Transfer Cancellation
(define-public (cancel-expired-transfer (swap-id uint) (token-contract <sip-010-trait>))
    (let 
        ((swap (unwrap! (map-get? pending-swaps swap-id) ERR-SWAP-NOT-FOUND))
         (token (contract-of token-contract)))
        (asserts! (> block-height (get timeout swap)) ERR-SWAP-EXPIRED)
        (asserts! (not (get completed swap)) ERR-SWAP-ALREADY-COMPLETED)
        (asserts! (is-eq token (get token swap)) ERR-INVALID-TOKEN)
        (try! (as-contract 
            (contract-call? 
                token-contract
                transfer 
                (get amount swap) 
                (as-contract tx-sender) 
                (get initiator swap) 
                none)))
        (ok (map-set pending-swaps swap-id (merge swap {completed: true})))))

;; Read-Only Functions
(define-read-only (get-pending-swap (swap-id uint))
    (map-get? pending-swaps swap-id))

(define-read-only (is-signer (account principal))
    (default-to false (map-get? authorized-signers account)))

(define-read-only (get-bridge-fee)
    (var-get bridge-fee))

(define-read-only (get-minimum-amount)
    (var-get minimum-amount))

(define-read-only (is-token-supported (token principal))
    (default-to false (map-get? supported-tokens token)))

(define-read-only (is-paused)
    (var-get paused))

;; Contract Initialization
(map-set authorized-signers (var-get contract-owner) true)