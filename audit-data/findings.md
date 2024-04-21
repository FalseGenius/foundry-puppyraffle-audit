### [H-01] Deleting the player from `PuppyRaffle::players` array after refunding them entranceFee in `PuppyRaffle::refund()` results in Reentrancy vulnerability, draining the contract balance.

**Description:** `PuppyRaffle::refund()` allows players to refund their deposits by initiating external call first and subsequently setting the user's address to zero in `PuppyRaffle::players()` . This introduces a vulnerability to Reentrancy attack, where attacker could deploy a contract with a malicious fallback() function to retrigger`PuppyRaffle::refund()`. Since user remains in `PuppyRaffle::players()` at this point, they would successfully pass all checks, leading to repeatedly executions of sendValue, ultimately draining the contract.

```javascript
@>      payable(msg.sender).sendValue(entranceFee); // Reentrancy here
        players[playerIndex] = address(0);
```

**Impact:** The reentrancy vulnerability could result in a significant drain on contract's balance, potentially leading to financial losses for the contract owner and participants.

**Proof of Concept:**

**Recommended Mitigation:** 


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